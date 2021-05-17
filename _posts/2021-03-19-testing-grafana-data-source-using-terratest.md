---
layout: post
title:  "Testing Grafana data source using Terretest"
date:   2021-03-19 00:00:00 -0000
categories: posts
---


When setting up a kubernetes cluster, one of the issues that we have faced repeatedly is the lack of integration
testing between the core components.  Nearly all the components we install in kubernetes are provided by
third parties, via helm charts or operators,  where adding/changing the tests can be hard (raising a PR) or
flat out impossible.  Here, we demonstrate how we started doing integration testing &mdash; to test that Grafana
was able to retrieve metrics from Prometheus.

Installation of components can usually be done just by following the quick start guide , deviation
from the "happy path" or when things start breaking, debugging the problem becomes extremely hard
with increased number of components/team members/deployment cycle. Although we were using
[Terratest](https://terratest.gruntwork.io) to validate the setup of individual components,
checking that all the services are communicating correctly always appeared to be one step too far
in terms of effort.  Until of course when manual checks becomes too expensive then you find ways to automate.


### The setup

We are doing the simplest setup here via helm charts to install both Prometheus and Grafana.

```sh
helm install prometheus https://prometheus-community.github.io/helm-charts/prometheus
helm install grafana https://grafana.github.io/helm-charts/grafana
```

Unfortunately, the standard setup is not going to work out of the box, so we have to introduce a `datasource`
into a `values.yaml` when installing Grafana.    
```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-server
        access: proxy
        isDefault: true
```

To confirm that the installation is working, we can login to Grafana after deployment and add an appropriate
dashboard to see the nice graphs. Doing this for every deployment is mundane; the recommended way is to
install dashboards is by defining them in the `values.yaml` as below.  Now we have a minimal setup that is
valid even on a laptop, but we have no way to tell if this setup is correct.

```yaml
dashboards:
  default-provider:
    prometheus-dashboard:
      gnetId: 10000
      revision: 1
      datasource: Prometheus
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'default-provider'
        orgId: 1
        folder: ''
        type: file
        updateIntervalSeconds: 30
        disableDeletion: true
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default-provider
```

### Automating using Terratest

Logging into Grafana every time to check if the dashboard is working will cost a significant amount of time &mdash;
proportional to the frequency of deployment &mdash; and the laziness in us will simply skip manual checks
eventually.  You are going to ask "How do you check something visual like a dashboard without looking at it?"
and that is a fair question.  The answer of this question can be broken up, because a dashboard is composed of

1. The setup of the visualization and
2. the metrics is being retrieved correctly.
   
We are not going to  address the visualization component here, and solely focus on testing the data
connection (to Prometheus).  First, let's setup the test function using Terratest which creates a new namespace
for this dedicated test that will be torn down on completion.

```golang
package test

import (
	"crypto/tls"
	"fmt"
	"github.com/gruntwork-io/terratest/modules/helm"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/random"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"strings"
	"testing"
	"time"
)

func TestGrafanaDataSource(t *testing.T) {
    // a total of 5 minutes, which is how long a normal helm install --wait takes
    retries := 10
    sleepBetweenRetries := 30 * time.Second
    // create a random namespace which we will use for testing
    namespaceName := fmt.Sprintf(
    	"%s-%s",
    	strings.ToLower(t.Name()),
        strings.ToLower(random.UniqueId()),
    )
    kubectlOptions := k8s.NewKubectlOptions("", "", namespaceName)
    defer k8s.DeleteNamespace(t, kubectlOptions, namespaceName)
    k8s.CreateNamespace(t, kubectlOptions, namespaceName)
}
```

Next we are going to install Prometheus via helm, with all but the main server component disabled as they
are essential for this test.  Helm repositories are added dynamically under a random name which will
also be deleted upon completion to increase reproducibility across machines/environments.

```golang
func TestGrafanaDataSource(t *testing.T) {
	/*
	    Previous code block
	*/
	prometheusChartName := "prometheus"

	prometheusOptions := &helm.Options{
		KubectlOptions: kubectlOptions,
		SetValues: map[string]string{
			"alertmanager.enabled":            "false",
			"kubeStateMetrics.enabled":        "false",
			"nodeExporter.enabled":            "false",
			"pushgateway.enabled":             "false",
			"server.persistentVolume.enabled": "false",
		},
	}

	prometheusRepo := strings.ToLower(fmt.Sprintf("terratest-%s", random.UniqueId()))
	defer helm.RemoveRepo(t, prometheusOptions, prometheusRepo)
	helm.AddRepo(t, prometheusOptions, prometheusRepo, "https://prometheus-community.github.io/helm-charts")
	prometheusHelmChart := fmt.Sprintf("%s/%s", prometheusRepo, prometheusChartName)
	
	helm.Install(t, prometheusOptions, prometheusHelmChart, prometheusChartName)
	defer helm.Delete(t, prometheusOptions, prometheusChartName, true)
}
```

Then install Grafana in a similar manner using a values file containing the Prometheus datasource information
like we did before.  Additionally, we set the admin password to `admin` for the purpose of this test, this is
to ensure that we can make use of the Grafana api directly.  Please remember that this is an example and
using `admin` as a password is not recommended at all times.

```golang
func TestGrafanaDataSource(t *testing.T) {
    /*
	    Previous code block
    */
	grafanaChartName := "grafana"

	grafanaOptions := &helm.Options{
		KubectlOptions: kubectlOptions,
		ValuesFiles:    []string{"grafana-values.yaml"},
		SetValues: map[string]string{
			"adminPassword": "admin",
		},
	}

	grafanaRepo := strings.ToLower(fmt.Sprintf("terratest-%s", random.UniqueId()))
	defer helm.RemoveRepo(t, grafanaOptions, grafanaRepo)
	helm.AddRepo(t, grafanaOptions, grafanaRepo, "https://grafana.github.io/helm-charts")
	grafanaHelmChart := fmt.Sprintf("%s/%s", grafanaRepo, grafanaChartName)

	helm.Install(t, grafanaOptions, grafanaHelmChart, grafanaChartName)
	defer helm.Delete(t, grafanaOptions, grafanaChartName, true)
}
```

Now we can confirm that the test works by running `go test -v .`, which should show that a new namespace
has been created with both Prometheus and Grafana installed (then deleted).   After celebrating in joy
that we are close to running this test in CI, there is one last step to achieve our original goal.

Grafana allow proxy calls to the original data source via REST api calls.  To check if prometheus is working
or not, we will normally do `curl "$PROMETHEUS_URL/-/ready"` to check for a 200 response.  A more comprehensive
check would be to query specific metrics via `api/v1/` as stated in
the [documentation](https://prometheus.io/docs/prometheus/latest/querying/api/); we take the middle approach
here to just query the status of Prometheus.  This is done by going through the Grafana pods, captured
by filtering on the labels, then create a port forward so that a http call can be made.  A 502 will be return
when the connection from Grafana to Prometheus fails, and a 200 otherwise.  Alternatively we can test against
the service directly using the same approach but use
`k8s.ListServices(t, kubectlOptions, filter)` and
`k8s.NewTunnel(kubectlOptions, k8s.ResourceTypeService, service.Name, 0, 80)` to find the service and create
the port forward respectively.

Running `go test` again (will hopefully) shows a full workflow: creating the namespace, install the
helm charts, http call to Grafana which proxy to Prometheus via the stored configuration, delete the helm charts,
and finally remove the temporary namespace.

```golang
func TestGrafanaDataSource(t *testing.T) {
    /*
	    Previous code block
    */
	// find all the pods that satisfies the filters, then wait until all of them are available
	filters := metav1.ListOptions{
		LabelSelector: fmt.Sprintf("app.kubernetes.io/name=grafana"),
	}
	pods := k8s.ListPods(t, kubectlOptions, filters)

	for _, pod := range pods {
		k8s.WaitUntilPodAvailable(t, kubectlOptions, pod.Name, retries, sleepBetweenRetries)
		// We are going to create a tunnel to every pod and validate that all the pods
		// can query prometheus.  There are going to be people arguing that we should just test against the service
		// which will also validate the service -> pod mapping at the same time.  We are going to ignore them.
		tunnel := k8s.NewTunnel(kubectlOptions, k8s.ResourceTypePod, pod.Name, 0, 3000)
		tunnel.ForwardPort(t)
		// We know that the datasource is 1 because that is the only datasource we have
		endpoint := fmt.Sprintf("http://admin:admin@%s/api/datasources/proxy/1/api/v1/query?query=up", tunnel.Endpoint())
		// We are only testing a 200.  The query proxy to prometheus directly, and we only want
		// to check connectivity.  If the url cannot be reached then it throws a 502 error.
		http_helper.HttpGetWithRetryWithCustomValidation(
			t,
			fmt.Sprintf(endpoint),
			&tls.Config{},
			retries,
			sleepBetweenRetries,
			func(statusCode int, body string) bool {
				return statusCode == 200
			},
		)
		tunnel.Close()
	}
}
```

The principle here is that we hit the Prometheus api via Grafana and completes a simple integration test.
Testing for other data sources can be done following a similar pattern where we make a proxy request to the
destination backend.  Applying the test shown here in CI can be as simply as running the code as is against a
temporary environment such as [kind](https://kind.sigs.k8s.io), or require significant change due to
credentials retrieval, shared infrastructure, etc. The golang code above can be found
[as a gist](https://www.github.com/edwintye/k8s-local-env/main/test/gist/prometheus_grafana_datasource_test.go) and I
hope you have learnt something today :).

---
**NOTE**
Both the Prometheus and Grafana helm chart make use of `ClusterRole` and may clash when testing is
performed against a shared environments.  

---

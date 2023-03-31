---
title: "Testing Custom Resource in Helm charts"
date: 2023-04-01
tags:
  - golang
  - programming
  - testing
---

## Introduction
In the [previous post]( {{< ref "2023-03-29-helm-deployment-examples" >}} ) we talked about how we would
generate example manifests based on common deployment values.  Here we follow up and look at
how we would validate Custom Resource (CR) in a helm chart where the `kubectl apply --dry-run` is
not possible. Even in the case where a dry run is possible, that would require the k8s controller
we are targeting be CRD-aware. If we are going to make the effort and create a proper k8s testbed then the only
upside with the approach in this post is the speed of execution and parallel testing of multiple api version.

### TL;DR
> Although the focus here is on the opentelemetry operator CR, the general pattern of using go tests is
> valid via the sequence:
> 1. Import the desired operator version.
> 2. Unmarshal and validate the CR against the api definition.
> 3. Extract components/configs out of the CR for further validation.

## Let's start testing
Without a loss of generality, we assume that a CR like `examples/sidecar/rendered/sidecar.yaml` exists[^1]. 
The goal here is to confirm that the CR is valid for the corresponding CRD `(kind,apiVersion)` and the
operator running in the cluster is compatible. Since testing native k8s resources is relatively
trivial we will skip over completely. We also expect reader to know golang (and maybe a minimal amount of
k8s internals).

First we need to determine the correct operator version (aka image tag if you are confused here) we wish to
test and import that via `go.mod`. The package should have the api object defined (line 2) and can be
initialized (line 7). Rest of the test function is simply extracting bits of information out of the CR and
asserting the content like any standard unit test.

```go {linenos=true, hl_lines=[2,9]}
package operator_test
import "github.com/open-telemetry/opentelemetry-operator/apis/v1alpha1"
// some necessary import not shown
const testSidecarFile = "examples/sidecar/rendered/sidecar.yaml"
var logger = logf.Log.WithName("unit-tests") // "sigs.k8s.io/controller-runtime/pkg/log"

func TestOpenTelemetrySidecar(t *testing.T) {
	// Initialize the object and try map the manifest into it
	otelcol := v1alpha1.OpenTelemetryCollector{}
	err := unmarshal(&otelcol, testSidecarFile)
	require.NoError(t, err, otelcol)
	err = otelcol.ValidateCreate()
	require.NoError(t, err)
	// rudimentary sanity check, note the use of * as the field is nullable
	assert.GreaterOrEqual(t, *otelcol.Spec.Autoscaler.MinReplicas, int32(0))
	assert.GreaterOrEqual(t, *otelcol.Spec.Autoscaler.MaxReplicas, *otelcol.Spec.Autoscaler.MinReplicas)
	// extract the config from the CR for further validation
	config, err := adapters.ConfigFromString(otelcol.Spec.Config)
	assert.NoError(t, err, otelcol.Spec.Config)
	// we assert the default receiver ports
	ps, err := adapters.ConfigToReceiverPorts(logger, config)
	assert.NoError(t, err, otelcol.Spec.Config)
	for _, service := range ps {
		switch service.Name {
		case "otlp-grpc":
			assert.Equal(t, int32(4317), service.Port)
		case "otlp-http":
			assert.Equal(t, int32(4318), service.Port)
		}
	}
}
// just a random custom unmarshal for repeatability :)
func unmarshal(cfg interface{}, configFile string) error {
	yamlFile, err := os.ReadFile(configFile)
	if err != nil {
		return err
	}
	if err = yaml.UnmarshalStrict(yamlFile, cfg); err != nil {
		return fmt.Errorf("error unmarshaling YAML: %w", err)
	}
	return nil
}
```

Of course, the test here is quite rudimentary &mdash; the CR is valid against the CRD and the information we have
defined makes sense up to a certain extent.  For a start, validating multiple api versions require multiple test
cases as they are different objects. We can import multiple api version, i.e. add additional
import to line 2 above, and also check whether the api object can upgrade to a newer version. However, this
level of check is more effort than what's worth and we can simply find out the compatibility directly from
the CRD definition.  Querying the crd definition (if the yaml cannot be found online you can always output it
into yaml from an active cluster)

```shell
yq '.spec.versions[].name' <name-of-crd>.yaml
```

returns a list of `name`, which is the `apiVersion` used in the CR manifests. There are additional useful
information in the array `.spec.version` which again we are going to gloss over ~~because we can **whoop whoop**~~.

Finally, we have not actually checked the validity of the config `otelcol.Spec.Config`
completely. The operator actually writes it out to a `ConfigMap` and then mounted to the pod where the
opentelemetry collector binary picks it up. A proper equivalent test is beyond the scope here and we end by
simply writing the config to a file for the next stage of testing if we truly want to go that far :).

{{< tabs >}}

{{< tab "Raw yaml" >}}
```go
func TestWriteConfigToFile(t *testing.T) {
	err = os.WriteFile("config.yaml", []byte(otelcol.Spec.Config), 0644)
    require.NoError(t, err)
}
```
{{< /tab >}}

{{< tab "ConfigMap" >}}
```go
func TestWriteConfigMapToFile(t *testing.T) {
    cm := corev1.ConfigMap{
        TypeMeta:   metav1.TypeMeta{},
        ObjectMeta: metav1.ObjectMeta{},
        Immutable:  nil,
        Data:       map[string]string{"config.yaml": otelcol.Spec.Config},
        BinaryData: nil,
    }
    var cmOutput []byte
    _, err = cm.MarshalTo(cmOutput)
    require.NoError(t, err)
    err = os.WriteFile("sidecar-configmap.yaml", cmOutput, 0644)
    assert.NoError(t, err)
}

```
{{< /tab >}}

{{< /tabs >}}

---

[^1]: We lean strongly into the opentelemetry stuff as examples since we run this internally and is more or
      less a copy and paste without much adjustment.

---
title: "Enhance Monitoring with Prometheus Service Monitor"
date: 2022-07-15
tags:
  - monitoring
---

Prometheus allows us to gather application metrics and perform real time monitoring/alerting.  If you are using
it in k8s, it is likely that you have the following annotation in the yaml as you are using the old (and default)
flavor of Prometheus:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/metrics"
  prometheus.io/port: "8080"
```

which informs prometheus to "pull" the data via the `/metrics` endpoint from the application. However, one of
the problem arises if you need to monitor the metrics for multiple containers in the same pod. A common scenario
is where the application has a redis sidecar to handle cache.  There are applications that can parse multiple
annotations through by breaking down into steps/stages, for example filebeat supports the following

```yaml
annotations:
  co.elastic.logs.redis/module: "redis"
  co.elastic.logs.some-application/json.keys_under_root: "true"
```

which would allow separate parsing of the logs according to the user specified format. Unfortunately Prometheus
does not provide that feature and instead asks the operators to upgrade to the
[operator version](https://github.com/prometheus-operator/prometheus-operator) which provides a
new CRD called `ServiceMonitor`.  The idea behind `ServiceMonitor` is that it tells the prometheus operator
which services it should retrieve the metrics via labels, and look at the (pod) endpoints that is binded to
the services. More concretely,

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: app
spec:
  selector:
    matchLabels:
      metrics: prometheus
  endpoints:
    - port: http
```

will select all the pods that has a service with the labels `metrics: prometheus` and endpoint
`http` as a named port. Because `ServiceMonitor` detects via labels, the infra team can deploy generic
monitoring for the different types of service that could be running. If we want to monitor redis, then
we match the label of something say `exporter: redis` 

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis
  labels:
    team: infra
spec:
  selector:
    matchLabels:
      exporter: redis
  endpoints:
    - port: exporter
```

assuming that the services has the appropriate labels such as below.  Now the exporter label can be other
things such as `exporter: mongodb`, `exporter: fastly`, or one from the
[list here](https://prometheus.io/docs/instrumenting/exporters/). This really enhanced the monitoring as
all the containers within a pod can be monitored simultaneously. Of course, if you are using multiple exporter
sidecar then `exporter: redis` is not going to end well with a clash in labels, but having multiple exporter
in the same pod is definitely a sign of bad design.  Additionally, the deliberate choice of `exporter: redis` rather
than something more generic like `prometheus: exporter` is that it acts as a reminder/self-documentation
that 1.) we have redis (or X) running and 2.) remember to add the corresponding dashboard in Grafana.

```yaml
kind: Service
apiVersion: v1
metadata:
  name: some-application
  labels:
    metrics: prometheus
    exporter: redis
spec:
  selector:
    app: some-application
  ports:
    - name: http
      port: 8080
    - name: exporter
      port: 9121
```

---
title:  "Opentelemetry collector to Grafana Cloud"
date:   2023-12-19
tags:
  - programming
  - monitoring
---

## Introduction

At
[ObservabilityCON2023 Grafana labs announced](https://www.youtube.com/live/ydlv_V3dyXk?si=3CIwjPlBi4IoN01D&t=1443)
[Application Observability](https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/)
which was really exciting and it has been our go-to for service health overview ever since.
Since there are a few niche requirements for the panels to full light up, such as
`span_kind=~"SPAN_KIND_SERVER|SPAN_KIND_CONSUMER"` it is beneficial to have a local test setup when
adding instrumentation to a new service.  

Most of the work is already done for those using [grafana agent](https://github.com/grafana/agent) but of course
I am much more of an Opentelemetry person so this is to demonstrate what a setup would look like.

## Opentelemetry config

Below we have a minimal config which can be used locally, where the urls/usernames/passwords
are all injected via environment variables. Note that with the correct permission we can use
the same API key across loki/mimir/tempo even though they all have different tenant ids.

```yaml
receivers:
  otlp:
    protocols:
      grpc:
      http:
connectors:
  spanmetrics:
    histogram:
    namespace: otelcol
  servicegraph:
processors:
  resource:
    attributes:
      - action: insert
        key: deployment.environment
        value: local
  metricstransform:
    transforms:
      - include: otelcol.calls
        action: update
        new_name: traces.spanmetrics.calls.total
      - include: otelcol.duration
        action: update
        new_name: traces.spanmetrics.latency
exporters:
  prometheusremotewrite:
    endpoint: ${env:PROMETHEUS_URL}
    auth:
      authenticator: basicauth/metrics
    add_metric_suffixes: false
  loki:
    endpoint: ${env:LOKI_URL}
    auth:
      authenticator: basicauth/logs
    default_labels_enabled:
      exporter: true
      job: true
  otlp/tempo:
    endpoint: ${env:TEMPO_URL}
    auth:
      authenticator: basicauth/traces
extensions:
  basicauth/logs:
    client_auth:
      username: ${env:LOKI_USERNAME}
      password: ${env:GRAFANA_API_KEY}
  basicauth/metrics:
    client_auth:
      username: ${env:PROMETHEUS_USERNAME}
      password: ${env:GRAFANA_API_KEY}
  basicauth/traces:
    client_auth:
      username: ${env:TEMPO_USERNAME}
      password: ${env:GRAFANA_API_KEY}
service:
  telemetry:
    logs:
      level: info
  extensions: [basicauth/logs,basicauth/metrics,basicauth/traces]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [resource]
      exporters: [spanmetrics,otlp/tempo]
    metrics:
      receivers: [spanmetrics]
      processors: [resource,metricstransform]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [resource]
      exporters: [loki]
```

Some of the key components and steps required for metrics to enable application observability
1. Span metrics and service graph connector &mdash; this creates the required metrics from the traces/spans
2. Resource processor &mdash; adds the default filter label `resource.deployment.environment` to the metrics
3. Metric transform processor &mdash; renames the metrics that is suitable for grafana cloud
4. Prometheus remote write exporter &mdash; writes to mimir, without the unit suffix and resources stored in
   `target_info` so that the service information can be surfaced.

A similar setup to the prometheus remote write exporter is required for loki exporter to ensure that
the service can be identified in the logs.

Alternatively we can just send everything to Grafana cloud's
[otlp gateway](https://grafana.com/docs/grafana-cloud/send-data/otlp/send-data-otlp/) which (acts as a forwarder and) simplifies our
exporter setup significantly[^1]. More concretely, the whole `extensions` and `exporters` block can be replaced
by

```yaml
extensions:
  basicauth/otlp:
    client_auth:
      username: ${env:GRAFANA_TENANT_ID}
      password: ${env:GRAFANA_API_KEY}
exporters:
 otlphttp:
    endpoint: ${env:GRAFANA_OTLP_URL}
    auth:
       authenticator: basicauth/otlp
```

and swap out the corresponding parts in the pipeline. Obviously the downside here is that we cannot be sure
about the conversion from otlp to loki/mimir/tempo since we no longer has tight control over the write operation.
At the time of writing, from personal conversations with various engineers at ObservabilityCON2023, the otlp
gateway simply forwards to the native otlp endpoint of mimir/tempo without adjustment and uses the loki exporter
when writing logs. The aim is to use the native otlp endpoint of loki in the future such that the otel gateway
is a pure proxy. As the loki otlp endpoint is still at the experimental stage I think having this as GA or close
to stable in 2024 will be optimistic (we are already at December of 2023 afterall). For those who wishes to
experiment native otlp, it is essential that they have the loki setting `limits_config.allow_structured_metadata`
set to `true` (whether it is on the cloud or locally).

---

[^1]: There is a significant tradeoff here in that the errors returned from loki/tempo/mimir to the (grafana) otel
grafana will not be propagated back to us. If you are seeing a lot of errors or in the experimental stage then
it is recommended to ship directly to the backend rather than use the otel gateway.

---
title:  "Setting up continuous profiling for open-telemetry collector"
date:   2024-07-30
tags:
  - programming
  - golang
  - monitoring
---

One of the biggest problem we have found at work is that the speed of opentelemetry (otel) moves way faster than other parts of the infrastructure.
Namely, the [opentelemtry collector](https://github.com/open-telemetry/opentelemetry-collector) (and the [contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main)) usually has a release every 2 weeks.
As the opentelemetry collector sits in either the data gathering or transport layer, it is essentially a requirement to keep up with the latest release due to bug fixes and/or performance improvements.
For bug fixes, it is often easy to test in a non-production environment to verify.
Performance improvements?? Especially ones on paper which may or may not hold for your particular workload, well, one solution is to do continuous profiling and track the changes in real time.
This can be done by enabling the [pprof extension](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/extension/pprofextension) in the collector and [pyroscope](https://pyroscope.io/) which pulls the profiles and stores in a backend.

To demonstrate, We make use of the `v1beta1` of the OpenTelemetryCollector CRD which is only available after helm version `0.58.0`.
Refer to the official [opentelemetry operator helm chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-operator) for more details.

We install the base minimum for the operator

```shell
# assuming we are already in kubernetes and is operating without the namespace otel
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --set manager.collectorImage.repository=otel/opentelemetry-collector-k8s \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert.enabled=true
```

before applying the CRO. Note that we have to specify the port explicitly because the operator is not able to recognize the port and mutate the svc/pod even if defined in the config.

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: pprof
  namespace: otel
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc: {}
          http: {}
    exporters:
      debug: {}
    extensions:
      pprof:
        endpoint: :1777
    service:
      extensions: [pprof]
      pipelines:
        traces:
          receivers: [otlp]
          processors: []
          exporters: [debug]
  ports:
    - name: pprof
      port: 1777
```

Now we have a collector running, all we got to do is setup pyroscope to be in ["pull mode"](https://grafana.com/docs/pyroscope/latest/configure-client/grafana-agent/go_pull/).
The snippets of the pyroscope setup here forms the basis of our standard production upgrade where we begin continuous profiling 30 minutes before a change and ends 30 minutes after the change (be it a success or rollback).
The general flow is pretty self-explanatory for anyone who is familiar with how Prometheus scrape works, as this is essentially the same but for profiles instead of metrics.

```alloy
// Pod discovery, can also do service discovery.
discovery.kubernetes "pods" {
    role = "pod"
    namespaces {
        names = ["otel"]
    }
}
// Filter and select the correct pods, and do "relabeling" to insert correct metadata into the profiles.
discovery.relabel "otel" {
  targets = discovery.kubernetes.pods.targets
    rule {
            source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_component"]
            regex         = "opentelemetry-collector"
            action        = "keep"
    }
    // Since the collector will have many ports open to receive traffic, we should filter on pods that
    // has pprof enabled, which by default is port `1777` in the pprof extension.
    rule {
            source_labels = ["__meta_kubernetes_pod_container_port_number"]
            regex         = "1777"
            action        = "keep"
    }
    rule {
            target_label  = "__port__"
            action        = "replace"
            replacement   = "1777"
    }
    rule {
            source_labels = ["__address__"]
            target_label  = "__address__"
            regex         = "(.+):(\\d+)"
            action        = "replace"
            replacement   = "${1}"
    }
    rule {
            source_labels = ["__address__", "__port__"]
            target_label  = "__address__"
            separator     = "@"
            regex         = "(.+)@(\\d+)"
            replacement   = "$1:$2"
            action        = "replace"
    }
    // Create standard labels so that is is easier to understand, these are prometheus conventions. 
    rule {
            action        = "replace"
            source_labels = ["__meta_kubernetes_namespace"]
            target_label  = "namespace"
    }
    rule {
            action        = "replace"
            source_labels = ["__meta_kubernetes_pod_name"]
            target_label  = "pod"
    }
    rule {
            action        = "replace"
            source_labels = ["__meta_kubernetes_node_name"]
            target_label  = "node"
    }
    rule {
            action        = "replace"
            source_labels = ["__meta_kubernetes_pod_container_name"]
            target_label  = "container"
    }
    // Both service_name and service_version are opentelemetry conventions.
    rule {
            action        = "replace"
            source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_version"]
            target_label  = "service_version"
    }
    rule {
            source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_label_app_kubernetes_io_name"]
            target_label  = "service_name"
            separator     = "@"
            regex         = "(.*)@(.*)"
            replacement   = "${1}/${2}"
            action        = "replace"
    }
    // Always good to have some sort of unique identifier to track changes through time. This is the
    // sha of the config which the operator computes for us.
    rule {
            action        = "replace"
            source_labels = ["__meta_kubernetes_pod_annotation_opentelemetry_operator_config_sha256"]
            target_label  = "config_sha"
    }
}
```

then we define the backend which we want to ship to

```alloy
pyroscope.write "backend" {
  endpoint {
      url = env("PYROSCOPE_URL")
      basic_auth {
          username = env("PYROSCOPE_USERNAME")
          password = env("PYROSCOPE_PASSWORD")
      }
  }
}
```

and finally we define the pipeline which chains all the stages `discovery` -> `relabel` -> `scrape` -> `export`.

```alloy
pyroscope.scrape "otel_settings" {
    targets    = discovery.relabel.otel.output
    forward_to = [pyroscope.write.backend.receiver]
    profiling_config {
        profile.goroutine {
            enabled = true
            path = "/debug/pprof/goroutine"
            delta = false
        }
        profile.process_cpu {
            enabled = true
            path = "/debug/pprof/profile"
            delta = true
        }
        profile.godeltaprof_memory {
            enabled = false
            path = "/debug/pprof/delta_heap"
        }
        profile.memory {
            enabled = true
            path = "/debug/pprof/heap"
            delta = false
        }
        profile.godeltaprof_mutex {
            enabled = false
            path = "/debug/pprof/delta_mutex"
        }
        profile.mutex {
            enabled = false
            path = "/debug/pprof/mutex"
            delta = false
        }
        profile.godeltaprof_block {
            enabled = false
            path = "/debug/pprof/delta_block"
        }
        profile.block {
            enabled = false
            path = "/debug/pprof/block"
            delta = false
        }
    }
}
```

Applying all of the above during and upgrade to `v0.101.0` of the opentelemetry collector contrib where the loadbalancing exporter gain a massive improvements, straight diff:

![profile-diff](/images/2024-07-30-profile-diff-101.png)

and when focused on the `mergeTraces` function where the upgrade took place

![merge-traces](/images/2024-07-30-merge-traces-diff-101.png)

allowed us to confirm that the performance enhancement in the CHANGELOG matches (and exceeds) our expectation.
Furthermore, by understanding how the collector behaves, we were able to fine tune the resources and various settings to improve the stability of our system.

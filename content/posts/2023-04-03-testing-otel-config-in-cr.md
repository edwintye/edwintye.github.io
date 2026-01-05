---
title:  "Testing Opentelemetry Config in Custom Resource"
date:   2023-04-03
tags:
  - golang
  - programming
  - testing
---

## Introduction
We talked about how to [test custom resources]( {{< ref "2023-04-01-testing-cr-in-helm-charts" >}} ) for the operator
but skipped out on testing the config for the opentelemetry collector itself. Unsurprisingly, there comes a time
where testing the CR itself is insufficient and we do indeed need to go further down the rabbit hole. Here we are,
answering our question with "Yes, we indeed want to go that far". This is the third and final part of the series.

First we go back and see continue where we left off &mdash; writing the collector config to a file ready to
be read by the application.  In the simple case, we can run the application against the config and see if it
errors out.  An example can be found as
[honeycomb tests their component](https://github.com/honeycombio/opentelemetry-collector-configs/blob/v1.7.0/test/test.sh)
this way via shell scripts; build the binary, spin it up against the config,
validating the metrics, and killing it via the trapped pid. One massive drawback with shell scripting is that
manipulating a config on disk is cumbersome, and then looping through all the different config files becomes
quite error-prone. Again, we turn to native `go test` to ease the pain of managing the different test scenarios.
Our example here uses a file on disk but having that passed via memory is not beyond the realm of possibility;
readers of the [previous post]( {{< ref "2023-04-01-testing-cr-in-helm-charts" >}} ) should be able to connect
the dots easily.

## Testing the config via tests
Unfortunately there is a bit of work to do if we want to mimic the behaviour of the opentelemetry
collector binary, we have the code block collapsed as it is ~~rather trivial~~ quite long and boring.
The snippet below can be summarized as: Run the application against the config we want to test with a timeout
as kill signal.

{{% details "Running application in test" %}}
```go
func TestOpenTelemetryCollectorConfig(t *testing.T) {
	// we create the factories with all the receivers/processors/connector/exporters that we
	// wish to use and can be parsed
	factories, err := components()
	require.NoError(t, err, "error in creating factories")
    // can expand this to include multiple files
	for _, file := range []string{"<some-relative-path>/config.yaml"} {
		// This is part of otelcol.NewCommand triggered from main
		configProviderSettings := newDefaultConfigProviderSettings([]string{file})
		configProvider, err := otelcol.NewConfigProvider(configProviderSettings)
		require.NoError(t, err, fmt.Sprintf("error in parsing the config for %s", file))
		// Collector.Run -> Collector.setupConfigurationComponents
		// we only need to do part of the run if we only want to validate the config without running it
		conf, err := configProvider.Get(context.Background(), factories)
		// this can error when the receiver/processor/exporter config is invalid
		require.NoError(t, err, fmt.Sprintf("error in mapping the configs to the factories %s", file))
		// last part of the validation, this is also validate the service pipelines
		// in addition to the receiver/processor/exporter config which was done in configProvider.Get
		// against the factories
		// this can error when a processor is defined in the pipeline but not in their respective block
		// outside the pipeline
		assert.NoError(t, conf.Validate(), fmt.Sprintf("error in validating the config for %s", file))

		// command.go, still part of NewCommand, but maybe this is not possible given that we need to do a run
		// in the background which means we need to work with an adjusted yaml
		// first we build the program
		info := component.BuildInfo{
			Command:     "otelcol-testing",
			Description: "OpenTelemetry Collector for testing in CI",
			Version:     "1.0.0",
		}
		collectorSettings := otelcol.CollectorSettings{BuildInfo: info, Factories: factories}
		collectorSettings.ConfigProvider = configProvider
		col, err := otelcol.NewCollector(collectorSettings)
		require.NoError(t, err, fmt.Sprintf("error in creating the collector for %s", file))
		// then create a deadline which allows us to gracefully kill the program
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		// this effectively runs the binary
		err = col.Run(ctx)
		assert.NoError(t, err)
	}
}
```
{{% /details %}}

Note that the snippet above is incomplete and require additional functions
[newDefaultConfigProviderSettings](https://github.com/open-telemetry/opentelemetry-collector/blob/v0.72.0/otelcol/configprovider.go#L120)
and
[makeMapProvidersMap](https://github.com/open-telemetry/opentelemetry-collector/blob/v0.72.0/otelcol/configprovider.go#L130).
Unfortunately we have to do a manual copy and paste the functions alongside these tests
as they are not public functions that we can import directly.

Although we can run the application as tests, it does not mean that the tests will pass verbatim. For example,
we might be using the `k8sattributes` processors which will fail when not running in k8s (predictably some
would say). There are a few options we can take to circumvent such issues show below, where ideal amount of
change would be zero for CI and minimal for local development.  Generally speaking it would be impossible to
have zero changes, particularly for local testing, unless we start creating mocks &mdash; which would be very
cumbersome unless the developers are well versed in golang.

{{< tabs >}}

{{% tab "Manual skip" %}}
```go
// let's say we want to skip part of the test due to a known reason
if testing.Short() {
	t.Skip("skipping test in short/local mode due to inability to find k8s metadata")
}
```
{{% /tab %}}

{{% tab "Autodetect" %}}
```go
// or we can autodetect certain required information and skip if required 
if os.Getenv("KUBERNETES_SERVICE_HOST") != "" || os.Getenv("KUBERNETES_SERVICE_PORT") != "" {
	break; // or do some changes
}
```
{{% /tab %}}

{{% tab "Processor manipulation" %}}
```go
// remove the problematic processor from the pipeline just in the test
// can easily expand this to a list of processors and will be left as an exercise for the readers 
var indexToRemove int
for i, v := range conf.Service.Pipelines[component.NewID("traces")].Processors {
	if v.String() == "k8sattributes" {
		indexToRemove = i
	}
}
// removing the processor from the pipeline
conf.Service.Pipelines[component.NewID("traces")].Processors = append(conf.Service.Pipelines[component.NewID("traces")].Processors[:indexToRemove], conf.Service.Pipelines[component.NewID("traces")].Processors[indexToRemove+1:]...)
```
{{% /tab %}}

{{< /tabs >}}

## Dependency tracking
Now we have the foundation to test our config the natural next question is how do we manage an upgrade.  More
concretely, a helm chart will almost certainly have an `<container name>.image.tag` block which allows
independent version tracking of the docker image to the helm chart. Therefore, a bump in the default image tag
should be reflected in the tests or rather, in the (dependency file) `go.mod` of the tests.

We use the official [otel builder](https://github.com/open-telemetry/opentelemetry-collector/tree/main/cmd/builder)
tool to generate our `go.mod` (which mimics the official binary build), and facilitate the version bump by swapping
in the new image version defined in our CR. This particular choice of editing the build definition rather than
`go.mod` directly is due to the complex dependency from upstream libraries, especially in the case of
prometheus where a [dual tracking system](https://github.com/prometheus/prometheus/issues/8852) had to be put
in place. The script below updates the `go.mod` accordingly, and can also be enhanced to compare `CURRENT_VERSION`
against `NEXT_VERSION` (highlighted) and fail in CI.

```shell {hl_lines=[7,8,9]}
#!/usr/bin/env bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
OUTPUT_DIR="${SCRIPT_DIR}/<some-random-place>"
# get the current version from the existing build and the next version from the CR we want to test
# and replace the version in the builder config so that the go.mod can be updated using the
# builder which should contain all the correct imports
CURRENT_VERSION=$(yq '.dist.otelcol_version' "${SCRIPT_DIR}/<some-relative-path>/otelcol-builder.yaml")
NEXT_VERSION=$(yq '.spec.image' "${SCRIPT_DIR}/<some-relative-path>/config.yaml" | cut -d ':' -f 2)
# some people may want to have an if statement here and it is cut out to save space
# installing the builder tool with the target version
GO111MODULE=on go install "go.opentelemetry.io/collector/cmd/builder@v${NEXT_VERSION}"
# swap out the existing version with the new version
sed -i.bak s/"${CURRENT_VERSION}"/"${NEXT_VERSION}"/g "${SCRIPT_DIR}/<some-relative-path>/otelcol-builder.yaml"
# generates the go.mod + go.sum which our tests uses
builder --skip-compilation --config="${SCRIPT_DIR}/<some-relative-path>/otelcol-builder.yaml" --output-path="${OUTPUT_DIR}"
```

A secondary benefit to using the builder config is that we have tight control on what
receiver/processor/connector/exporter is available.  If the collector config uses a component not defined in the
builder config then it will error out even if that component is available in official builds. This layer of protection
is driven by the fact that ordering matters, and is enforced via a reorder in our helm chart e.g. 

```tpl _reordering.tpl
processors:
{{- $config :=  (include "collector.processors" . | fromYaml ) -}}
{{- range $k, $v := (list "memory_limiter" "resourcedetection" "k8sattributes" "batch") }}
{{- if hasKey $config $v }}
  - {{ $v }}
{{- end -}}
{{- end -}}
```

Finally, it should be noted that the builder config can compile a binary that is fit for purpose while trimming all
the unused components from the official builds.  From experimentation, there is a 50% reduction in size and as the
saying goes "size matters"!

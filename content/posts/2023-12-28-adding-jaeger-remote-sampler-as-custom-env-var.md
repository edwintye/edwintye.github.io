---
title:  "Adding Jaeger remote sampler using custom env var"
date:   2023-12-28
tags:
  - programming
  - monitoring
  - golang
---

### Background

The [opentelemetry go sdk does not support Jaeger remote sampler](https://github.com/open-telemetry/opentelemetry-go/blob/e3bf787c217c0dcc6c4fb0111318ca8f1790a157/sdk/trace/sampler_env.go#L29-L34)
via the environment variable even though it is one of the
[known samplers](https://github.com/open-telemetry/opentelemetry-specification/blob/24740fdd83ad4256d6cdb585c2d04b601d82322f/specification/configuration/sdk-environment-variables.md?plain=1#L111-L119).
That is because the Jaeger remote sampler is in the
[go-contrib](https://github.com/open-telemetry/opentelemetry-go-contrib/blob/a001fcc76ce2798dbbf8290ab557840ba2b65f7d/samplers/jaegerremote/sampler_remote.go)
repo instead. If we try to setup the Jaeger remote sampler via environment variable
`OTEL_TRACES_SAMPLER="jaeger_remote"` it will result in the error `unsupported sampler: jaeger_remote` printed
to `stdout`, yet it is not a fatal error. Here, we look at a simple setup which will allow us to initialize
the Jaeger remote sampler via environment variable which allows instrumentation to be changed via a central
location via say the [opentelemetry operator](https://github.com/open-telemetry/opentelemetry-operator).

### The rundown

Let's start by laying down the foundations.  The most basic setup does not require anything but
generally speaking it is better to manually set the service name and version rather than rely
on environment variables. Using the resource, we can setup a new tracer to replace the default
global tracer. At this point, the tracer can be updated with environment variables! For example,
`OTEL_TRACES_SAMPLER=traceidratio` and `OTEL_TRACES_SAMPLER_ARG=0.5` would lead to a sampler with
50% sampling on the trace id being initialized since nothing has been defined. Our goal is to
leverage the same semantics with the jaeger remote sampler. Our goal here is un-comment out the line
which adds the jaeger remote sampler to the trace provider.

```golang
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
)

func main() {
	res :=  resource.NewWithAttributes(semconv.SchemaURL,
                semconv.ServiceName("some-name"),
                semconv.ServiceVersion("some-version"),
            ))
    tracerProvider := sdktrace.NewTracerProvider(
    	sdktrace.WithResource(res)),
        // sdktrace.WithSampler(NewJaegerRemoteSampler("jaeger-remote")),
    )
    otel.SetTracerProvider(tracerProvider)
}
```

First, we need the ability to identify and parse the 3 arguments allowed for the jaeger remote sampler:
* endpoint &mdash; endpoint (url without the path) where the jaeger remote config can be read
* pollingIntervalMs &mdash; frequency of polling the remote endpoint
* initialSamplingRate &mdash; the default sampling percentage if the remote cannot be read

then assuming that we have indeed parsed the arguments into a variable of `map[string]string`
the jaeger remote sampler can be constructed as

```golang
import "go.opentelemetry.io/contrib/samplers/jaegerremote"

func createJaegerSampleWithArgs(serviceName string, args map[string]string) tracesdk.Sampler {
	var opt []jaegerremote.Option
	// the default sampling percentage if the args cannot be read from environment
	fraction := 0.25
	if endpoint, ok := args["endpoint"]; ok {
		opt = append(opt, jaegerremote.WithSamplingServerURL(endpoint))
	}
	if interval, ok := args["pollingIntervalMs"]; ok {
		if n, err := strconv.Atoi(interval); err == nil {
			opt = append(opt, jaegerremote.WithSamplingRefreshInterval(time.Duration(n)*time.Millisecond))
		}
	}
	if ratio, ok := args["initialSamplingRate"]; ok {
		if s, err := strconv.ParseFloat(ratio, 64); err == nil {
			fraction = s
		}
	}
	opt = append(opt, jaegerremote.WithInitialSampler(tracesdk.TraceIDRatioBased(fraction)))
	return jaegerremote.New(serviceName, opt...)
}
```

and the sampler created as below.  Note that we need to separate the functions so since all the base
samplers can be prepended with `parentbased_` in the otel semantic and will use the upstream trace
state to make a sampling decision. One unfortunate aspect is that the constants `tracesSamplerKey`
and `tracesSamplerArgKey` are not exported in the go-sdk, which means that we have to redefine
those two constants ourselves. We have also made the assumption that a function `parseJaegerRemoteEnvArgs`
exists somewhere that can parse the args correctly (some combination of splitting `,` and `=`).

```golang
const (
    tracesSamplerKey               = "OTEL_TRACES_SAMPLER"
    tracesSamplerArgKey            = "OTEL_TRACES_SAMPLER_ARG"
	// custom definition for jaeger
    samplerJaegerRemote            = "jaeger_remote"
    samplerParentBasedJaegerRemote = "parentbased_jaeger_remote"
)
func NewJaegerRemoteSampler(serviceName string) tracesdk.Sampler {
	sampler, ok := os.LookupEnv(tracesSamplerKey)
	if !ok { return nil }

	sampler = strings.ToLower(strings.TrimSpace(sampler))
	samplerArg, _ := os.LookupEnv(tracesSamplerArgKey)
	samplerArg = strings.TrimSpace(samplerArg)

	jaegerRemoteSampler := createJaegerSampleWithArgs(serviceName, parseJaegerRemoteEnvArgs(samplerArg))
	switch sampler {
	case samplerJaegerRemote:
		return jaegerRemoteSampler
	case samplerParentBasedJaegerRemote:
		return tracesdk.ParentBased(jaegerRemoteSampler)
	default:
		return nil
	}
}
```

Another caveat is that using the same env var as the base sdk will result in seeing
`unsupported sampler: jaeger_remote` printed out to the console every time the sampler is initialized.
For anyone without the context, this line may seem like a misconfiguration and therefore we may consider
changing the key to something different such as `tracesSamplerKey="OTEL_TRACES_SAMPLER_CUSTOM"`
(probably unnatural when using with the otel operator). Similarly,
we may consider passing in a logger to the function `NewJaegerRemoteSampler` or add a couple of `fmt` in
before the return statements to signify what type sampler has been initialized.

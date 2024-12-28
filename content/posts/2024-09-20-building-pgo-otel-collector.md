---
title:  "Building PGO otel collector"
date:   2024-09-20
tags:
  - programming
  - golang
---

In the [previous post]( {{< ref "2024-07-30-continuous-profiling-otel-collector" >}} ) we talked about how to use continuous profile to figure out the resources required by the shape of the data.
After obtaining profiles, the nature thing we can do &mdash; at least in golang since 1.20 &mdash; is to build the binary using the profiles that we have collected with [Profile-guided Optimization (PGO)](https://go.dev/doc/pgo).
The [official documentation on pyroscope](https://grafana.com/docs/pyroscope/latest/view-and-analyze-profile-data/profile-cli/#exporting-a-profile-for-go-pgo) on how to build an optimized binary is quite comprehensive already.
Information here is purely intended as a reference for my future self. 

Assuming that we have collected the profiles for the previous pprof otel collector, hence the service name, download the merged profile as per below

```shell
// The profilecli uses different env vars but same auth method as gathering the profile
// The credentials will require different permission set
export PROFILECLI_URL=PYROSCOPE_URL
export PROFILECLI_USERNAME=PYROSCOPE_USERNAME
export PROFILECLI_PASSWORD=PYROSCOPE_PASSWORD
profilecli query go-pgo \
    --query='{service_name="otel/pprof-collector"}' \
    --from="now-1h" \
    --to="now"
```

which exports the profile as `default.pgo` to the location where the command is run.
The time range above is quite large which if you run a lot of collectors in production the network usage may spike beyond expectation.
Since `go build` automatically detects a `default.pgo`, all we have to do is copy this newly downloaded profile and put that in the location of the repo where the binary is built.
Below shows an example where we simply use the otel collector contrib 

```shell
$ go build
$ # check that pgo is in use post build
$ go version -m ./otelcontribcol
...
	build	-buildmode=exe
	build	-compiler=gc
	build	-pgo=/Users/edwintye/github/open-telemetry/opentelemetry-collector-contrib/cmd/otelcontribcol/default.pgo
```

and we can see that the flag `-pgo` is present and populated by profile we just populated.
Before I stop this monologue, I should stress that there is a small trap here.

As the otel collector can pretty much do everything, the usage pattern between deployment may vary and a "random" profile obtained for otel collector probably does not improve the performance.
This is because the components used in the profile may be different to *your workload*.
For example, we use a standard two layer setup of loadbalancing layer-1 -> tail sampling layer-2, which on the surface seems very standard and the profile would be transferable.
However, for other technical reasons we in fact compute the span metrics in layer-1 rather than layer-2 (the more common setup).
In fact the only processor that is common between our layer-1 and layer-2 collectors is the batch processor; the optimized build using a single set of profile in fact only improve one layer and has no impact for the other.
To truly optimize the build we have to build two different binaries, one for layer-1 and another for layer-2, each with the correct profile.
Obviously, an extra (small) optimization here is to build our own variant of the binaries with restricted set of components via the [builder tool which we also played with a while ago]( {{< ref "2023-04-03-testing-otel-config-in-cr" >}}).

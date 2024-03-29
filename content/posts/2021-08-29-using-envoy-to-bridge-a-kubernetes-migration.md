---
title: "Using Envoy to bridge a kubernetes migration"
date: 2021-08-29
tags:
  - docker
  - programming
---

### Old vs the future

Most product comes to a point where a rewrite/migration is due for various reasons.  Here, we
will walk you through the usage of envoy when migrating an old data science application that takes
a csv file as input in VMs to one that serves api inside kubernetes (k8s).

To provide a bit more context, the application simply takes an input &mdash; in the form of a
csv &mdash; does a whole bunch of stuff then return the result as another csv file.  The input
files comes from the external customers[^1] and the size varies. As there is an inevitable delay with
regard to sending and receiving files, most of them has more than 1 row and is processed as a batch
job. The desire is to move to an api based solution that encourages requests that consist of one
object only to:
* Improve customer experience with faster response.
* Easier resource management with the requests even out over time and not batched up.
* Better A/B testing, splits at the network/infra rather than application level.

From a data science point of view, doing A/B testing is definitely the biggest driving factor.
Coupling with a massive drive towards container or even serverless solutions, the nod to migrate
came through and off we go to the brighter future.

### The path of restructuring

With our future world of k8s + service mesh waiting for us, the first thing is to broadly split
up the steps required for a migration.  In summary, we have:
1. Split the service up: an api component and a thin wrapper acting as a client to pick up csv file.
2. Run the application live in parallel in the existing VM and k8s.
3. Deprecate the VM and hopefully end the nonsense of sending/receiving csv.

The new api serving application can in theory be running solely in k8s without ever touching a
VM.  All we need is the thin wrapper client to process the csv and make a request on behalf of a
customer. However, setting this up can be a bit unnatural depending on the environmental setup and
how the api gateways are structured.  For simplicity, we duplicate the application for both VM/k8s
and create a clear separation of concern. 


**Splitting the service up**

Depending on how the data science application is created initially, it may have an easier or
harder time in transitioning from csv to api.  For example, if you use
[bentoml](https://docs.bentoml.org)
then it comes straight out of the box with the correct decorator.

```python
@api(input=DataframeInput(), mb_max_latency=200, mb_max_batch_size=1000, batch=True)
def predict(self, df: pd.DataFrame):
    # the predict method may be a bit complex such as a sklearn.pipeline
    return self.artifacts.model.predict(df)
```

Using `DataframeInput()` gives you the ability to run predictions against a csv file directly
and reply via an api where the payload is an array (of array) or values. For a customer facing
api, it is recommended to accept a well&ndash;defined json object rather than arbitrary arrays
of numbers (which is what `DataframeInput()` allows) for better exposition.

Let's ignore the fact that a migration is one of the best time to rethink how the product should
work, and we probably want to create an api from scratch.  The simplest approach would be to do
straight translation from a csv to a json object &mdash; take the csv headers as keys.
Now our wrapper client can be as simple as 

```python
import pandas, requests

if __name__ == "__main__":
    df = pandas.read_csv("some_file.csv")
    for data in df.to_dict(orient="record"):
        result = requests.post("https://target-url", json=data)
        # process the result as desired
```

where the program can be triggered by say an AWS Lambda that detects the arrival of a new file.
The application can easily reverse the json back into the desired format.
Without significant amount of work, we have an api and a corresponding wrapper
client that is functionally identical, where the api component can be deployed as a
standalone into k8s.

**In comes the restrictions**

There are corporations where the whole system is to resist changes. The resistance can come in many
forms, for us, it is to never change the design of working systems.
Allow network connections from the VM to k8s? No.
Create a new landing area for the csv files? No.
Allow an additional ingress to the VM to hit the api? No.
Pretty much everything is a straight no regardless of logic, you get the picture.  The worst part is
that when we deployed a first iteration of the api into the VM, we forgot to hide our tracks and listen
only on localhost.  One of the security scanners picked up the open port on the VM and we got an
invitation to lunch from security.`

Now we have a new requirement of binding to `127.0.0.1` (localhost) rather than `0.0.0.0` (all interfaces)
&mdash; hard coded in and
never to be touched again.  This restriction effectively renders the docker image useless as
the k8s health check will no longer pass.  We have two options at this point:
1. Go through the necessary design changes and explaining them to various architects and auditors, 
2. take the easy way out and circumvent the restrictions.

### Envoy to the rescue

Yes, we took the easy way out after studying how the various service mesh works. Nearly all the service
mesh that we tried follow the same pattern: inject a sidecar, rewriting the routing, and let the
sidecar provide all the goodies that we need.  As [Envoy](https://www.envoyproxy.io) appears to be
the most common service proxy around and configured via yaml it was an easy choice[^2].  After a bit
of time, the following yaml was cooked up and ready to be served.

```yaml
static_resources:
  listeners:
    - address:
        socket_address:
          address: 0.0.0.0
          port_value: 10080
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                codec_type: AUTO
                stat_prefix: ingress_http
                route_config:
                  name: backend
                  virtual_hosts:
                    - name: backend
                      domains:
                        - "*"
                      routes:
                        - match:
                            prefix: "/"
                          route:
                            cluster: backend
                http_filters:
                  - name: envoy.filters.http.router
  clusters:
    - name: backend
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: backend
        endpoints:
          - lb_endpoints:
              - endpoint:
                  health_check_config:
                    port_value: 8080
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: 8080
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 10081
```

Envoy now is a functioning minimal service proxy: comes with its own health check at `:<admin_port>/ready`, checks
the upstream service, reroute to the correct port, and bridges the outside to localhost connectivity. The
application is named as `backend` in the config for simplicity and requires no further changes. For a
deployment to k8s, all we have to do is add the envoy sidecar (alongside the api service) with the config above.

```yaml
        - image: api:v1.0.0
          name: main-api-service
          ports:
            - containerPort: 8080
        - image: envoyproxy/envoy:v1.19.0
          name: envoy-sidecar
          args:
            - "-c"
            - "/mnt/data/envoy.yaml"
          readinessProbe:
            httpGet:
              path: /ready
              port: 100081
          volumeMounts:
            - mountPath: /mnt/data
              name: envoyconfig
```

Unfortunately, the application still fails to spin up due to health check failures even when it was successful
for envoy. We can in theory have the application health check go through envoy, but that creates another 
problem which we discuss later. Learning from how istio configure the sidecar,
we introduce another route which forwards the health check to the application.  K8s can now `httpGet` at
`:15080/app-health/get/<original_path>` for the application health and accurately determine container
health individually.

```yaml
static_resources:
  listeners:
    - address:
        socket_address:
          address: 0.0.0.0
          port_value: 15080
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                codec_type: AUTO
                stat_prefix: ingress_http
                route_config:
                  name: health_check
                  virtual_hosts:
                    - name: health_check
                      domains:
                        - "*"
                      routes:
                        - match:
                            prefix: "/app-health/get/"
                          route:
                            prefix_rewrite: "/"
                            cluster: health_check
                http_filters:
                  - name: envoy.filters.http.router    
  clusters:
    - name: health_check
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: health_check
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: 8080
```

Having two essentially identical entry to the application seems completely insane, and I hear you. The
need stems from the need to respect (distributed) tracing on all but the health check endpoints. Just
because our VM setup is a bit old school, it doesn't mean we are completely blind! A separate route
allows us to hit the health check endpoint without creating a trace, replicating the existing system
completely.

### Tracing compatibility

As said previously the future state is a service mesh where tracing is taken care of completely by
the infrastructure. In the transition state where parallel run happens, we need to ensure
that the two system can be as identical to each other as possible.  Fortunately, tracing is
an existing functionality we have via Elastic APM.

Inside the application, we use the interoperability of
[elastic apm and open tracing](https://www.elastic.co/guide/en/apm/get-started/current/opentracing.html)
to ensure traces
conforms to W3C specification from the application first.  Then setup envoy to also use W3C format
for the main route `backend`, denoted as `TRACE_CONTEXT` as seen below, and we sent that to jaeger.
The party responsible for handling the tracers is determined by the targeted platform
via a feature toggle, i.e. by the application itself or performed outside by envoy.
Jaeger is the final collection point for which we can compare the traces during the parallel
run as our last system sanity check.

```yaml
# generate_request_id: true # is this an edge service?
tracing:
  provider:
    name: envoy.tracers.opencensus
    typed_config:
      "@type": type.googleapis.com/envoy.config.trace.v3.OpenCensusConfig
      zipkin_exporter_enabled: true
      zipkin_url: "http://jaeger.observability:9411/api/v2/spans"
      outgoing_trace_context: TRACE_CONTEXT
      incoming_trace_context: TRACE_CONTEXT
```

The commented out config `generate_request_id: true` is to enable the generation of persistent header
`X-Request-ID`.  For k8s, such header already exists (created by the edge gateway) while in VMs we
create the header from the internal client (cheating a little).  During development, sometimes it
is useful to uncomment the config for debugging; a local k8s setup usually fails to replicate a full
environment and requires some extra effort as shown here.

### Parallel run and sunsetting
A massive benefit here is that we have "dog food" the api. In some cases we have even informed our customers
exactly how we use the api internally.  In theory (from my personal perspective), both the build and
documentation should be shared with the customer verbatim because there isn't any secrets.  We
simply invoke the [openapi generator](https://github.com/OpenAPITools/openapi-generator)
to create the client library and wrap it round with some
rudimentary python code to read the csv and add request headers.

Parallel run is necessary for customers who have yet to move and also provide a fallback option for a
period of time until all parties are happy.  Sunsetting only occurs when all the customers has successfully
migrated for a prolonged period, even though in reality we snapshot the state before their indefinite slumber
as a precaution.

This is the end of our envoy story, hope you enjoyed it and learnt a thing or two.

[^1]: We use the word "customer" rather than "client" here to make a distinction because we have our own internal client making requests to the api. 
[^2]: Thinking that yaml would be easy was a grave mistake, configuring envoy turned out to be the most time&ndash;consuming part.  The lack of knowledge didn't help.
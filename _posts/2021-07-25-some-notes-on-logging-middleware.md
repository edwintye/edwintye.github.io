---
layout: post
title:  "Some notes on logging middleware"
date:   2021-07-25 00:00:00 -0000
categories: programming
tags: golang programming
---

> A log line should present information that is actionable.

A statement I heard many moons ago* that represents a level of perfection I aspire to achieve.
In the world of microservices, a log line containing the request/response pair
is probably the best starting point when trying to debug an issue. 

Making use of a middleware pattern to log requests is one of those fundamental ideas
that you will find in almost every service.  The simplest version would look something like

```golang
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		logger := log.Logger{}
		defer func(start time.Time) {
			logger.Printf("request duration: %s", time.Since(start).Milliseconds())
		}(time.Now())
		next.ServeHTTP(rw, r)
	})
}
```

where we just record the time taken of the request to respond.  In most cases we will already have
a logger initiated in the main package; structured logging is pretty much the standard these days
and is commonly achieved by using an external logger, e.g. `go-kit/log`, `zap`, `logrus` etc.
Obviously some more information is required before the logs are useful. At a minimum we
need to know which endpoint is being hit!  

### Logging is awesome

Let's assume that we have already initialized `logger := zap.NewExample()`
in the main of the service.  Then we can improve the logging to include other information such
as the path and the method of the request.

```golang
fields := []zap.Field{
	zap.Time("start_time", start),
	zap.Time("end_time", time.Now()),
	zap.Int64("duration", time.Since(start).Milliseconds()),
	zap.String("http_path", r.URL.Path),
	zap.String("http_method", r.Method),
}
logger.With(fields...).Info("an awesome request")
```

Now, this may seem to be sufficient to calculate simple KPI, however one issue is that we
are not differentiating between a successful request and a failed one.  To produce service level
reporting, we need to capture the status code returned to the client.  The response can be captured
by hijacking the response writer with our own struct that satisfies the interface.

```golang
type RequestHijackWriter struct {
	http.ResponseWriter
	Status int
	Body   []byte
}

func (r *RequestHijackWriter) WriteHeader(status int) {
	r.Status = status
	r.ResponseWriter.WriteHeader(status)
}

func (r *RequestHijackWriter) Write(body []byte) (int, error) {
	r.Body = body
	return r.ResponseWriter.Write(body)
}

func (r *RequestHijackWriter) Header() http.Header {
	return r.ResponseWriter.Header()
}
```

Above, we store a copy of both the body and status code when it is written later in the
application. We can then easily log this info as
`zap.ByteString("response", hijack.Body)` and
`zap.Int("http_status", hijack.Status)` respectively.

### Application logs does not give you SLA

Sometimes people mistakenly assuming that the logging inside the application is sufficient for an
SLA report.  Unless your customers is the super chilled out type, they will want something more
comprehensive.  Note that some status code will never be recorded &mdash; the likes of 404 and 405
would have been bounced before reaching the middleware and will only be captured at the gateway
level. Similarly, 401/403 are handled almost exclusively in the gateway layer and such requests
never reach the application.

The purpose of logging in the application is to get a view of the application in that specific
instance of the service.  Unless you only have one instance of the service, it is always interesting
to compare the traffic and performance between the replicas and will likely form part of the SLO/SLI.
For example, you may spot an early sign of a hard disk failure because a particular VM is always
slower.  If your log forwarder/collector does not augment such metadata &mdash; hostname in this example
&mdash; then we simply add that in globally.

```golang
hostname, _ := os.Hostname()
logger = logger.With(zap.String("hostname", hostname))
```

### Are we logging too much?

Logging too much info about the request is possible if your service handles PII data.  A sharp
eyed reader may realize that we are logging the response body but not the parameters or
the body from the request, while at the same time logging the response.  I must stress
that in general we **do not** want to log the whole response.  We should take
out specific fields that is useful during log analysis.

There is almost never a case where capturing the full request or response can provide information
in the event of a failure.  Actionable logging happens in the meat of the application.  Right
before and after the part of the code which failed, and not logs at the edge (of the application).
Logs generated by the middleware are useful as a starting point to generate some metrics for
rudimentary monitoring, and a mechanism to trace the request. 

As a data scientist, the most common metric that we want to monitor is some form of a
score provided to the client.  In such a case, we can simply reflect the response body
and extract the score.

### Real&ndash;time monitoring options

Usage of logs is usually in the form of batch analysis rather than real&ndash;time monitoring.
People often turn to prometheus for such tasks and instrument in the same way as logging.
For example, we can set up appropriate quantiles that we want to monitor

```golang
var scoreHistogram = prometheus.NewHistogramVec(
    prometheus.HistogramOpts{
        Name:    "score_of_some_service",
        Help:    "Score distribution",
        Buckets: []float64{0.9, 0.1, 0.99, 0.01, 0.999, 0.001, 0.5},
        }
    []string{"score"},
)
```

with alerts triggered based on drift/deviation.  Although it seems that we have duplicated
information into another system, data for real&ndash;time monitoring is not destined for durable
storage. For long term analysis, we will always go to the logs which contains the raw rather than
the processed data.  At times we may have to consume logs from multiple applications
and one way of joining the logs is via tracing.

### Tracing in logs

Tracing is done via request headers, usually in the form of `X-Correlation-ID`, `X-Request-ID` supplied
by the client and/or some form of span context such as `TraceParent` from the open tracing world.
Although we can add (distributed) tracing information into the logs in the middleware, as per below,
this is most likely not efficient.

```golang
// this is going to be difficult to keep track of, and should use
// proper tracing instrumentation
func HeaderToFields(header http.Header) []zap.Field {
    return []zap.Field{
    	// or with x- prefix, or whatever variants you know exists
        zap.String("correlation_id", header.Get("x-correlation-id")),
        zap.String("request_id", header.Get("x-request-id")),
        zap.String("span_id", header.Get("<some span id like Uber-Trace-Id>")),
    }
}
```

In most programming languages the instrumentation of tracers will provide a mechanism to either
log or add some logging info into the trace. The tracer agent should contain all the necessary
information already, and the server can be instrumented by having tracers rather than a logging
middleware. For example, open tracing has a
[go client](https://github.com/opentracing/opentracing-go) which can be used to extract info
(from header) and also logs (given span).

```golang
import (
    "github.com/opentracing/opentracing-go"
    "github.com/opentracing/opentracing-go/log"
)
// extract the information from header
spanContext, err := opentracing.GlobalTracer().Extract(
    opentracing.HTTPHeaders,
    opentracing.HTTPHeadersCarrier(r.Header),
)
// start a span and add some log information
span = opentracing.StartSpan("some_random_request")
span.LogFields(
	log.String("event", "some-ecent"),
	log.Int64("value", 12321),
)
```

Some infrastructure is set up such that tracing is injected via a sidecar acting as a proxy.
In those cases we have to find out the appropriate headers the application needs to extract.  In
the ideal scenario your sidecar will conform to open tracing standard and pass them on automatically.
One downside to manual instrumentation is that we can't add extra log info.  Generally speaking
there should virtually be no differences because the solution still rely on (span) context propagation.

Finally, I should say that my experience of logging middleware is that the usefulness tends to
zero, especially as maturity with dealing with context develops.  Logs with tracing more than covers
the entry/exit element of logging middleware, and monitoring on both application + gateway
replaces the real&ndash;time element.


---
**NOTE**
I honestly cannot remember who I heard this from, but I have since heard it from multiple
people across different jobs/companies that this is slowly becoming general knowledge.

---
---
layout: post
title:  "Where to put http.TimeoutHandler"
date:   2021-08-02 00:00:00 -0000
categories: golang programming
---

One of the most interesting things I get to see on working across different product teams is the
various implementation of the same concept. As titled, we have multiple usage pattern of
[http.TimeoutHandler](https://golang.org/pkg/net/http/#TimeoutHandler) and I try to explain the rationale
behind each of them. I am not going to try to explain why we need a timeout or the different types of
timeout; cloudfare has an excellent article
[here](https://blog.cloudflare.com/the-complete-guide-to-golang-net-http-timeouts/) that contains more
knowledge than I have regarding the various components/stages of timeout.

### Setting the scene

Let's start by setting the scene with some code as shown below.  We have two components:
a logging middleware which
[I have writen about previously]({% post_url 2021-07-25-some-notes-on-logging-middleware-in-golang %}), and plays
a significant part as we see later.  The `SleepHandler` simply sleeps for 3 seconds before responding.
Our sole focus from herein is the content of the `getServer()` function, and ways people implement timeouts.

```golang
func SleepHandler(rw http.ResponseWriter, r *http.Request) {
	time.Sleep(3 * time.Second)
	rw.WriteHeader(http.StatusOK)
	rw.Write([]byte("Bedge . o O Wokege"))
}

func getServer() *http.Server {
	r := mux.NewRouter()
	r.Use(loggingMiddleware)
	r.HandleFunc("/", SleepHandler)
	srv := &http.Server{
		Handler: r,
		Addr:    ":8080",
	}
	return srv
}
```

### Router level timeout

The most common place I have seen is to place `http.TimeoutHandler` over the whole router. We now
have guaranteed on a (503) response when the requests are taking too long, and we can change all
aspects of the router/handlers without further thoughts on this issue.  Although
this is possibly the easiest approach, it is also least useful because now the logging middleware
(or indeed any middleware) wouldn't get the correct information.

More concretely, `http.TimeoutHandler` writes and issues a `context.Done()` at the same time. Unless
the application is context aware throughout, the request will still be running in the background. In
the case of our `SleepHandler`, it will in fact return and logged as a 200 response. To ensure that
we record the correct response, we can either make all the handlers or the (logging) middleware context
aware &mdash; perfectly achievable via the `go func()` then `select {}` pattern.
However, most people would prefer to take the shortest path, and there are times it is by design that
the operation of the request ignores the context.

```golang
func getServerTimeoutRouter() *http.Server {
    // Setup router with middleware and handler
    srv := &http.Server{
        Handler: http.TimeoutHandler(r, 1*time.Second, "Router timeout."),
        Addr: "  :8080",
    }
    return srv
}
```

### A timeout middleware

So let us enhance the logging middleware.  At the same time, why add extra bits to a component
that is functioning well.  Instead, we can just introduce the timeout as part of the middleware.
Well, some of my colleagues have one exactly that.

```golang
func timeoutMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
        http.TimeoutHandler(next, 1*time.Second, "You have timed out.").ServeHTTP(rw, r)
    })
}

func getServerTimeoutMiddleware() *http.Server {
    // Setup the router
    r.Use(loggingMiddleware)
    r.Use(timeoutMiddleware)
    // Setup the http.Server
}
```

The most significant difference is the change of execution order between logging and timeout.
This small change ensures that the correct response is captured, and swapping the order above
is equivalent to the aforementioned router level implementation.  The only downside is that such
a broad approach is rather blunt.

In some scenarios we want a bit more control as the complexity of the program increases.
Often we will start breaking down the server by endpoints/operations `r.PathPrefix("something").Subrouter()`
where middleware is applied per subrouter.  If you require dedicated logging middleware per subrouter
to prevent logging sensitive data, then you will need to have the timeout middleware (even if they are
all the same) after the logging middleware as said previously.

### Handler level timeout

Finally, the most rudimentary approach is to wrap individuals handler with `http.TimeoutHandler`.
Although this may seem completely unnecessary, there are times when we just want that extra bit
of safety by allowing the main endpoints to respond slowly, while ensuring that the health check
endpoint(s) respond (or not) in a timely manner under stress. 

Downside to such refined control is obviously the diligence to put this on every handler, as well
as carefully thought out durations for each handler.  Furthermore, we also lose the power to easily
set a global timeout duration say via an input argument to the main program.  A matter of
trade&ndash;offs between convenience and control at the end of the day.

```golang
func getServerTimeoutHandler() *http.Server {
    // Setup the router and middleware
    r.Handle("/", http.TimeoutHandler(http.HandlerFunc(FooHandler), 3*time.Second, "Handler timeout."))
    // Setup the http.Server
}
```

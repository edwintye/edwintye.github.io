---
title: "Testing the main of a golang http server"
date: 2022-04-29 00:00:00 -0000
tags:
  - golang
  - programming
  - testing
---

I had this question at work by a recent graduate on "Why we don't test our main?" and without much thought
gave the stock answer of "We test our main via pact tests".  Of course, the answer is valid in that we make
use of the package `os/exec` to test the cli arguments like

```golang
func TestCliArg(t *testing.T) {
    app := exec.Command(os.Args[0], "-test.cli", "some-cli-argument")
    err := app.Start()
    require.NoError(t, err)
    // do some stuff, for us it is contract test via pact.io
    err := app.Process.Signal(os.Interrupt)
    require.NoError(t, err)
}
```

with a detection in `TestMain` like below which allows us to launch the main program automatically when doing
`go test`.

```golang
func TestMain(m *testing.M) {
	for i, arg := range os.Args {
		if arg == "-test.cli" {
			os.Args = append(os.Args[:i], os.Args[i+1:]...)
			main()
			return
		}
	}
	os.Exit(m.Run())
}
```

Unfortunately although this does provide great coverage because the test result won't show up on the coverage report.
So we went about addressing this issue and do some learning in the process because it is always nice to
gain more knowledge. Turns out, this is a well known problem and 
[one of the common solution](https://www.cyphar.com/blog/post/20170412-golang-integration-coverage)
is to introduce `func Main() error` where the tests can call `Main` and assert the output.  For the majority
of our applications, they are http servers like (in the simplified form)

```golang
import "github.com/gorilla/mux"
func getServer() *http.Server {
	r := mux.NewRouter()
	r.HandleFunc("/", SomeHandler)
	srv := &http.Server{
		Handler: r,
		Addr:    ":8080",
	}
	return srv
}
```

which obviously is a long&ndash;running process until an interrupt is triggered. We are already using
`os.Exec` to start the program and interrupt so our current construct is insufficient. Knowing that there
is no mechanism to just kill a goroutine, we have to change the function argument to allow us to send an
`os.Interrupt` into `Main()`.  Unfortunately, adding a random input argument to the function that
governs the program caused some unease, but we are very accustomed to propagating context so off we go.

Our minimal program has the very familiar function signature `Main(ctx context.context) error`, which contains
two run groups: one block for the http server, and another simply to capture the interrupt signal and
terminate the function/program.  We can simply call `Main(context.Background())` for our normal operation,
surround with the appropriate error capture and is functional identical to how any http server would look like.

```golang
import "github.com/oklog/run" // and other standard import not shown
func Main(ctx context.Context) error {
	g := run.Group{}
	{
		srv := getServer()
		g.Add(func() error {
			if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				return err
			}
			return nil
		}, func(error) {
			srv.Shutdown(context.Background())
		})
	}

	{
		sig := make(chan os.Signal, 1)
		g.Add(func() error {
			signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
			select {
			case <-sig:
			case <-ctx.Done():
			}
			return nil
		}, func(error) {
		})
	}

	return g.Run()
}
```

The test would now insert a context into `Main(context.context)` and cancels the context after the server
has been started successfully.  An inexact version is used below where it simply waits and assumes the server
is alive after 2 seconds, which we can replace it with an actual request to an endpoint of the server.
Obviously we can use `context.WithTimeout` instead of `context.WithCancel` and swap the action on the
`select/case` a bit, and that is just down to personal preference.

We initialize the `err` to be an actual error as the expectation is the output from `Main(ctx)` overwrites
with a nil which is the expected output of the test. Our coverage here is not comprehensive because we
are not testing against the scenario where the server throws an error.  For most application, that is
probably one step too far however there is an easy way by occupying same port as the application before
starting the http server via `net.Listen("tcp", ":<application-port>")`.

```golang
func TestMainStart(t *testing.T) {
	err := errors.New("tmp")
	ctx, cancel := context.WithCancel(context.Background())
	go func() { err = Main(ctx) }()
	select {
	case <-time.After(2 * time.Second):
		cancel()
		time.Sleep(time.Second) // just need some mechanism to allow the http server to finish
	case <-ctx.Done():
	}

	require.NoError(t, err)
}
```

Although we are in a good state in that we archived our original goal, there is still a need to inject a
context into the program which may be confusing depending on your setup. For example, if you are already using
[errgroup](https://pkg.go.dev/golang.org/x/sync/errgroup) and manage your own context, then adding
another one just for testing is probably not the most friendly approach. In that case we can just swap it out
with a channel (which is the output of `ctx.Done()` anyway), i.e. `Main(done chan bool)` or any other variable
type. The signal interrupt block now becomes

```golang
select {
case <-sig:
case <-done:
}
```

and the program can be started normally via `Main(nil)`. Testing remains simple as we just change the definition
and usage from a context to a channel. Overall, the change described here is simply, while provide the possibility
of increasing test coverage on a massive scale; even if these new test does not improve the safety of a release
as the program is probably tested in some other way, at least we have the paperwork for the more pedantic folks.

```golang
// the block which triggers the stoppage in the test
done := make(chan bool, 1)
select {
case <-time.After(2 * time.Second):
    done <- true
    time.Sleep(time.Second)
case <-done:
}
```

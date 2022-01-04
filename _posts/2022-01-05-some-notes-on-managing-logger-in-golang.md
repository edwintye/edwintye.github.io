---
layout: post
title:  "Some notes managing logger in golang"
date:   2022-01-05 00:00:00 -0000
categories: programming
tags: golang programming
---

As someone who only started learning and using golang for a couple of years, I am constantly surprised by
how loggers are being managed everywhere.  I first learnt programming on Java and the general rule of thumb was
relatively simple: singleton for application, dependency injection for library. The design of the programming
language means that following these two simple rules turns out to be quite hard, but not impossible if you
release yourself from the strict OOP world.  

Consider the simplest program, where we wish to divide one number by another; the purpose of the divide function
is to capture the division by zero error and return the `Inf` value while warning the (function) caller with
some custom information.  The program will not compile because `logger` is not defined, and we walk
through the various way in which we can implement `logger`.

```golang
package main

import (
	"math"
)

func divide(x float64, y float64) float64 {
	if x == 0 {
	    logger.Println("...")
		return return math.Inf(int(x))
    } else {
	    return x / y
    }
}

func main() {
    fmt.Println(divide(3, 2))
    fmt.Println(divide(3, 0))
}
```

**Singleton is king**

For a simple application, we can just have a global logger.  What happens though when we want to say extract
the function into a different file? Absolutely nothing as long as the new file is part of `package main`.
In general, there is nothing wrong with the singleton pattern for the main of the application
because it is easy and extendable. 

```golang
var logger = log.Default()
```

**CMD layout changer**

As time goes on, we may have a more complicated program and decides to split the code up into
`/pkg` and `/cmd` directories
[as shown here](https://github.com/golang-standards/project-layout).  There are multiple ways we can change
the function `divide` to allow a logger be defined at the `cmd` and be used in the `pkg` via
dependency injection.  The most invasion change would be to change the function signature such that we *must*
insert a logger as a parameter.

```golang
func Divide(x float64, y float64, logger log.Logger) float64 {}
```

We are restricted by the design of the programming language where method overload is not an option, and this
implementation is rather clunky. Having to insert the logger seems very unintuitive, so we may want to
just do it once with
[currying](https://en.wikipedia.org/wiki/Currying). 

```golang
func currying(logger log.Logger) func(float64, float64) float64 { return Divide }
```

This may be a sensible solution in some situation, and indeed may seem natural if you have a functional
programming background. For golang however, we can do this much better via a struct + interface.  Any future
features can be easily defined in the interface and implemented accordingly. From the user perspective, we
have reduced this down to a single initialization of the `Calculator` object using the `logger` which was
defined in `/cmd`.  Problem solved until someone else wants to use your package.

```golang
type Calculator struct {
    logger *log.Logger
}

type calculate interface {
    Divide(float64, float64) float64
}
func (c *Calculator) Divide(x float64, y float64) float64 {
    // can use c.logger in all the methods
}
```

**Interface segregation maybe?**

Forcing every user of your package to use the standard logger is not very user-friendly. Almost every logger
provides you with some mechanism to transform back to a standard logger, e.g. an application using
[go-kit/log](https://github.com/go-kit/log) can use this `Calculator` struct with just two lines as shown below. 

```golang
l := gokitlog.NewLogfmtLogger(os.Stdout)
logger := log.New(gokitlog.NewStdlibAdapter(l), "[some-prefix] ", log.LstdFlags)
```

[Logrus](https://github.com/sirupsen/logrus) on the other hand provides an almost fully matching interface
[StdLogger](https://github.com/sirupsen/logrus/blob/0c8c93fe4d2fb9013b83ae5f3151608f69f562ca/logrus.go#L124)
against the standard logger which the logrus logger satisfies. Therefore, we can just change the struct definition
of `Calculator` to use `logrus.StdLogger` without impacting any existing code and lower the friction to other
users simultaneously.  

One of the downside of using `logrus.StdLogger` here is that now the package *is forced to* import logrus, and
every user of this package also has an indirect import and polluted the dependency.  Furthermore, we are not
being explicit about what is actually being used.  More concretely, we should be defining a narrow scope interface
that contains method we use within the package.  If we only use `Println`, as shown in the `Divide` function, then
our custom interface would look like

```golang
type Calculator struct {
    logger StdLogger // uses our custom interface
}

type StdLogger interface {
	// redefine the interface of the standard library logger like logrus
	// but only contain methods used in this library
    Println(v ...interface{})
}
```

where both `log.Default()` and `logrus.New()` satisfies our custom `StdLogger` interface. For anyone who wishes
to do something unconventional, to create an object with the requirement of a single method is trivial. From the
user perspective, we have lowered the barrier to start consuming the package as much as possible.  Yet, a single
question remains: 

> Why is the logger a forced requirement?

**Locally global**

Consider the original application where we only want to compute division of two numbers a couple of times. Maybe I
don't even want to log anything.  The solution is obvious, we can just define a logger that discards every message
and initialize the `Calculator` object with it.

```golang
noOpLogger StdLogger := log.New(io.Discard, "[calculator]", log.LstdFlags)
cal Calculator := Calculator{logger}
```

The pro and con of this approach is that it requires an action from the user in all situation. For those who
prefers to disable all features by default, we can instead move `noOpLogger` into the package and remove the
need of a struct altogether. 

```golang
package calculator
// Note that this performs a compile time check
var Logger StdLogger = log.New(io.Discard, "[calculator]", log.LstdFlags)
type StdLogger interface {}
// same divide function as before but now at the package level and not via a struct
func Divide(x float64, y float64) float64 {
	Logger.Println("Use package logger here without the need of a struct")
}
```

Now the logger is created at compile time and does not log anything by default. User of the library can override
the default logger if they wish to log. Similarly, the default behaviour can be set to log to `stdout` and let
the user change that as desired. One obvious benefit is the way we use the package, when only simple actions
without a state or side&ndash;effect exists; ability to invoke the function calls directly without the
initialization of a `Calculator` object.

```golang
import foo.bar/calculator
func main () {
	// If we ever want to override the default logger in the package, we can just override it
	// calculator.Logger = logrus.New()
    calculator.Divide(3, 2)
    calculator.Divide(3, 0)
}
```

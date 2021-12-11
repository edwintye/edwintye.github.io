---
layout: post
title:  "Integration testing in Golang using docker"
date:   2020-01-29 00:00:00 -0000
categories: programming
tags: golang docker programming testing
---

All the examples and code here are in a [Github repo](https://github.com/edwintye/golang-docker-it-test),
which assumes an interaction with Redis (an KV in memory store commonly used for cache) is required.

An integration test is used to ensure that modules/classes/sub-systems all work together without issues.
When our software has a hard dependency on external parts such as data stores, databases, message broker,
and event store for monitoring, then the notion of integration quite often includes those data stores as well.
We would always prefer to have a feedback cycle, which often leads to some sort of emulation of the services in
the production environment.

### What's the problem?
Traditionally, these services will be mocked and injected into the integration tests. Feedbacks are fast
and tests are self-contained, bar some external library required for mocking, which is advantageous as it
decreases the dependency of development. Having an actual database on a laptop is wasteful, yet it is also
the safest approach. In the event that we would like to ensure forward and backward compatibility between
(major) versions, testing against the desired versions is a requirement.

Docker reduces the setup cost with the ability to spin up an exact version of the system on demand. A common
pattern is to spin up the required containers first via some shell script. This increases the complexity due to
a non-native step, and slightly more cumbersome with config being passed around different programs. For example,
a bash script (see below) to spin up a container and then performs the tests shown below completely renders the
IDE extra functionality useless. The introduction of external scripting for a particular type of test also
increases the cognitive load of the developers, and introduces a particularly nasty coupling due to the
steps (within the tests) split over multiple locations + languages.

{% gist 87ebe8f84fc3eb59f337915c27b9cf1e docker_redis_go_test.sh %}

### Using containers via SDK
One way to bypass the requirement of a shell script step would be to embed the steps of the docker command
into the tests themselves. More concretely, we can use the official Golang SDK &mdash; or the appropriate libraries
for the programming language of choice &mdash; to bake in all the docker command line above directly within
the package. An example can be seen in
[docker.go](https://github.com/edwintye/golang-docker-it-test/blob/master/docker.go), which contains the
minimal implementation required: download the image, start the container with an exposed port, find the port
mapping, stop the container, and remove the container as per the interface below.

All the methods in the interface are simple wrappers around the SDK’s `Client` and builtin `context` classes.
The two methods, `initialize` and `getContainerNetworkInfo`, directly mimic the command line operations 
`docker run` and `docker port` respectively. Since there isn’t much rationale to stop but not remove a container for
testing purposes, the two steps have been merged into one method as `stopContainer()` &mdash; replicating the combination
of the `--rm` flag in `docker run` and `docker stop`.

{% gist c3eebfad83dfe05cecfd242a9a25f71d golang_docker_interface.go %}

Now equipped with the ability to spin up a container internally in runtime, we can revert back
to native go commands throughout the process. We make use of environment variables to carry out the tests
against the different versions as desired. Verifying the compatibility for a particular version is as easy
as augmenting the build matrix, here as `[rc, latest, 5.0], with the new tag. The steps in CI, here seen using
Github actions, demonstrate the full workflow including the different testing phases.

{% gist f0f5b665d5710fa83c20386c37a60d04 golang_actions.yaml %}

The mechanism of choice to separate out the different types of tests is via the build chain. Namely,
`+build integration` at the top of the file is used to flag up the fact that the files contain 
integration tests and are triggered by tagging such as `go test -tags=integration`. Using the docker 
container inside the tests requires new functions `setUp` and `tearDown`, purely because Golang does not
offer a clean solution for setting up the tests. Alternatives include initializing the necessary objects in
`TestMain(m *testing.M)`, increasing the complexity and setup time for simple unit tests, or having
a `TestMain(m *testing.M)` or each tag/file which is rather error-prone. We find that the simplest
solution is to consolidate related tests under one function and separate them through
[subtests](https://blog.golang.org/subtests). A nice side&ndash;effect of this construct is that each test has
a clean container to work with; managing the state is comparatively easy as an explicit purge between
tests is no longer mandatory.

As much as using build tags separate the different types of test nicely, a rather painful consequence
is that the coverage report requires an additional full run. *Note that if other types of tag exists say,
E2E, then they should be included as well.*

```bash
go test -tags=unit,integration -v -covermode=count .
```

Furthermore, the coverage will always be driven down slightly due to the lack of testing for file
[docker.go](https://github.com/edwintye/golang-docker-it-test/blob/master/docker.go); having tests for the docker
container class basically put us back to square one, where we  now seek a way to test an external program, and it
would be more productive to extract and convert the file
[docker.go](https://github.com/edwintye/golang-docker-it-test/blob/master/docker.go) into a dedicated package instead.

File tagging is not only used in the tests but also the build, the intended purpose in the first place, as
used in the file `docker.go`. We tag the files meticulously to minimize the main program; build tag provides
the ability to clearly state the purpose at the file level. Inserting the tag `+build integration` ensures
that the default `go build` will not include the `docker.go` file (or any of the dependencies) when 
compiling the binary.

### Afterword
Docker helps with decreasing the requirements of testing against a live service, eliminating the need
for either a deployment step to the workflow or the CI server has access to those live services.
CI servers, such as Github actions, Bitbucket pipelines, Travis, Circle, etc, all have docker available
either as a service or come as default these days. Here, we have provided an intro on how to start using
the docker SDK and embed the tests inside the package for Golang, allowing comprehensive setup within
the test code itself. Hope this post has been informative, and happy coding!

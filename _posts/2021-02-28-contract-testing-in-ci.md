---
layout: post
title:  "Contract testing in CI"
date:   2021-02-28 00:00:00 -0000
categories: programming
tags: python programming testing
---

Repo containing the code can be found in [python-contract-test-demo](https://github.com/edwintye/python-contract-test-demo).

A full pipeline can be seen in [github action workflow file](https://github.com/edwintye/python-contract-test-demo/blob/main/.github/workflows/main.yml).
Main steps of our concern is just the contract test step using [dredd](https://dredd.io) via `npm test`!
Nearly all the other steps in our CI pipeline is getting the environment to a state where we can run that command.

### What is contract testing

A contract test is to ensure that services know how to talk to each other; contracts are usually based on api calls
be it REST, gRPC, GraphQL, or whatever protocol of choice.  By enforcing request/response pair between
the client and server, the interactions will be defined as code and validated as part of normal testing.  It
is important to note that contract testing does not verify functionality.  Namely, if the service answers
the question "what is the next prime number?" then all we want to confirm is that we get a number back;
no one will verify the correctness because you don't need to make that api call if you already have the answer!

Two different train of thoughts exists surrounding the interaction of client and server:
  1. work in a collaborative environment, probably with code sharing,
  2. in a hostile setting where the clients only sees a live service bar documentation.

In the first scenario, the most well known contract testing tool is probably [pact](https://pact.io), which aims
to eliminate E2E testing completely by introducing *pacts* test on both the client and server side.
Alternatively, a server side focused testing tool like dredd ensures that the (open) api spec
and service has full compatibility.  Choice of tooling is therefore biased towards what and who the service is for;
the expectation of a B2C api vs a service used internally in an organization will be vastly different.

Generally speaking, contract testing from the client side is much less important because the server should
never introduce breaking changes. Once we understand how the server behaves and have mocked the api calls
on the client side development, the expectation is that the same api call will remain valid forever.  

### Why run contract test in CI

We take the approach that contract test is part of standard testing just like unit and integration tests; to provide
a fast feedback when unintended changes have been introduced. The aim is to ensure that we are not making
any breaking changes, or,
if we are making breaking changes then the api spec and code should be at least in sync. 

There is nothing worse than deploying an update, even via canary release, when the impact to the clients
can be caught much earlier in development.  In the scenario where the api documentation is managed
centrally, then the development of api spec/service is out of sync by design and CI acts as the synchronization
step.  

### Setting it up

We store the open api spec in the same repo as the service for convenience as 
[api/open-api.yml](https://github.com/edwintye/python-contract-test-demo/blob/main/api/open-api.yml).
In the case where the api spec sits elsewhere, the pipeline will also need to have a download step
which in the simplest case a `curl -O <some spec>` command suffice.  None of the 500s status codes are
present in the spec because they are not driven by the client, and indeed 500s should not
occur under normal operation.

As said previously we will be using dredd to ensure that the service conforms to the api spec.  Because dredd
is just a JS package, we can greatly simplify the testing by introducing a
[package.json](https://github.com/edwintye/python-contract-test-demo/blob/main/package.json) file;
using a JS package manager helps with the 
installation of the dependencies and executing the test improving repeatability.

In this example, we have an application written in python using fastapi.  As dredd is JS based this demonstrates
how the contract test is decoupled from the main codebase but still runs in the same CI pipeline.
Configuration for dredd is
[api/dredd.yml](https://github.com/edwintye/python-contract-test-demo/blob/main/api/dredd.yml) where line 2
line 4 specifies the test hooks and how to spin the server up respectively.
Note that in the pipeline we only trigger the contract test on a pull request as per

```yaml
if: github.event_name == 'pull_request' || github.ref == 'refs/heads/main'
```

but given that the contract test only takes a few seconds there isn't a real reason to not do that for
every push.

Although dredd will read the api spec and runs the tests using the examples and verify the returned
http status code, our service here has the full `GET`, `PUT`, and `DELETE` operations which requires
a little bit of setup.  The most common way is to create a state in the service before the execution
of each http call.  We take an alternative approach in which the order of http requests are
made such that a `GET` operation with 200 response is executed after a `PUT`.  This can be seen in
the [hook file](https://github.com/edwintye/python-contract-test-demo/blob/main/api/hooks.js)
where the sequence of play is defined at the top.

To force a 404 on a `GET` request, we make it the first test where the service has an empty state.
Equivalently, performing a `GET` after the `DELETE` also achieves the same thing.
Some status code are particularly hard to test, in our example 422 is triggered by a string
when it is expecting an integer, a scenario not found as part of the examples.
Unfortunately, the only solution here is to manipulate the request in the hook unless we are willing to
have tests separate from the api spec.  Because contract test is deliberately light weight and not a
replacement of full E2E test suite, the recommendation is to stick closely to the api spec.  

### Using containers for testing

Like most toolings out there, we can invoke the tests using a pre-build docker image, here supplied by
developers of dredd themselves.  The most important benefit with using docker containers is the ability
to now deploy the test anywhere with the flexibility to target an address as desired.

To demonstrate, let's assume that we are doing dev work locally and have a server running with the `--reload` option.
We can simply run the command below in the project root to achieve the same as
`npm test` used previously.  One main difference is that we are no longer using the configuration file,
instead we supply all the necessary information via the cli arguments explicitly.  

```bash
docker run -it -v $(pwd):/mnt apiaryio/dredd:13.1.2 /mnt/api/open-api.yaml localhost:8000 --hooksfile=/mnt/api/hooks.js
```

Moving the test to say a cloud environment is simply as we would only need to add the api spec to the image.  Again,
if the api specs are stored in a service catalogue then we can download the file at runtime. This expands the
scope of testing massively as we can invoke the contract test from a different environment to where the service
is hosted: the test scope in this case may expand to network connectivity, mTLS, authorization, etc.

### Final words

Although we have demonstrated how to bake in contract test as part of CI, note that the contract tests here only
assert the scenarios defined by the api spec; therefore only the *positive cases* are tested.  More concretely,
a negative case is when we wish to test a scenario that is not specified in the api spec.  In our demo, an
example would be a (http code) 503/504 error.  A production service will almost surely have either implemented
its own timeout, but forcing a long request may be impossible or simply not worth the effort.
Similarly, the purpose of contract test demonstrated here is not to test what happens when the service sits
behind a gateway but fail fast, and we will skip such tests during CI.  

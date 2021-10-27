---
layout: post
title:  "The nightmare of keeping containers updated"
date:   2021-10-08 00:00:00 -0000
categories: process docker
---

For anyone who has worked a corporate job with a way too eager security team, they will understand a
lot from just the title.  For those who are still working with the notion of docker images are
immutable, I also wish that the real world is that simple.  Let me talk about the various different
build + scan strategies that I have seen/use myself.

Essentially, the problem is that there will be a security mandate for how
"clean" images should be when at the different stages:
* Build time
* Deploy time
* Run time

The definition of "clean" varies, but is pretty much always based on some combination of
[SAST](https://en.wikipedia.org/wiki/Static_application_security_testing) and
[DAST](https://en.wikipedia.org/wiki/Dynamic_application_security_testing) performed by the scanner of
choice. In general, it is very easy to comply to the security posture as long as it is well documented
for any given stage. Trouble begins when the development to production timeline is long, or a deployed
version sits in the same state for extended period of time.

## What is the problem?

Main issue security policies is that a single policy cannot cover all three stages &mdash; build, deploy, run time.
Consider the scenario following two scenarios:
1. Build the image today and deploy to dev/stage.  Deploy to production a week later.
2. Deployed to production, and application is never updated.

In both cases above, we have a disconnected timeline where new vulnerability may be found.  This is
because the scanners (hopefully) will update their vulnerability database and patches made available
over time. The longer we wait between build and deploy, the more likely it will be that we have to
rebuild the image. Same logic applies where a container running in production may become insecure.

Note here that some programming languages makes an image harder to maintain. Bytes complied languages like
Python requires a whole suite of *stuff* inside an image to run, and the same with JVM languages. For
languages that can compile to a single binary, like c++ or golang, a scratch image suffice with relatively
minimal upkeep. Before we talk about the different ways to keep images update to date, let's explore the
problem of

## When to do security scans?

The most aggressive setup would be to have continuous scanning for every commit in the mainline.  If
pull/merge request is required then no new security flaws should be introduced when accepting a merge.
Generally speaking we don't put the full set of gates in front of every commit as that slows the development
down too much. Most common solution is to create a release candidate from the mainline where we can work
through the problems if any.

Naturally, the speed where fixes are introduced in the release candidates dictate the cadence of the
deployment. This can be a bottleneck for full time engineering teams &mdash; unlike open source projects
&mdash; where the desired deployment frequency is daily. In the current tech landscape of
"move fast and break things" it is probably fair to *scan but not block* deployments. New issues can be
fixed before the next version.

There is also an easy answer: Just scan before every deployment! A suggestion I have heard from
the security team.  A difficulty here is that a deployment may not have the ability to scan; those
who uses FluxCD or ArgoCD on Kubernetes do not have pipelines for their deployment. If there is
no pipeline then the scan must be done on either the build stage or by the image registry.

## Upstream triggers for tags

## Package dependencies version bump

## Warning from security scanners

## Nightly for mainline


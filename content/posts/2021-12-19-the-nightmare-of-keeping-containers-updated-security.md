---
title: "The nightmare of keeping containers updated - Security"
date: 2021-12-19
tags:
  - docker
  - process
---

For anyone who has worked a corporate job with a way too eager security team, they will understand a
lot from just the title.  There is usually some "security policy" in place with various "gates"[^1] that
an application has to pass before it is considered clean enough for deployment.  Furthermore, a clean
docker image has a shelf life; everything is good as long as the image does not have a match against
the (constantly changing) vulnerability database. 

The definition of "clean" varies, but is pretty much always based on some combination of
[SAST](https://en.wikipedia.org/wiki/Static_application_security_testing) and
[DAST](https://en.wikipedia.org/wiki/Dynamic_application_security_testing) performed by the scanner of
choice. SAST is performed (usually once) at during build/deploy time, while DAST is continuously happening
in the background on the host of the application during runtime.  In general, it is very easy to comply to
the security posture as long as it is well documented for the given stages and sensible, i.e. only cares about
issues with known fixes and easy to whitelist false positives. Trouble begins when the development
to production timeline is long, or a deployed version sits in the same state for extended period of time.

So before we talk about the different ways to keep images update to date, let's explore the problem of having
a long lead time to deployment.

## What is the problem?

First, let's assume that we always scan the docker images when it is pushed to the repository manager via
SAST.  Then DAST kicks in when it is deployed and running in dev/uat/prod (depending on how brave you are).
Main issue of security policies is that finding a balance between the three stages &mdash; build, deploy,
run time &mdash; is hard and exacerbated when teams move at a very slow pace.
Consider the scenario following two scenarios (that we briefly touched on at the end of
[last post]( {{< ref "2021-12-18-the-nightmare-of-keeping-containers-updated-dependency" >}} ):
  1. Build the image today and deploy to dev/uat.  Deploy to production a month later.
  2. Deployed to production, and application is never updated.

In both cases above, we have a disconnected timeline where new vulnerability may be found.  This is
because the scanners (hopefully) will update their vulnerability database and patches made available
over time. The longer we wait between build and deploy, the more likely it will be that we have to
rebuild the image just before deployment. Continuous delivery isn't quite "continuous" anymore if
the same (security control) gate reappears before deployment.

[Ranting a little] Same logic applies where a container running in production may become insecure; the
log4j shit storm of December 2021 taught us that patching should be done on both the image (JVM) and
application (library) level[^2]. There is also the reality where if vulnerabilities are known to be
being exploited in the wild, you cannot wait. The time between some vulnerability database is updated,
propagated to your server, and a report generated to some stakeholder is too slow. Operation teams would
have started working before some executive understands the severity and required actions. In those
situations, we can throw every runbook out the window and just have faith in the Ops team with their
skills and knowledge[^3].

## When to do security scans?

If the long lead time to deploy creates such a problem, then why not find a solution to tackle this
exact issue.  In fact there is an easy answer: Just scan before every deployment! A suggestion I have heard
from the security team.  A difficulty here is that a deployment may not have the ability to scan; those
who uses FluxCD or ArgoCD on Kubernetes do not have pipelines for their deployment. "Deployment" is actually
a change in the config file within a git repo when you do GitOps.  If there is no pipeline then the scan must
be done on either the build stage or by the image registry.

Scanning the images in the registry is a nice idea, until someone tries to implement it and realize
scanning **all the artifacts** is going to require a dedicated cluster.  Remember that I said one
of the triggers for docker image rebuild should be via upstream trigger?  Well, imagine you have an application
that uses `python:3.9`, a new patch version comes through and we rebuild the image of all 300 tags of
this application.  Multiply that by all the application you build and use.  Good luck and have fun.

Without doubt there should be a smarter policy, as older tags usually exists for audit purposes only.
Indeed, a smart repository manager will check if there are (pull/push) actions on the images and can
purge those that are inactive [dockerhub offer this via subscription].  Combined with some intelligent
dependency/layer analysis, scanning all the images in your image repository may be possible.
However, flagging a vulnerability for an almost stale image leads to a cry wolf situation and eventually
no one will pay attentions to the real issues.

## Build time scanning

Now our conclusion may be that we just shift&ndash;left and enforce SAST as part of CI/CD pipeline.
Combined with the acceptance that there is a higher Ops price to pay for slower moving applications,
we can at least entertain the idea of maintaining certain security posture for docker images.

The most aggressive setup would be to have scanning in place for every commit in the mainline.
Generally speaking putting the gate in front of every commit slows down the development a bit too much,
and totally unreasonable for teams that does trunk based development. A good compromise here is probably
to only enforce scans on release (candidates).  Alternatively a nightly build + scan where engineers
can tackle the issues first thing at work can work for certain teams.  For those that uses feature
branches a scan may be triggered on pull/merge request.  In general, regular rebuild with full OS + 
library dependencies update
[as said previously]( {{< ref "2021-12-18-the-nightmare-of-keeping-containers-updated-dependency" >}} )
will mitigate most if not all the issues.

Full time engineering teams have a different release cadence relative to say open source projects.  My
personal preference is daily deployment, hence my expectation would be that scanners don't block progress
unless it is an existing issue and after a grace period. An application on slower pace may choose to block
and forbids the introduction of any new security issues.  The worst type of blocks are those where you
don't have absolute control over.

With the proliferation of open source libraries, even in enterprises, means that at some point a vulnerability
remains until someone puts out a patch. In the unfortunate event that you are using a not very
well maintained library, then either 1. find an alternative library, 2. you fork the original and create a
new dependency hell for yourself, 3. accept that you are doomed. On a positive note, most SAST scanners are
not configured to flag up issues that cannot be resolved. No patch, no alerts, successful pipeline and
happy days all round.

## Runtime scanning 

In the event where the SAST fails to pick up something as mentioned previously, DAST may come to your
rescue (or puts you back into the nightmare of unmaintained open source package). For those unfamiliar
with DAST, you can just assume that a penetration test is being carried out on your system continuously.
Although this is something you can embed into your CI/CD pipelines, you typically don't want a pipeline
to run for too long.  So a common approach is to deploy the DAST tool of choice onto the hosts of the
test environments and allow scanning to occur for all the applications that are deployed there.
The aim is to pick up on stuff that was missed by SAST, and my personal experience is that every issue
the DAST raises turns out to be a nightmare to deal with.

An example would be that DAST figures out that your application is susceptible to SQL injection. A
sensible application would have validated all the data fields and perform the necessary escapes when
relaying information onwards.  An error on this level may require a full sweep of the code base to ensure
such fundamental error is not wide&ndash;spread, an extremely costly event.

On the other hand, a security flaw may be traced back to the programming language.  More concretely, the
brilliant idea of using the most up&ndash;to&ndash;date JVM backfires and forces you to rollback. Now
you have to downgrade + rebuild, overwrite the existing image:tag, and redeploy.
In the ideal scenario where we have the appropriate toolings in place and runs on kubernetes, then a
fully automated refresh can be performed via a
[rebase](https://buildpacks.io/docs/concepts/operations/rebase/) on all affected runtime layer,
and rely on automated reschedule using
[deschudler](https://github.com/kubernetes-sigs/descheduler) with `maxPodLifeTimeSeconds` coupled
with `imagePullPolicy=Always` on the pods.

Hopefully at this point you are a bit more educated about managing docker containers, while also
being more confused at the same time. Maybe one day we will all figure out how to do this properly and
have a template to follow. Until then, good luck with your own container journey.

---

[^1]: A tick box exercise to ensure that the application is deemed secure. Usually automated within a pipeline
      and will not fail unless the security team's sole purpose in the company is to block progress.

[^2]: Note here that some programming languages makes an image harder to maintain. Bytes complied languages like
      Python requires a whole suite of *stuff* inside an image to run, and the same with JVM languages. For
      languages that can compile to a single binary, like c++ or golang, worst case scenario is to deploy the
      application in a `scratch` image as a vulnerability mitigation strategy.

[^3]: In a nutshell, invest in your Ops team as if they are firefighters.  Regular training, drills, and live
      action when called upon.

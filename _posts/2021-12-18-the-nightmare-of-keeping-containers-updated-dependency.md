---
layout: post
title:  "The nightmare of keeping containers updated &mdash; Dependency"
date:   2021-10-08 00:00:00 -0000
categories: process docker
---

For those who are still working with the notion of docker images are immutable, I also wish that
I can go back to simpler days.  Unfortunately keeping the images at the cutting edge &mdash;
driven by the motivation of minimizing pain of skip version updates &mdash; require a lot of work.
I will talk about the various different build + scan strategies to keep containers updated that I
have seen/use myself.  This is the first post of a two part series, focused on dependencies, and see the
[next part]({% post_url 2021-12-19-the-nightmare-of-keeping-containers-updated-security %})
on keeping containers updated from a security perspective.

## What's in an image?

Let's start by go through how we build a docker image.  Generally speaking we have 3 components:
 1. Build image &mdash; controls the (major/minor) version of the programming language version.  Most
    recently golang release 1.17, where a (free) performance increase can be observed by simply upgrading
    to this version.
 2. Runtime image &mdash; is partly dictated by the build images as per the programming language version.
    Although we can change the distribution, there really isn't any benefits.  Therefore, only the OS level
    packages are amendable.
 3. Application &mdash; is often OS agnostic, and depends only on the libraries it uses and the programming
    language version.

For applications that can be shipped via a single binary, using a `scratch` image for runtime
reduces our problem down to only the build image and application. Quite often tho, we do want
some ability to troubleshoot and will have the application ship with multiple runtime images: `scratch`
for the smallest footprint, and a slim version for debugging. Whether we want to maintain
dedicated `Dockerfile` or delegate some responsibilities via 
[buildpack](buildpack.io), the same issues remain.  Without loss of generality, we can say
that all 3 components can be categorized into two types of dependencies:
  * Programming language version. 
  * Import package/library version.
 
## Upstream triggers for tags

Let's assume that our docker image is `python:3.9`, an official image on dockerhub and is updated regularly
to the latest patch version.  We can easily handle the update through a web hook such that an update to the
base image forces a rebuild; dockerhub offers this natively for paid users via the *build* tab where
you can manage *triggers*.  Updating minor versions would require manual intervention, and if the application
moves slowly this is probably the preferred approach.

If you are in a position where you can access the public registries, just having the triggers will solve
the problem.  If you are using an internal repository manager such as Artifactory or Nexus, I have potential
bad news for you.  Repository managers is set to store the docker images on its system on the first request,
then uses that as a cache for future fetches. A trigger via dockerhub in such situation will simply lead
to a rebuild of the same (final) image due to caching.   Now we need to be hooked against the repository
manager, while making sure that the repository manager respects the external updates.

## Auto triggers via dockerfile update

Some developers are more conservative and may wish to tag against exact patch versions instead,
e.g. `python:3.9.8`.  A new build will be triggered via a version bump on the dockerfile, through the
use of
[dependabot](https://docs.github.com/en/code-security/supply-chain-security/keeping-your-dependencies-updated-automatically/configuration-options-for-dependency-updates#configuration-options-for-private-registries)
or similar tooling. Biggest difference here is that the CI pipeline re-runs automatically against the new
(target) version.  A couple more adjustments may be required such that the programming language version inside
the CI definition matches the `Dockerfile` but that is a comparatively small task. Keeping pace with the bleeding
edge with this approach is probably best suited for applications that is on a fast development cycle without the
need to offer LTS.

## Package dependencies version bump

Dependency checking tools like
[dependabot](https://docs.github.com/en/code-security/supply-chain-security/keeping-your-dependencies-updated-automatically/configuration-options-for-dependency-updates#configuration-options-for-private-registries)
can again create merge request by bumping the versions of the imported libraries. This is a relatively well
established practice (at the time of writing).  Pretty much the sole reason to not do automated version bumps
is that you can't ship the application in a timely manner.  Creating the artifact without shipping may create
a false sense of security (pun intended) without the appropriate tooling in place. This leads us nicely onto
the security aspect of docker images in the
[second part of this series]({% post_url 2021-12-19-the-nightmare-of-keeping-containers-updated-security %}).

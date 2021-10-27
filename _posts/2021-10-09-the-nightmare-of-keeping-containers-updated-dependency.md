---
layout: post
title:  "The nightmare of keeping containers updated - Dependency"
date:   2021-10-08 00:00:00 -0000
categories: process docker
---

For those who are still working with the notion of docker images are immutable, I also wish
that the real world is that simple.  Unfortunately keeping the images at the cutting edge &mdash;
driven by the motivation of minimizing pain of skip version updates &mdash; require a lot of work.
I will talk about the various different build + scan strategies that I have seen/use myself.

## What's in an image?

Let's start by go through how we build a docker image.  Generally speaking we have 3 components:
1. Build image,
2. Runtime image,
3. Application.

Whether we want to maintain dedicated `Dockerfile` or delegate some responsibilities via 
[buildpack](buildpack.io), the same issues remain.  Without loss of generality, we can say
that all 3 components can be *updated* without knowledge of each other.

*Build image* controls the (major/minor) version of the programming language version.  Most
recently golang release 1.17, where a performance increase can be observed by simply upgrading to it.


*Runtime image* is partly dictated by the build images as per the programming language version.
Although we can change the distribution, there really isn't any benefits.  Therefore, only the OS level
packages are amendable. Binary programs are special cases as they can use a `scratch` image which
eliminates the complexity here. This only applies to some programming languages and can be a poor choice
even for those that qualify as it significantly reduce the debug capability when things go wrong.

*Application* 

## Upstream triggers for tags

## Package dependencies version bump

## Warning from security scanners

## Nightly for mainline


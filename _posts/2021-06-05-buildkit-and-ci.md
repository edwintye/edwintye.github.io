---
layout: post
title:  "Buildkit and CI"
date:   2021-06-05 00:00:00 -0000
categories: programming
tags: programming docker
---

After collaborating on a repo on Github that uses buildx, it was slightly shocking to see how fast the
builds.  My companies' Jenkins docker build on a very similar image seems to take almost double the time.
The great thing about using the
[buildx Github action](https://github.com/docker/setup-buildx-action)
is that docker themselves provided it, and can be used simply like

```yaml
- name: Docker Setup Buildx
  uses: docker/setup-buildx-action@v1.3.0

- name: Build image
  run: docker build .
```

The speed gain is worth it especially if you have limited amount of CI minutes in private repos. My natural
response is to try replicating this in Jenkins for our internal build.  After supercharging myself with
confidence after consulting the
[official doc](https://docs.docker.com/develop/develop-images/build_enhancements/),
it was deeply disappointing that the command

```groovy
docker buildx build .
```

does not exists, nor does buildkit

```groovy
environment{
    DOCKER_BUILDKIT = "1"
}
```

because the docker engine does not have those features. Lesson of the day is that private build chain/tooling
is not only hard to maintain, but will likely miss out on cutting edge features.

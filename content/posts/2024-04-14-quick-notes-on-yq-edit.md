---
title:  "Quick notes on yq edit"
date:   2024-04-14
tags:
  - programming
  - helm
---

One of the best thing about kubernetes, and especially gitops, is that we can re-use the same definitely
across many different environment and clusters via very simple yaml manipulation. However, it is also true
that editing yaml en-masse is not fun and automation is highly desirable. Most people will eventually turn
to `yq`, and at the same time be slightly stuck on the syntax. So I am just out here documenting a few
of the most used commands in my normal work.

To find all the clusters that is current set to image `1.0.0` for application `app`

```shell
yq 'select(.app.image.tag=="1.0.0")' | filename *.yaml
```

which tells us which file satisfies that condition. Sometime we may want to only find the image for applications
that have been enabled.

```shell
yq 'select(.app.enabled==true and .app.image.tag=="1.0.0")' | filename *.yaml
```

Then if we want to do an in-place update of all the images to a mor up to date version on the yaml file

```shell
yq -i 'with(.app; select(. | .enabled==true and .image.tag="1.0.0") | .image.tag="2.0.0")' *.yaml
```

But there are cases where the yaml have not been properly formatted before so the minor change turns out to be way
bigger than expected. In those cases we can generate the diff on those selected changes by first formatting the
yaml - wrapped in the following shell function `yq_edit` (which I am sure you would have encountered before
in some shape or form if you live on github)

```shell
function yq_edit() {
  yq eval --exit-status '.' "$2" | tee out1.yaml
  yq eval --exit-status "$1" "$2" | tee out.yaml
  diff -u out1.yaml out2.yaml | tee out.patch
  patch "$2" < out.patch
  rm out1.yaml out2.yaml out.patch "$2.orig"
}
```

which allows us to perform updates easily via

```shell
yq_edit 'with(.app; select(.image.tag="1.0.0") | .image.tag="2.0.0")' *.yaml
```

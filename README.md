### Hugo setup

The theme used here is the [hugo-book](https://github.com/alex-shpak/hugo-book) via hugo modules
&mdash; and is vendored to ensure build consistency.
This can be changed in `hugo.yaml` and then run

```shell
hugo mod get -u
hugo mod vendor
```

To test the build locally,

```shell
hugo build
hugo --gc --minify
```

or to serve the website

```shell
hugo server
# other common flags
# -D : build drafts
# -F : build future dated pages
```

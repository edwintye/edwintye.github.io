### Hugo setup

The theme used here is the [hugo-book](https://github.com/alex-shpak/hugo-book) via a submodule
&mdash; the theme setup (at the time of writing) installation instructions uses a standard `git clone` but
importing this as a submodule is highly recommended as per the hugo official guide. 

```shell
git submodule add https://github.com/alex-shpak/hugo-book.git themes/hugo-book
```

However, our `.github/workflows/hugo.yaml` differs from the official guide in that our `Checkout` action
is set to a shallow clone only.

```yaml
with:
  fetch-depth: 0
```

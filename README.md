### Hugo setup

The theme used here is the [hugo-blog-awesome](https://github.com/hugo-sid/hugo-blog-awesome) via a submodule
&mdash; the theme setup (at the time of writing) installation instructions uses a standard `git clone` but
importing this as a submodule is highly recommended as per the hugo official guide. 

```shell
git submodule add https://github.com/hugo-sid/hugo-blog-awesome.git themes/hugo-blog-awesome
```

However, our `.github/workflows/hugo.yaml` differs from the official guide in that we our `Checkout` action
is set to a shallow clone only.

```yaml
with:
  fetch-depth: 0
```

Highlight style is obtained from `hugo gen` and changed from `emacs` to `onedark` because there is some
compatibility issue between the `emacs` syntax highlight and the theme. 

```bash
hugo gen chromastyles --style=onedark > assets/code-highlight.css
```

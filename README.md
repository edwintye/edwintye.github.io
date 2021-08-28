### Jekyll Theme

The theme used here is 100% based on [broccolini/swiss](https://github.com/broccolini/swiss)
with additional code highlighting via [_syntax.scss](/_sass/_syntax.scss).  This is achieved by
coping: _layouts/, _sass/, _includes, and assets/syntax.css here then editing the various
themes to include the `_syntax.scss` file.

Highlight style is obtained from pygments, emacs style, by generating it from the source as per below.

```bash
pygmentize -S emacs -f html -a .highlight > _syntax.scss
```

---
title: "Moving from Jekyll to Hugo"
date: 2023-03-26 00:00:00 -0000
tags:
- programming
---

After many months of procrastinating I have finally made the leap and move this page to [hugo](https://gohugo.io).
The primary reason of moving is that I am must more comfortable with the use of hugo as I am a golang developer
and also had to use it at work. Generally speaking, organizations are less likely to use jekyll for their
documentation/blog. Even so the switch from one markdown rendereing framework to another is mnior, the additional
cost is unnecessary for those who publish their blog entry for both work and personal site simultaneously. The
is also the dependency on github, who very kindly manages a lot of steps for us but also introduces extra
friction.  For example:
* The need to keep updating the `gem` dependency `github-pages`.
* Inability to add extra plugins for say diagrams, maths, etc.
* Need to remember there are separate build path for ruby2 and ruby3, see
  [pages-gem#752](https://github.com/github/pages-gem/issues/752) for details.

None of the three points above, even in combination, were sufficient to push me away. As said, the main problem
was the micro adjustments required to transfer my blog posts to my personal page (here).

The full migration process were much simpler than anticipated as the hugo documentation on hosting via
github pages were very comprehensive.  My steps were as follows:
1. Selecting a new theme from hugo - I actually watched Kris Nóva publish her site live on twitch and decided to
   replicate by following her steps and repo (and of course some copy and paste).
2. Add the theme via `.gitmodules`.
3. Selecting an acceptable syntax highlighting via css using `hugo gen chromastyles`.  A list of examples
   can be found [here](https://xyproto.github.io/splash/docs/all.html).
4. Move all the `.md` files to the correct locations and consolidate categories and tags into just tags.
5. Remove layout (no longer using custom layout) and tidy up the date as the date format can be in the form of
   `2006-01-02` (the golang version of reference time).
6. Moving the static image files to `/static/images`.
7. Convert the flow diagrams from image to a [GoAT diagrams](https://gohugo.io/content-management/diagrams/)
   using [ASCIIFlow](https://asciiflow.com/).
8. Remove the extensive use of `&mdash;` and `&ndash;` to simple `-` as hugo does not embrace full html functionality.
9. Add the hugo workflow into `.github/workflows/hugo.yaml` and remove the old jekyll workflow which "tests" the
   build (aka just compiles the static files).  Yes, I have effectively removed testing on branch + PR, but I think
   we can live with that on a personal blog.
10. Change the repo `Settings` --> `Pages` --> `Build and deployment` --> `Source` from "Deploy from a branch"
    to "GitHub Actions". 

That is it, and what you see now is the new version. Now that I have finished the move there will be no excuses
and more posts will be coming soon.

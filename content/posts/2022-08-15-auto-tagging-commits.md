---
title: "Auto tagging commits"
date: 2022-08-15
tags:
  - process
---

TLDR: Add datetime and commit hash in the form of `vX.X.X-datetime-hash` on every push using the following command.

```shell
git tag -a $(git describe --exclude "v*-*-*" --tags --abbrev=0)-$(date +"%Y%m%d%H%M%S")-$(git rev-parse --short=12 HEAD) -m "\n$(git log --oneline $(git describe --tags --abbrev=0 @^)..@)" && git push origin --tags
```

## Now the slightly longer version with a bit more info.

One of the interesting things I have learnt from the golang ecosystem is how strict semver tagging
is not a requirement; everywhere in general. For example, it is quite common to see entries like these in
`go.mod` (equivalent to `package.json` for JS and `requirements.txt` in python)

```golang
require (
    golang.org/x/net v0.0.0-20220624214902-1bab6f366d9e
    golang.org/x/sys v0.0.0-20220610221304-9f5ed59c137d
)
```

where the datetime and git hash is used for tracking with a fix semver of `v0.0.0`. This idea of including
a time and hash is actually very useful when it comes to cloud native developments as quite often we
need to rebuild a new docker image and push the tag through.  After like a couple of minutes on google,
we already found the solution: [autotag](https://github.com/pantheon-systems/autotag).  Unfortunately,
setting this up proved to be more painful than we can tolerate when you build agents run kubernetes via Jenkins[^1].
We ended up using this one-liner

```shell
git tag -a $(git describe --exclude "v*-*-*" --tags --abbrev=0)-$(date +"%Y%m%d%H%M%S")-$(git rev-parse --short=12 HEAD) -m "\n$(git log --oneline $(git describe --tags --abbrev=0 @^)..@)"
```

where it adds a tag the corresponding commit message.  The new tag is of the form `vX.X.X-datetime-hash`, and
`vX.X.X` is the latest tag of that form.  More concretely, if we never bump semver it will remain the same forever.
The datetime component includes the second, and the commit hash is limited to the first 12 characters. Commit message
of the tag includes all the commit messages since the last tag with a newline at the start. This is a safe operation
as long as parallel builds on the same commit is disabled. Alternatively, you can choose to only push on main
rather than feature branches.

For local development and a [OMZ](https://ohmyz.sh/) user myself (with the git plugin), I also have also added the alias which combines
the create tag line above and the push of the tag as `gpt`.

```shell
alias gpt='<the crazy line before> && git push origin --tags'
```

Every push is now automatically tagged and a new docker image built. For systems that can use this type of
versioning, we can even start importing feature branches of external libraries via using this type of tagging. 

---

[^1]: We use docker images as cache of our tools, and the security posture of git - e.g.
      https://github.com/actions/checkout/issues/760 - made this virtually impossible even with the correct user (1000).

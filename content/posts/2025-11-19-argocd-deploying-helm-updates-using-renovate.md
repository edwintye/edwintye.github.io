---
title:  "ArgoCD deploying helm updates using Renovate"
date:   2025-11-19
tags:
  - programming
  - helm
---

ArgoCD is one of the most well know GitOps tool, and it is excellent at rapid deployment with zero
interaction when using [version ranges](https://argo-cd.readthedocs.io/en/stable/user-guide/tracking_strategies/).
However, the standard procedure is to use a pinned version in production and a "relax" constraint in non-production
to stop unexpected behavior creeping in.
The relaxation in non-production can be limited to just the patch version or up to the minor version,
entirely dependent on the acceptable risk level. Therefore, the only step that requires manual intervention is
the deployment to production.

Here we assume that automated promotion to production is not an option, which could be due to non-technological
constraints or just risk is too high.
In such scenario, a semi-automated process is still preferred to manually updating all yaml files for a pull request. 
This is where [Renovate](https://docs.renovatebot.com/) can be leveraged, and eliminate most of the toil bar the approval.
Let's start with assuming that we have a argocd application helm repo, broken down to teams.
Values file are all sitting under `envs` for simplicity’s sake with the targets named explicitly,

```
argocd
  +-- team-alpha
  |    +-- coredns-applications.yaml
  |    +-- sealed-secrets-applications.yamln
  |    +-- envs
  |        +-- cluster-a-values.yaml
  +-- team-beta
  |    +-- istio-applications.yaml
  |    +-- nginx-applications.yaml  
  |    +-- envs
  |        +-- cluster-b-staging-values.yaml
  |        +-- cluster-c-production-values.yaml
  +-- renovate.json
```

and one of the application is behind against the latest and look something like

```yaml sealed-secrets-applications.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets
  namespace: argocd
spec:
  project: default
  source:
    chart: sealed-secrets
    repoURL: https://bitnami-labs.github.io/sealed-secrets
    targetRevision: '2.16.0'
    helm:
      releaseName: sealed-secrets
      valueFiles:
        - ../envs/cluster-A-values.yaml
  destination:
    server: "https://kubernetes.default.svc"
    namespace: kubeseal
```

with values overriding the default image version of the chart using a standard `image` block

```yaml cluster-A-values.yaml
image:
  registry: docker.io
  repository: bitnami/sealed-secrets-controller
  tag: 0.30.0
```

such that we have two different things to maintain: the helm chart version, and the image version [^1].
In the ideal scenario, we would just enable Renovate and it scans the repo according to schedule,
detects the missing updates and works magically.
Unfortunately, the default will not work because argocd is disabled by default and
helm values is limited to only `values.yaml` at the top level.
In the simple case, we can expand both sets of regex and grab all the application + values file on each run.
Now 

```json renovate.json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "enabledManagers": ["argocd", "helm-values"],
  "argocd": {
    "enabled": true,
    "managerFilePatterns": ["/(^|/)argocd/.+applications\\.ya?ml$/"]
  },
  "helm-values": {
    "enabled": true,
    "managerFilePatterns": ["/(^|/)argocd/.+values\\.ya?ml$/"]
  }
}
```

Now Renovate will detect and raise PR according to the defined cron schedule on both the helm chart and images.
For those who cannot wait until a scheduled detection, they can even run it locally to create a PR

```shell
# To execute Renovate locally against a remote target.
LOG_LEVEL=debug renovate --dry-run=full <target-repo>
```

In situations where codeowners are defined along folder boundaries,
we would need to target applications along those boundaries to ensure that we don't test the limit of the approval process.
One obvious benefit to running `renovate` locally is that the PR would automatically be tied to the authenticated user,
which helps with auditing.

```shell
# Only trigger changes to a specific folder
LOG_LEVEL=debug renovate --include-paths="team-alpha/**" --dry-run=full <target-repo>
```

Alternatively, we can group the releases via [packageRules](https://docs.renovatebot.com/configuration-options/#packagerules)
which allow us to better manage the number of releases, i.e. per team or one release per target.
The config below will create separate branches, with separate PRs, for each cluster in scope
as well as each argo application. [^2]

```json
{
  "packageRules": [
    {
      "matchManagers": ["helm-values"],
      "additionalBranchPrefix": "cluster-{{lookup (split packageFile '-') 2}}-",
      "matchFileNames": ["/(^|/)argocd/team-[a-z]+/envs/cluster.+values\\.ya?ml$/"],
      "enabled": true
    },
    {
      "matchManagers": ["argocd"],
      "additionalBranchPrefix": "{{parentDir}}-",
      "managerFilePatterns": ["/(^|/)argocd/.+applications\\.ya?ml$/"],
      "enabled": true
    }
  ]
}
```

A special note here is that because of how `helm-values` allow indentation during it's detection,
which is beneficial to a subchart structure, it would also detect the `image` block with the correct syntax.
More concretely, a literal string of `values: |` will not be unmarshalled correctly into the map,
while the `valuesObject` block would be a valid map.
In the case where `valuesObject` is used, either in conjunction with `valuesFile` or by itself,
the regex for the `helm-values` manager would need to be adjusted accordingly.
Therefore, the best practice is to separate out the values used rather than defining them directly into the
argo application and have proper separation of concerns.

```shell
    helm:
      releaseName: sealed-secrets
      # would not be detected      
      values: |
        image:
          registry: docker.io
          repository: bitnami/sealed-secrets-controller
          tag: 0.30.0
      # would be catched by the `helm-values` manager
      valuesObject:
        image:
          registry: docker.io
          repository: bitnami/sealed-secrets-controller
          tag: 0.30.0
```

---

[^1]: For external dependencies with regular release cadence we should use the default image and just bump the chart.
      But this is an example!

[^2]: A later rule can override an earlier rule in `packageRules`, so be careful with the regex if the same
     match manger is used multiple times.


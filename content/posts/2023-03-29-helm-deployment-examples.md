---
title: "Helm Deployment Examples"
date: 2023-03-29
tags:
  - helm
  - programming
  - testing
---

## Background
A common problem with [helm charts](https://helm.sh/docs/topics/charts/)
is that the authors (or contributors) find it difficult to guarantee:
* No changes when refractoring,
* New features have no side effect,
* Bug fixes are targeted.

The core problem is that although helm charts are treated as artifacts and contains code, we don't usually apply
the standard programming practices when developing one. Even if the person raising the change is confident, it is
hard to prove to the reviewers in general without a full suite of tests.  

On the flip side, users of the same helm chart is often face with the same issue when upgrading to a newer version.
Namely, the predefined interface `values.yaml` is not subject to contract tests and the validity of the code,
api versions to be exact, is at the mercy of the kubernetes release schedule. The common solution
ends up being "just deploy it and see if it breaks" &mdash; a perfectly valid approach until you become an
open source project maintainer with thousands of companies relying on this very project.
Here we describe a middle round between zero validation and the full E2E tests used by the opentelemetry project.

## Generating example manifests
Let's assume that we have our internal chart named as `opentelemetry-collectors` which contains a collection of
the native api and CR (custom resources) for all our different setups.  Then we already have a stable deployment
using the helm chart, and we wish to ensure that our refractoring would make zero changes against a live cluster.
Naturally a `diff -r` between the existing and future manifests suffice and we can run this in CI outside the mainline.

> But what if the deployment happens outside of the chart repo?

Well that creates a little bit of an issue since you would need to keep a copy of the deployment manifest
inside the chart repo. The best case scenario would probably be to use a `values-everything-enabled.yaml` and
run a `helm template` to generate all the manifest, then compare the diff between before and after refractoring.
Since there is no easy way to show the diff between branches without files, we are forced to generate the
deployed manifests in say an `examples/` folder via `Makefile`

```makefile
generate-examples:
	EXAMPLES_DIR=examples; \
	EXAMPLES=$$(find $${EXAMPLES_DIR} -type d -maxdepth 1 -mindepth 1 -exec basename \{\} \;); \
	for example in $${EXAMPLES}; do \
	  	echo "Generating example: $${example}"; \
		VALUES=$$(find $${EXAMPLES_DIR}/$${example} -name *values.yaml); \
		rm -rf "$${EXAMPLES_DIR}/$${example}/rendered"; \
		for value in $${VALUES}; do \
			echo "$${EXAMPLES_DIR}/$${example}/rendered"; \
			helm template example . --namespace default --values $${value} --output-dir "$${EXAMPLES_DIR}/$${example}/rendered"; \
			mv $${EXAMPLES_DIR}/$${example}/rendered/opentelemetry-collectors/templates/* "$${EXAMPLES_DIR}/$${example}/rendered"; \
			rm -rf $${EXAMPLES_DIR}/$${example}/rendered/opentelemetry-collectors; \
		done; \
	done
```

The command above will generate the manifest for every `examples/<subfolder>/values.yaml` into
`examples/<subfolder>/rendered/`, and we can have `<subfolders>` names match against each type of usage we have
(or expected). For a refractoring, a git diff *should* show a grand total of **zero lines**. A new feature, if
the interface changes, will have no diff as well unless the example value files is updated. Bug fixes on the other
hand will trigger a diff. Unfortunately, some human intelligence is required to determine what is expected in
the change.

Now we have a mechanism to give a bit more confidence to the reviewers, how do we ensure that the helm changes
has updated the generated manifest? Obviously, we just test it by repeating the same process in CI. A fail is
triggered whenever the examples are not up-to-date. For open source maintainers, it is useful to pin the generated
manifest against a kubernetes version[^1] e.g. `helm template . --kube-version=1.15` to prevent environment
drift[^2].

```makefile
check-examples:
	EXAMPLES_DIR=examples; \
	EXAMPLES=$$(find $${EXAMPLES_DIR} -type d -maxdepth 1 -mindepth 1 -exec basename \{\} \;); \
	for example in $${EXAMPLES}; do \
	  	echo "Checking example: $${example}"; \
		VALUES=$$(find $${EXAMPLES_DIR}/$${example} -name *values.yaml); \
		for value in $${VALUES}; do \
			helm template example . --namespace default --values $${value} --output-dir "${TMP_DIRECTORY}/$${example}"; \
		done; \
		if diff -r "$${EXAMPLES_DIR}/$${example}/rendered" "${TMP_DIRECTORY}/$${example}/opentelemetry-collectors/templates" > /dev/null; then \
			echo "Passed $${example}"; \
		else \
			echo "Failed $${example}. run 'make generate-examples' to re-render the example with the latest $${example}/values.yaml"; \
			rm -rf ${TMP_DIRECTORY}; \
			exit 1; \
		fi; \
	done
```

In the case where we have chart dependencies, both commands above needs to be augmented by generating the manifests
of the sub-chart as well (details collapsed below). Unless the dependencies has also been committed to the git
repo (no, we are not going to argue about this here), an addition `helm dependency build` is required
before `helm template`.

{{% details "Additional block for helm dependencies" %}}
```makefile
			SUBCHARTS_DIR=$${EXAMPLES_DIR}/$${example}/rendered/${CHART_NAME}/charts; \
            SUBCHARTS=$$(find $${SUBCHARTS_DIR} -type d -maxdepth 1 -mindepth 1 -exec basename \{\} \;); \
            for subchart in $${SUBCHARTS}; do \
            	mkdir -p "$${EXAMPLES_DIR}/$${example}/rendered/$${subchart}"; \
            	mv $${SUBCHARTS_DIR}/$${subchart}/templates/* "$${EXAMPLES_DIR}/$${example}/rendered/$${subchart}"; \
            done; \
```
{{% /details %}}

The final helm chart repo committed to git would therefore look something like (or without the dependency
under `charts/`)
```
opentelemetry-collectors
  +-- charts
  |   +-- upstream-dependency-chart-0.0.0.tgz
  +-- Chart.lock
  +-- Chart.yaml
  +-- examples
  |   +-- deployment
  |       +-- values.yaml
  |       +-- rendered
  |            +-- clusterrole.yaml
  |            +-- deployment.yaml
  |            +-- rolebinding.yaml
  |            +-- sa.yaml
  |   +-- sidecar
  |       +-- values.yaml
  |       +-- rendered
  |            +-- sidecar.yaml
  +-- templates
  |   +-- _helpers.tpl
  |   +-- clusterrole.yaml
  |   +-- deployment.yaml
  |   +-- rolebinding.yaml
  |   +-- sa.yaml
  |   +-- sidecar.yaml
  +-- .helmignore
  +-- Makefile
  +-- values.yaml
```

We have explicitly included `.helmignore` in the folder structure above as a reminder that `helm package` will
include the `examples/` (sub-)folders by default. 

## Final words
We can also improve the checks by adding a dry run step to `check-examples` which further validates the rendered
manifests. Both the client and server side testing require a target kubernetes cluster with matching api
versions + CRDs and can be quite cumbersome to setup.  Generally speaking a dry run is just
[chart testing](https://github.com/helm/chart-testing)
on *easy mode* without the helm tests and the value added is small given the pre-requisite.  In the
[next post]( {{< ref "2023-04-01-testing-cr-in-helm-charts" >}} ),
we are going to talk about how to approach testing the custom resources generated in the examples without relying
on a live kubernetes cluster.

```shell
if ! kubectl apply --dry-run -f "$${EXAMPLES_DIR}/$${example}/rendered"; then exit 1; fi; 
```

---

[^1]: Probably the minimum supported version so that when the support for older kubernetes is fully deprecated
      diffs will be generated automatically.

[^2]: Can you really trust your developers to not upgrade helm?

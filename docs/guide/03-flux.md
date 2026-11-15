# 03 Flux

## What this adds

The cluster reconciles itself from this repository. Flux 2.10.0, installed
and kept running by the Flux Operator, polls `main` every minute and
applies `kubernetes/apps/`. Cilium and the Flux Operator itself are Helm
releases that Flux manages from the same files the bootstrap tasks install
from. From now on a change to the cluster is a merged pull request, not a
command.

## Before you start

- [02 Cluster](02-cluster.md): the cluster runs, Cilium was installed with
  `mise run bootstrap:cilium`, and `kubeconfig` exists in the clone.
- A clone with `mise install` done (`flux2` 2.10.0, `helm`, `kubectl`).
  Outside mise, export `KUBECONFIG=$PWD/kubeconfig` and put the mise tools
  on `PATH`.
- Network access to `ghcr.io` (Flux images and the flux-operator chart) and
  `github.com` (the repository).
- The repository is public, so Flux needs no credential (D10).

## Steps

### 1. The layout

```
kubernetes/apps/
  kustomization.yaml              # entry point: lists the namespace directories
  flux-system/
    kustomization.yaml            # lists the ks.yaml files
    flux-operator/ks.yaml         # Flux Kustomization for app/
    flux-operator/app/            # ocirepository.yaml, helmrelease.yaml
    flux-instance/ks.yaml         # depends on flux-operator
    flux-instance/app/            # fluxinstance.yaml
  kube-system/
    kustomization.yaml
    cilium/ks.yaml
    cilium/app/                   # ocirepository.yaml, helmrelease.yaml,
                                  # values.yaml, kustomizeconfig.yaml
```

Every application is `kubernetes/apps/<namespace>/<app>/`: a `ks.yaml`
(the Flux Kustomization, in `flux-system`, with `retryInterval: 2m` and a
timeout) and an `app/` directory with the objects. The layout is the one
of onedr0p/home-ops and buroa/home-ops, without their components. The
entry `kustomization.yaml` is written out instead of generated, so the
list of namespaces is visible in one file (D32).

Neither `flux-system` nor `kube-system` has a `namespace.yaml`: both exist
before Flux, and a namespace Flux does not own can never be pruned.

### 2. The FluxInstance

`flux-instance/app/fluxinstance.yaml` describes Flux itself:

- `distribution.version: 2.10.0`, exact, so Flux moves only through a
  Renovate pull request. A range like `2.10.x` would let the operator
  upgrade it on its own (D32).
- `sync`: `https://github.com/msavdert/homelab.git`, `refs/heads/main`,
  path `kubernetes/apps`. The operator creates a GitRepository and a
  Kustomization, both named `flux-system`; the default interval is one
  minute.
- `kustomize.patches`: helm-controller runs with
  `--feature-gates=DisableChartDigestTracking=true`. Without it, Flux
  writes the chart version as `1.20.4+<digest>`, and Cilium and
  flux-operator carry that version in their pod labels, so every adoption
  would restart their pods (D33, "When it goes wrong").

### 3. The HelmReleases

`cilium/app/helmrelease.yaml` and `flux-operator/app/helmrelease.yaml`
point at the OCIRepository next to them with `chartRef`. Their name and
namespace equal the Helm releases the bootstrap tasks create, so Flux's
first reconciliation is a Helm upgrade of the existing release, not a
second installation.

Cilium's values stay in `values.yaml`, the file `bootstrap:cilium` uses.
`app/kustomization.yaml` turns it into a ConfigMap with a hashed name
(`cilium-values-<hash>`), and `kustomizeconfig.yaml` writes that name into
the HelmRelease's `valuesFrom`. A changed value therefore changes the
HelmRelease, and Flux upgrades at once instead of at its next interval.

```
$ kubectl kustomize kubernetes/apps/kube-system/cilium/app | grep cilium-values
  name: cilium-values-8t86gb4dk2
    name: cilium-values-8t86gb4dk2
```

The two HelmReleases and the FluxInstance carry
`kustomize.toolkit.fluxcd.io/prune: disabled`. Removing a line from a
`kustomization.yaml` then cannot uninstall Cilium or Flux; removing them is
a deliberate step by hand.

### 4. Bootstrap

The Flux tree must be on `main` first: the FluxInstance syncs from there.
Then:

```
$ mise run bootstrap:flux
Pulled: ghcr.io/controlplaneio-fluxcd/charts/flux-operator:0.62.1
NAME: flux-operator
NAMESPACE: flux-system
STATUS: deployed
REVISION: 1
fluxinstance.fluxcd.controlplane.io/flux serverside-applied
fluxinstance.fluxcd.controlplane.io/flux condition met
kustomization.kustomize.toolkit.fluxcd.io/flux-system condition met
```

The output is from the first run; the task has since gained two more
waits (every Kustomization, every HelmRelease), which print further
"condition met" lines. It installs flux-operator with Helm from
`flux-operator/app/`,
applies the FluxInstance and waits until the FluxInstance, every
Kustomization and every HelmRelease is Ready. Flux then manages
flux-operator and the FluxInstance like any other application.

After this, `bootstrap:cilium` and `bootstrap:flux` are for an empty
cluster only. A `helm upgrade` by hand on a Flux-owned release fails on
field conflicts with helm-controller.

## Check

Run on 2026-11-15.

Adoption without a restart. With the feature gate active, Flux was made to
run a Helm upgrade of Cilium with unchanged inputs, which is the upgrade
path adoption takes:

```
--- before
ds gen=3 envoy gen=3 operator gen=3
5ffc2e5639d37b40cb73a92292d66010  -        # hash of all Cilium pod UIDs
helm revision 3 cilium-1.20.4
$ flux reconcile hr cilium -n kube-system --force
✔ applied revision 1.20.4
--- after
ds gen=3 envoy gen=3 operator gen=3
5ffc2e5639d37b40cb73a92292d66010  -
helm revision 4 cilium-1.20.4
```

The release was upgraded (revision 3 to 4); no pod template changed and no
pod was replaced.

The gate. Pull request #16 added a pod annotation to `values.yaml`. It was
merged at 16:17:18 UTC and nothing was run by hand. The annotation was on
the DaemonSet at 16:17:24; at 16:17:55:

```
$ git rev-parse origin/main
671c856df4ec50bfec90bb1816d5361564b3e11e
$ flux get kustomizations -A
NAMESPACE    NAME           REVISION                       READY  MESSAGE
flux-system  cilium         refs/heads/main@sha1:671c856d  True   Applied revision: refs/heads/main@sha1:671c856d
flux-system  flux-instance  refs/heads/main@sha1:671c856d  True   Applied revision: refs/heads/main@sha1:671c856d
flux-system  flux-operator  refs/heads/main@sha1:671c856d  True   Applied revision: refs/heads/main@sha1:671c856d
flux-system  flux-system    refs/heads/main@sha1:671c856d  True   Applied revision: refs/heads/main@sha1:671c856d
$ flux get helmreleases -A
NAMESPACE    NAME           REVISION  READY  MESSAGE
flux-system  flux-operator  0.62.1    True   Helm upgrade succeeded for release flux-system/flux-operator.v4 with chart flux-operator@0.62.1
kube-system  cilium         1.20.4    True   Helm upgrade succeeded for release kube-system/cilium.v5 with chart cilium@1.20.4
$ kubectl -n kube-system get ds cilium -o jsonpath='{.spec.template.metadata.annotations}'
{"cilium.io/cilium-configmap-checksum":"318a3e47...b34830","homelab.savdert.com/managed-by":"flux","kubectl.kubernetes.io/default-container":"cilium-agent"}
```

(`SUSPENDED` columns, all `False`, trimmed.) Thirty seconds after the
merge, `flux-instance` briefly reported "dependency 'flux-system/flux-operator'
revision is not up to date"; its retry two minutes later was not needed,
because the dependency became Ready first.

## Day-two tasks

- **Add an application.** For a chart:
  1. Create `kubernetes/apps/<namespace>/<app>/app/` with
     `ocirepository.yaml` (the chart URL and an exact `tag`, which Renovate
     follows), `helmrelease.yaml` (`chartRef` to it) and
     `kustomization.yaml` listing both. Put values in `values.yaml` with
     the same `configMapGenerator` and `kustomizeconfig.yaml` as Cilium,
     or inline under `spec.values` if they are few.
  2. Create `kubernetes/apps/<namespace>/<app>/ks.yaml`, copied from
     `cilium/ks.yaml` with the name and path changed. Add `dependsOn` if
     the application needs another one first.
  3. For a new namespace: `kubernetes/apps/<namespace>/kustomization.yaml`
     with a `namespace.yaml` and the `ks.yaml`, and the directory added to
     `kubernetes/apps/kustomization.yaml`.
  4. `kubectl kustomize kubernetes/apps/<namespace>/<app>/app` must render.
     Open a pull request; after the merge, `flux get kustomizations -A`
     shows the new revision within a minute or two.
- **Change a value or a chart version.** Edit the file, merge. Flux
  applies it; nothing is run by hand.
- **See what Flux is doing.** `flux get kustomizations -A`,
  `flux get helmreleases -A`, `flux events -A`. `flux reconcile
  kustomization flux-system --with-source` skips the wait for the next
  poll.
- **Upgrade Flux.** Renovate proposes two pull requests, the CLI in
  `mise.toml` and `distribution.version` in `fluxinstance.yaml`, labelled
  `upgrade-drill` for a minor or major. Merge them together. Upgrade the
  flux-operator chart first when both are pending.
- **Rebuild from nothing.** The rebuild in [Cluster](02-cluster.md) ends
  with `mise run bootstrap:secrets` and `mise run bootstrap:flux`, after
  which Flux takes over. This has not been run end to end.

## When it goes wrong

- **Every Cilium and flux-operator pod restarted when Flux took over.**
  The first `bootstrap:flux` adopted both releases in place (Helm revision
  2), but the pod templates changed in one label:
  `helm.sh/chart: cilium-1.20.4` became `cilium-1.20.4_712e1f65bf30`.
  helm-controller appends the first twelve characters of the OCI artifact
  digest to the chart version, and both charts put that version in their
  pod labels. Fix: the feature gate `DisableChartDigestTracking=true` in the
  FluxInstance (D33). Applying it rolled the pods once more, back to the
  plain label.
- **`helm upgrade` by hand fails with "conflict with helm-controller:
  .metadata.labels.helm.sh/chart".** This happened once while the fix was
  tested. The release belongs to Flux. The attempt left a `failed` revision
  in the Helm history, which the next Flux upgrade replaced. Change the
  files instead.
- **`mise exec` uses the lab cluster even with another `KUBECONFIG`
  exported.** `mise.toml` sets `KUBECONFIG` for every command run through
  mise. For a test cluster, call the tools directly, not through mise.

## Sources

- Flux Operator documentation (fluxoperator.dev):
  [installation](https://fluxoperator.dev/docs/guides/install/) (the Helm
  chart, namespace `flux-system`),
  [FluxInstance](https://fluxoperator.dev/docs/crd/fluxinstance/) (required
  fields, `version` as a range or an exact version, the name `flux`,
  `kustomize.patches`) and [sync](https://fluxoperator.dev/docs/instance/sync/)
  (the generated `flux-system` objects, the one-minute default, no secret
  for a public repository).
- Flux: the
  [Kustomization reference](https://fluxcd.io/flux/components/kustomize/kustomizations/)
  (`prune: disabled`, `retryInterval` defaulting to the interval) and the
  [HelmRelease reference](https://fluxcd.io/flux/components/helm/helmreleases/).
  helm-controller v1.7.1 source: the release name and storage namespace
  defaults, the upgrade of a release with no Flux history, and
  `mutateChartWithSourceRevision` with the `DisableChartDigestTracking`
  gate.
- [onedr0p/home-ops](https://github.com/onedr0p/home-ops) and
  [buroa/home-ops](https://github.com/buroa/home-ops): the
  `kubernetes/apps/<namespace>/<app>/` layout with `ks.yaml` and `app/`,
  flux-operator and the FluxInstance managed by Flux, the bootstrap that
  reads chart and values from the Flux files, and the same feature gate.
  Their alert components, the `flux-instance` chart and the controller
  tuning were not taken.
- Renovate [flux manager](https://docs.renovatebot.com/modules/manager/flux/):
  OCIRepository tags are detected; the FluxInstance version is not, hence
  the custom manager.

# 00 Repository

## What this adds

Every change to the repository travels the same way: a short branch, a pull
request that has to pass two checks, a squash merge into `main`, and later a
release that marks a verified phase. The documentation site is rebuilt from
`main`, and Renovate proposes dependency updates once a week.

## Before you start

- A clone of `github.com/msavdert/homelab` and [mise](https://mise.jdx.dev).
- For the GitHub settings: a token with administration rights on the
  repository. On the agent box that is `opgh` (the token comes from git's
  credential cache); elsewhere `gh` logged in as the owner.
- The Renovate GitHub app installed on the repository.

## Steps

### 1. Tools and the local check

`mise.toml` pins every command-line tool the lab uses (OpenTofu, talosctl,
kubectl, kubectl-cnpg, helm, flux, cilium-cli, uv, jq) plus what the
check needs (ruff, shellcheck, zensical). The same file is used locally and in CI, so a check that passes
on your machine passes there.

```sh
mise install
mise run check
```

`check` is everything that can be validated without a cluster. Today that is
the documentation build with `--strict` (a broken link or a page missing
from the build fails it) and `py_compile` plus `ruff check` on the tracked
Python. Phase 1 added `lint:tofu` (`tofu fmt -check` and `tofu validate`
on `infra/`, without credentials); `lint:shell` runs shellcheck on the
scripts. `lint:kubernetes` runs `kubectl kustomize` on every tracked
directory with a `kustomization.yaml` under `kubernetes/` and `talos/`
and names the directory that fails; a broken child also fails every
kustomization that includes it. Because a merge to `main` is a
deployment, this is the check that stops a manifest that does not
render. It reads only tracked files, so `git add` a new directory before
running it locally. The output below is from phase 0.

```
[lint:python] All checks passed!
[docs:build] Build started
[docs:build] No issues found
Finished in 1.70s
```

`mise run docs:serve` previews the site locally.

### 2. Workflows

Four files in `.github/workflows/`. Each starts with `permissions: {}` and
gives every job only what it needs; every action is pinned by full commit
SHA with the tag in a comment, so a moved tag cannot change what runs.

| Workflow | Job | Runs on | Does |
|---|---|---|---|
| `ci.yml` | `check` | pull requests, pushes to `main` | `mise run check` |
| `pr-title.yml` | `semantic-title` | pull requests | the title must be a Conventional Commit |
| `docs.yml` | `build`, `deploy` | changes to `docs/`, `mkdocs.yml`, `mise.toml` | builds the site; on `main` also deploys it to Pages |
| `release-please.yml` | `release-please` | pushes to `main` | keeps the release pull request up to date |

The title check matters because the pull request is squash-merged and its
title becomes the commit message on `main`; release-please reads those
messages to build the changelog.

### 3. Repository settings

These live on GitHub, not in files. They were set through the API:

```sh
# squash merge only, title of the pull request as the commit message,
# branches deleted after the merge
opgh api -X PATCH repos/msavdert/homelab \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY

# Pages built by a workflow, not from a branch
opgh api -X POST repos/msavdert/homelab/pages -f build_type=workflow

# the workflow token may open pull requests (release-please needs this)
opgh api -X PUT repos/msavdert/homelab/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```

Set Pages before the first merge that touches `docs.yml`: the `deploy` job
runs on that merge and fails if Pages is not enabled yet.

### 4. The ruleset on `main`

The ruleset is what makes the flow binding. It requires a pull request (no
approvals: there is one maintainer), the checks `check` and
`semantic-title`, linear history, and it blocks force pushes and deletion.
Nobody can bypass it.

```sh
opgh api -X POST repos/msavdert/homelab/rulesets --input - <<'EOF'
{"name":"main","target":"branch","enforcement":"active","bypass_actors":[],
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "rules":[
  {"type":"pull_request","parameters":{"required_approving_review_count":0,
   "dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,
   "require_last_push_approval":false,"required_review_thread_resolution":false,
   "allowed_merge_methods":["squash"]}},
  {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,
   "required_status_checks":[{"context":"check"},{"context":"semantic-title"}]}},
  {"type":"required_linear_history"},{"type":"non_fast_forward"},{"type":"deletion"}]}
EOF
```

The check names are the job names in the workflows. Renaming a job without
changing the ruleset leaves every pull request waiting for a check that
never comes.

### 5. A change, from branch to `main`

```sh
git switch -c docs/fix-typo
# edit, then
mise run check
git commit -am "docs: fix a typo in the host page"
git push -u origin docs/fix-typo
opgh pr create --title "docs: fix a typo in the host page" --body "..."
```

The title types are `feat`, `fix`, `docs`, `chore`, `ci`, `build`,
`refactor`, `perf`, `test` and `revert`. When `check` and `semantic-title`
are green, the pull request is squash-merged and its branch deleted. A merge
that touches `kubernetes/` changes the cluster, because Flux follows `main`
(from phase 3).

### 6. Releases

release-please (`release-please-config.json`, type `simple`) keeps one pull
request open, titled `chore(main): release X.Y.Z`. It collects the changelog
from every `feat`, `fix`, `perf`, `revert` and `docs` commit since the last
release; `feat` raises the minor version while the version is below 1.0.
The first release is `v0.1.0`.

A release marks a closed phase, not a deployment. Only the owner merges the
release pull request, when the architect reports that a phase's gate has
passed. Because release-please opens the pull request with the workflow
token, GitHub does not start its checks on its own: approve the waiting
runs in the Actions tab (or on the pull request), once after every update
of the pull request.

### 7. Renovate

`.renovaterc.json5` holds the configuration:

- runs before 06:00 on Monday (Europe/Istanbul), only for releases at least
  three days old;
- GitHub Actions updates come as one pull request (`ci`), mise tools as
  another (`dev tools`);
- minor and major updates of `talosctl`, `kubectl`, `flux2` and
  `cilium-cli` come alone, labelled `upgrade-drill`: they move together with
  the cluster component they control, as a drill the owner schedules;
- OpenTofu providers resolve from `registry.opentofu.org`;
- Talos versions are tracked from `factory.talos.dev` in YAML files under
  `talos/` (preset `home-operations/renovate-presets//apps/talosFactory.json5`);
- the runner image (`ubuntu-24.04`) is not updated by Renovate.

The Dependency Dashboard issue lists everything Renovate found and what is
waiting for the schedule.

## Check

Run on 2026-11-15 on `main`:

```
$ mise install && mise run check
exit 0

$ curl -sI https://msavdert.github.io/homelab/ | head -1
HTTP/2 200

$ opgh api repos/msavdert/homelab/rules/branches/main --jq '.[].type' | sort
deletion
non_fast_forward
pull_request
required_linear_history
required_status_checks

$ opgh api repos/msavdert/homelab/rulesets/27299377 --jq '{name,enforcement,bypass_actors}'
{"bypass_actors":[],"enforcement":"active","name":"main"}
```

A pull request titled `bad title` (#5, closed): `semantic-title` failed and
the merge state was `BLOCKED`.

The release pull request `chore(main): release 0.1.0` (#4) was opened by
release-please after the first merge. After the owner approved its runs in
the Actions tab, its required checks ran:

```
$ opgh pr checks 4
check           pass  13s
semantic-title  pass  3s
```

Dependency Dashboard (#6) lists the
workflows and `mise.toml` and no configuration error.

## Day-two tasks

- **Start of a session**: read the Dependency Dashboard and the open Renovate
  pull requests; merge routine ones, prepare upgrade drills (D23).
- **Add a tool**: add it to `[tools]` in `mise.toml` at the current release;
  Renovate picks it up.
- **Add a check**: add a task and list it under `tasks.check.depends`; CI
  runs it without a workflow change.
- **Rename a CI job**: change the ruleset's required checks in the same
  step, see step 4.

## When it goes wrong

- **Renovate wanted to move the runner to ubuntu 26.04.** The first run put
  `ubuntu 24.04 -> 26.04` on the dashboard. The runner is pinned on purpose;
  the `github-runners` datasource is now disabled (#7).
- **The onboarding pull request was behind `main`.** Renovate's onboarding
  branch was cut before the workflows existed. It was rebased onto `main`,
  its `renovate.json` replaced with `.renovaterc.json5`, and merged (#2).
- **The release pull request shows "action required".** Expected: see
  step 6.

## Sources

- obenhub (`/home/agent/work/obenhub`): the workflows, `release-please-config.json`,
  the pull request template and the Renovate schedule, grouping and release
  age were copied from there; its lint tools and lab tasks were left out.
- [Zensical, Publish your site](https://zensical.org/docs/publish-your-site/):
  the Pages artifact and deploy steps.
- Renovate documentation: the
  [mise](https://docs.renovatebot.com/modules/manager/mise/),
  [terraform](https://docs.renovatebot.com/modules/manager/terraform/)
  (the OpenTofu registry rule),
  [github-actions](https://docs.renovatebot.com/modules/manager/github-actions/)
  managers and the [configuration options](https://docs.renovatebot.com/configuration-options/)
  (cron form of `schedule`).
- [home-operations/renovate-presets](https://github.com/home-operations/renovate-presets),
  `apps/talosFactory.json5`: how Talos versions are found.
- GitHub REST: [rulesets](https://docs.github.com/en/rest/repos/rules),
  [repositories](https://docs.github.com/en/rest/repos/repos),
  [Pages](https://docs.github.com/en/rest/pages/pages).
- [release-please](https://github.com/googleapis/release-please): config
  schema and manifest releaser.

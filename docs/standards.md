# Standards

How files are laid out, named, written and committed. Short on purpose; if
a rule here is in the way of a gate, tell the owner.

## Documentation

The documentation is for a person who wants to understand or rebuild the
lab without an agent. It is plain Markdown in `docs/`, published with
Zensical.

Pages:

| Page | Content | Changes when |
|---|---|---|
| `index.md` | what the lab is, where to start | rarely |
| `architecture.md` | the parts and how they connect | the design changes |
| `decisions.md` | choices, alternatives, evidence | a decision is made |
| `roadmap.md` | phases, gates, state | a phase opens or closes |
| `host.md` | what exists on the Proxmox host | the host objects change |
| `guide/NN-name.md` | how one layer was built, step by step | its phase closes |
| `standards.md`, `handoff.md` | working rules, session start | the rules change |

### Guide pages

A guide page is written when its phase closes, from the commands that were
actually run. A reader with the prerequisites can follow it top to bottom
and end up with the same result. Every guide has these parts, in this
order:

1. **What this adds**: two or three sentences, including what it is for.
2. **Before you start**: tools, access and the earlier guides it depends
   on.
3. **Steps**: numbered. Each step has the command or file, what it does and
   why it is needed, and what to expect: real output, trimmed to the
   lines that matter.
4. **Check**: the gate commands and their real output, with the date.
5. **Day-two tasks**: the things done repeatedly with this layer (add an
   application, add a secret, upgrade a node).
6. **When it goes wrong**: only problems that actually occurred while
   building, with the symptom and the fix.
7. **Sources**: the documentation pages and repositories the work was based
   on, and what was taken from each.

The architect writes guide pages. They are not delegated to a smaller
model. A new guide page is added to the `nav` list in `mkdocs.yml` in the
same pull request; a page that is not in `nav` is not linked on the site.

### Writing

- Write for a reader who is capable but was not there. Define a term the
  first time it appears. Say why before how.
- Use full sentences in explanations. Use lists for steps and for parallel
  items, tables for facts with attributes, code blocks for anything typed
  or printed.
- Be specific: the actual address, version, file path and output. If a
  sentence would be true of any cluster, it does not belong here.
- State what was verified and when. Mark what was not tested as not
  tested.
- No filler: no introductions that restate the title, no summaries that
  repeat the page, no praise of tools, no "simply", "just", "seamless",
  "robust", "powerful", "best practice" without a named source.
- No emoji. No decorative formatting. Headings are sentence case.
- Never paste a secret, a token or a private key, including into output
  samples. Replace with `<redacted>`.
- Output samples are real. Do not invent or tidy command output; trim it
  and mark the cut with `...`.

## Layout and naming

- Directories as in [Architecture](architecture.md), "Repository layout". A
  directory is created by the phase that fills it.
- Kubernetes: `kubernetes/apps/<namespace>/<app>/` with `ks.yaml` (the Flux
  Kustomization) and `app/` (`kustomization.yaml`, `ocirepository.yaml`,
  `helmrelease.yaml`, chart values in `values.yaml`); see D32.
- Names are lowercase with hyphens. Nodes are `k8s-1` to `k8s-3`.
  1Password items are named in [Architecture](architecture.md), "Secrets".
- YAML: two spaces, one document per concern, comments only for what the
  file cannot say itself.
- Shell: `bash`, `set -euo pipefail`, no secret in arguments or files. A
  script that talks to an API and has to check every response is written in
  Python with the standard library only, as `infra/host/prepare.py` is.
- Repeated commands are mise tasks, named `<area>:<verb>` (`infra:plan`,
  `talos:apply`, `docs:build`). A task that needs credentials wraps its
  command in `op run` or `op inject`.

## Versions

Pinned where they are used (`mise.toml`, provider blocks, chart references,
image tags). Renovate proposes updates. When pinning something new, read
the current version from its release page.

## Commits

The flow is described in `AGENTS.md`, "Changes, releases and updates".

- One logical change per pull request. The title is a Conventional Commit
  in the imperative: `feat(infra): add node definitions`. The description
  says what was verified and how, with output.
- Never merge a pull request whose checks fail. For work that Flux applies,
  the gate can only be proven after the merge; a phase is not closed, and
  no release is proposed, until its gate passes on `main`. If a merge breaks
  the cluster, the fix or the revert is the next pull request.
- Before a merge, run the audit the change calls for. On the owner's
  workstation the `audit` skill defines the tiers and runs the external
  half through `agy`; without that skill, the `auditor` agent is the
  minimum. The tiers: none for prose that no agent executes;
  the `auditor` agent for configuration, code and rule files; the `auditor`
  plus one external model for anything that writes to a live system or
  handles credentials. For anything that deletes data or changes a live
  system outside Flux, the owner also sees the plan first.
- A phase is usually several pull requests. The last one updates the
  roadmap state, adds the guide page and rewrites `docs/handoff.md`.

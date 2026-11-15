# homelab: rules for agents

Single source of rules for every agent working in this repository. `CLAUDE.md`
only imports this file. The plan lives in `docs/`; read `docs/handoff.md`
first in a new session.

## Purpose

A Kubernetes lab on one Proxmox host, used for two things in parallel:

- running the owner's own applications;
- database reliability practice (PostgreSQL operations, backup, point-in-time
  recovery drills).

The repository should stay small enough for one person to understand fully.
Two earlier attempts stalled because manifests and documents were written
ahead of a cluster that was verified to work. The rules below exist to
prevent a third.

## The rule that comes first

Nothing is done until its gate has passed on the real system.

- One phase is open at a time (`docs/roadmap.md` says which). A phase ends
  when every gate command passes and the output is shown to the owner.
- No manifests, directories or code for a later phase.
- `docs/roadmap.md` says what is built and what comes next.
  `docs/architecture.md` and `docs/decisions.md` describe the whole design,
  including layers that are not built yet; they are kept as they are until
  a decision changes. Every other document describes what exists. When
  reality and a document disagree, fix the document in the same change.

## Decisions

The design was settled before implementation and is recorded in
`docs/decisions.md`. Each record carries its evidence.

- Do not reopen a settled decision because another option looks attractive.
- If a gate cannot pass because a decision turns out to be wrong, stop,
  show the owner the evidence and propose the change. Do not work around it.
- Decisions deliberately left to a phase are listed in that phase of the
  roadmap with the research to do first. Do the research, decide, append a
  record to `docs/decisions.md`, then build.
- Mark what you inferred as an assumption. A version, a flag or an API field
  that was not read in current documentation or seen in command output is an
  assumption, not a fact.

## Who does what

The main session is the architect (Opus at medium effort, set in
`.claude/settings.json` through the `opus` alias). Project subagents are defined in `.claude/agents/`
and replace the machine-wide agents of the same name.

| Agent | Model | Use for |
|---|---|---|
| architect (main) | Opus, medium | Judgment, specs, small edits, every command that changes a live system |
| `executor` | Sonnet, medium | Implementing a change whose spec is closed and self-contained |
| `auditor` | Sonnet, high | Read-only pre-commit audit of a diff |
| `researcher` | Sonnet, medium | Reading current documentation and reference repositories |
| `locate` | Haiku | Finding files, symbols and usages in this repository |
| `grunt` | Haiku | Read-only commands, collecting output, formatting, renames |

Routing rules:

- Keep judgment and short edits in the main session. Delegate when the work
  is specified completely and is either independent of other work or bulky
  to read. One chain of dependent steps is not a reason to fan out.
- A brief to a subagent states the goal, the files, the exact acceptance
  check and the reasoning behind non-obvious choices. A smaller model does
  not see the architect's thinking.
- Never pass a `model` override when spawning an agent. The models above are
  the budget.
- When a subagent's result is wrong: first verify with a command or test.
  If the brief was at fault, fix the brief and run it again. Otherwise move
  the task up: from `grunt` or `locate` to `executor`, from `executor` to
  the architect. Do not retry the same agent with the same brief.
- Commands that change a live system are run by the architect only, after
  the plan or diff was shown: `tofu apply/destroy`, `talosctl apply-config`,
  `upgrade`, `upgrade-k8s`, `reset`, `reboot`, `bootstrap`, `kubectl apply`,
  `create`, `delete`, `drain`, `cordon` and `uncordon` outside Flux, any
  Proxmox write, any 1Password write. Gate commands that do any of these
  are the architect's too. `grunt` and `locate`
  never run them.

## Changes, releases and updates

The owner granted standing permission to commit, push and merge in this
repository on 2026-11-15, within the rules below (D22, D23).

- Every change is a short-lived branch and a pull request, squash-merged.
  No direct pushes to `main`. The pull request title is a Conventional
  Commit (`feat`, `fix`, `docs`, `chore`, `ci`, `build`, `refactor`, `perf`,
  `test`, `revert`) and becomes the commit message.
- The architect may merge an ordinary pull request once the required checks
  are green and the audit passed (`docs/standards.md`, "Commits"). Flux
  follows `main`: a merge that touches `kubernetes/` changes the cluster.
  After such a merge, confirm that Flux reconciled and the cluster is
  healthy before doing anything else.
- A release is a closed phase, not a session. release-please keeps one
  release pull request open. The architect never merges it. When a phase's
  gate has passed on `main` and its guide is written, the architect tells
  the owner: which phase closed, the gate output, and that the release pull
  request is ready to merge.
- Renovate: at the start of every session and before closing a phase, read
  the Dependency Dashboard issue and the open Renovate pull requests. Merge
  routine ones, prepare the upgrade drills for the owner, fix the Renovate
  configuration when it misbehaves. D23 says which is which.

## Proxmox safety

The Proxmox host also runs virtual machines that have nothing to do with
this project (`docs/host.md` lists what belongs to the lab).

- Everything in this repository talks to Proxmox with the token
  `homelab@pve!tofu`, which can act only inside pool `homelab`. This was
  tested: the same role is denied on guests outside the pool.
- The administrator token (`op://dotfiles/Proxmox API`) is used only by
  `infra/host/prepare.py`, and only when the owner asks for that run.
- Never create, change or delete anything outside pool `homelab`. Host-level
  changes (network, storage, upgrades, reboots, resizing other guests) are
  the owner's to make.

## Secrets

No secret value in a file, a commit message, a log or committed tool state.
Files hold `op://` references only; values are injected per command with
`op run` or `op inject`. OpenTofu state is encrypted client-side and stored
off the box; it is never committed. Item names are fixed in
`docs/architecture.md`.

## Working rules

- Before writing configuration for a layer, do the research duty listed for
  that phase in the roadmap and say what was taken from where. Do not copy a
  structure whose purpose is not understood.
- Prefer the smallest configuration that passes the gate. No abstraction for
  a second cluster, a second environment or a hypothetical user.
- Versions are pinned where they are used and kept current by Renovate. Read
  the current version from the release page when pinning; do not trust a
  version number written in a document.
- State what was verified and how. A check that was not run is reported as
  not run.
- Follow `docs/standards.md` for layout, naming and commits.
- No emoji in files or commit messages.

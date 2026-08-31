# Adopting `gh stack` for the stacked-PR workflow

**Date:** 2026-08-31
**Status:** Approved, not yet implemented

## Problem

`docs/stacked-pr-workflow.md` and eight `stack-*` slash commands implement a
stacked-PR workflow by hand: `refactor/stepN-<slug>` branch naming, manual
`gh pr create --base <previous step>` chaining, manual `gh pr edit --base` after
each merge, and a hand-rolled cascading rebase.

GitHub shipped native stacked pull requests in public preview on 2026-07-30,
exposed through the `github/gh-stack` CLI extension (v0.1.0). It automates
branch creation, cascading rebase, PR base assignment, retargeting after merge,
and navigation, and links PRs into a first-class **Stack** object on github.com.

Most of the hand-rolled machinery in these commands is now redundant. The parts
that are *not* redundant are the ones `gh stack` does not address: coordinating
a single logical change across the several repos in `~/repos`.

## Goals

- Delegate all per-repo stack mechanics to `gh stack`.
- Preserve the multi-repo orchestration that `gh stack` has no concept of.
- Keep the existing command names, so muscle memory survives.
- Add commands for the capabilities `gh stack` newly makes available.

## Non-goals

- Automatic migration of in-flight `refactor/stepN-*` branches. Migration is
  deliberate and per-repo, using `gh stack init <branches...>` to adopt.
- Cross-repo atomic merge. GitHub's all-or-nothing guarantee is per-repo; this
  design reports partial success rather than pretending otherwise.
- Replacing `/stack-port`. `gh stack` has no equivalent operation.

## Decisions

These were settled during brainstorming and are load-bearing for everything below.

| Decision | Choice | Consequence |
|---|---|---|
| Multi-repo model | Thin orchestration layer over `gh stack` | Commands loop repos and delegate; they never reimplement stack mechanics |
| Branch naming | Adopt `gh stack` auto-naming (`08-31-add_login`) | Branch names can no longer correlate a step across repos |
| Cross-repo correlation | Workspace manifest file | New local state; the only thing tying repos together |
| Code structure | Pure prompt orchestration, no helper scripts | Repo stays markdown-only; drift is mitigated by a single canonical schema section |
| New commands | `/stack-start`, `/stack-merge`, `/stack-modify` | Three additions to the existing eight |

The naming and correlation decisions are coupled. Auto-naming was chosen for
ergonomics (`gh stack add -Am "..."` does staging, commit, branch creation, and
naming in one step), and it is precisely what makes the manifest necessary.

## Prerequisites

1. ~~**Upgrade `gh` to >= 2.90.0.**~~ Done — gh 2.98.0 installed 2026-08-31.
2. ~~**Install the extension:** `gh extension install github/gh-stack`.~~ Done —
   gh-stack v0.1.0.
3. **Confirm the preview is enabled for `contoroinc`.** Still outstanding. Stacked PRs are a public
   preview; `gh stack submit` will fail at the org level if not. Test on one
   throwaway stack before migrating in-flight work.

Every rewritten command MUST begin with a guard: if `gh stack` is unavailable,
report it and stop. Commands MUST NOT fall back to the old hand-rolled git
paths, because a silent fallback would produce branches the manifest does not
know about.

## The manifest

### Location

`<workspace-root>/.stack-manifest.json`, written only in multi-repo mode. In
single-repo mode `gh stack`'s own `.git/gh-stack` metadata is sufficient and no
manifest is created.

The workspace root (`~/repos`) is a plain directory, not a git repository, so
no gitignore entry is needed.

### Schema

```json
{
  "version": 1,
  "name": "gripper-refactor",
  "plan": "unloading_robot_ws/docs/superpowers/plans/2026-08-31-gripper-refactor.md",
  "trunk": { "unloading_robot_ws": "develop", "contoro_utils": "main" },
  "steps": [
    { "n": 1, "title": "Split gripper files", "merged": false,
      "branches": { "unloading_robot_ws": "08-31-split_gripper_files" } },
    { "n": 2, "title": "Extract gripper class", "merged": false,
      "branches": { "unloading_robot_ws": "08-31-gripper_class",
                    "contoro_utils":      "08-31-gripper_types" } }
  ]
}
```

Field notes:

- `trunk` is recorded per repo because the repos disagree (`develop` vs `main`).
- `steps[].branches` lists **only** the repos participating in that step. This
  is what expresses a step touching two of five repos — something positional
  alignment across `gh stack view --json` could not represent.
- `steps[].merged` is set by `/stack-merge` and by the sync path.
- Repo keys are directory names relative to the workspace root.
- PR numbers are deliberately **not** stored. They are derived from
  `gh stack view --json` on demand, so the manifest cannot go stale as PRs are
  opened, retargeted, merged, or closed.

### Lifecycle

| Command | Manifest interaction |
|---|---|
| `/stack-start` | Creates the file; populates `name`, `plan`, `trunk`; `steps` empty |
| `/stack-commit` | Appends a step, or adds a repo/branch to the current step |
| `/stack-status`, `/stack-checkout`, `/stack-create-summary`, `/stack-create-diagram` | Read only |
| `/stack-merge` | Marks steps merged; prunes fully merged steps |
| `/stack-rebase` | Prunes entries for branches deleted by `gh stack sync --prune` |
| `/stack-modify` | Reconciles renamed and dropped branches after the TUI exits |

The manifest is disposable local state. If it is lost or absent,
`/stack-status` MUST fall back to a positional reconstruction from
`gh stack view --json` and present it to the user for confirmation rather than
writing it silently.

### Canonical helpers

Because this design uses pure prompt orchestration with no shared script, the
manifest schema above and the `jq` read/write snippets are defined **once** in
`docs/stacked-pr-workflow.md`. Every command file references that section
rather than restating the schema. This is the sole mitigation against the eight
prompts drifting apart; keeping it is a requirement, not a style preference.

## Commands

### New

**`/stack-start <plan-or-name>`**
Reads the plan if one is given, asks which repos participate, and runs
`gh stack init --base <trunk>` per repo with trunk detected from that repo's
default branch. Writes the manifest skeleton.

**`/stack-merge [stepN]`**
Runs `gh stack merge` per repo, merging up to the PR for that step. The
manifest stores branches, not PR numbers, so the target PR is resolved by
looking the step's branch up in `gh stack view --json` — PR state changes on
every merge and must never be cached in the manifest.
Previews what will merge and requires confirmation before acting — this is the
only destructive command in the set. GitHub's all-or-nothing guarantee applies
per repo, so partial success across the workspace is possible and MUST be
reported explicitly per repo.

**`/stack-modify [repo]`**
Resolves the repo, checks the preconditions `gh stack modify` documents (clean
working tree, no rebase in progress, linear history, no PR queued for merge),
hands off to the TUI, and on return reconciles renamed and dropped branches
into the manifest. That reconciliation is the only reason a wrapper exists.

### Rewritten

**`/stack-commit [repo]`**
Retains the valuable part: reading the plan, classifying which step the
uncommitted changes belong to, and deciding whether they extend the current step
or begin a new one. The mechanics change:

- New step: `gh stack add -Am "<message>"` in each participating repo, then read
  the auto-generated branch name back from `gh stack view --json` and record it
  in the manifest under that step.
- Existing step: a plain `git commit` on the checked-out layer. `gh stack add`
  MUST NOT be used here; it would create a new layer.

**`/stack-create-pr [step]`**
`gh stack submit --auto --open` per repo.

**Important semantic limit, confirmed against the CLI:** `gh stack submit` has
no branch- or step-targeting flag. It pushes *every* branch in that repo's stack
and creates or updates PRs for all of them. A `stepN` argument therefore selects
**which repos** to run `submit` in — the repos participating in that step — and
submitting a repo necessarily submits that repo's entire local stack. Per-step
submission within a repo is not possible non-interactively. `--auto` skips the interactive editor;
`--open` is required because `--auto` alone creates drafts. Afterwards, resolves
each branch's PR number from `gh stack view --json` and writes a cross-repo
reference block into each PR body —
GitHub's Stack object is per-repo and cannot express a stack spanning repos.
The old `retarget` mode is deleted; `gh stack sync` retargets after merges.

**`/stack-rebase [repo]`**
`gh stack sync` per repo (fetch, reconcile remote, fast-forward trunk, cascade
rebase, push, sync PR state, prune). Runs non-interactively and MUST surface
both documented non-success paths per repo rather than swallowing them:

- A rebase conflict pauses the operation; the user resolves and runs
  `gh stack rebase --continue`.
- A diverged local/remote stack aborts the sync without pushing.

**`/stack-status [repo]`**
Aggregates `gh stack view --json` across repos, joined against the manifest so
rows group by **logical step** rather than by repo. Per layer shows: repos
touched, branch, PR number and state, and working-tree cleanliness.

**`/stack-checkout <stepN|top|bottom|up|down>`**
Per repo, checks out the branch the manifest records for the named step. Repos
not participating in that step stay where they are and are reported as skipped.
Bare navigation words pass through to `gh stack up/down/top/bottom`.

### Re-sourced

**`/stack-create-summary`, `/stack-create-diagram`**
Logic unchanged. Input changes from globbing `*/step*` branches to reading the
manifest plus `gh stack view --json`. The diagram gains real PR numbers and
merge state as a result.

### Unchanged

**`/stack-port`**
Behavior unchanged; `gh stack` has no equivalent for replaying a stack onto a
different base. It is currently installed in `~/.claude/commands/` but missing
from this repository and MUST be committed as part of this work.

## Documentation

`docs/stacked-pr-workflow.md` is rewritten around `gh stack`. It gains:

- The prerequisites section above.
- The canonical manifest schema and `jq` snippets.
- A migration section for adopting in-flight `refactor/stepN-*` branches.
- A corrected command table. The existing table names four commands that do not
  exist (`/commit-stack`, `/create-pr-stack`, `/rebase-stack`,
  `/checkout-latest-step`); the actual names are `/stack-commit`,
  `/stack-create-pr`, `/stack-rebase`, `/stack-checkout`.

**`install.sh` must be extended.** (Corrected 2026-08-31 — the original claim
here, "`install.sh` needs no change; it already copies `commands/*.md`", was true
of the old hand-rolled model and is false under this one.) The eleven `stack-*`
commands cite `stacked-pr-workflow.md` and `gh-stack-json-reference.md` ~58 times
for canonical blocks they must not retype. At runtime their cwd is the user's
workspace, not this repository, so a repo-relative `docs/...` path does not
resolve and an executor told to "use the jq from
`docs/stacked-pr-workflow.md#manifest-writes`" would improvise — writing
divergent JSON into `.stack-manifest.json`, which is exactly the
manifest-corruption failure the no-shared-script decision was betting against.
So `install.sh` also copies both docs into `~/.claude/docs/`, and every command
cites them by that absolute path (the same convention the commands already use
for `~/.claude/plans/`), anchors unchanged.

## Risks

**~~`gh stack view --json` field names are undocumented.~~ RESOLVED 2026-08-31.**
Prerequisites are installed (gh 2.98.0, gh-stack v0.1.0) and the real schema is
captured in `docs/gh-stack-json-reference.md`. Two measured details correct
assumptions made above:

- `branches[].base` is a **commit SHA, not a branch name**. Parent-branch
  relationships must be derived from array order (bottom-first), not from `base`.
- `branches[].pr` is **omitted entirely** when no PR exists, so commands must
  tolerate its absence rather than expecting a null.

The `pr` object's internal keys (`number`, `state`, `url`) are inferred from the
extension's struct tags and still need confirming against a stack with live PRs.

**Public preview.** The feature may change, and org-level enablement is not
guaranteed. Verify on a throwaway stack first.

**Manifest drift.** With no shared script, eight prompts each manipulate the
same JSON. The single canonical schema section is the mitigation. If drift
appears in practice, the fallback is to introduce `scripts/stack-lib.sh` and
update `install.sh` to copy it — a change this design deliberately deferred but
did not preclude.

**Loss of name-based correlation.** Auto-naming means a branch name no longer
identifies its step. Anything outside these commands that greps for `*/step*`
will stop working.

## Verification

1. Install prerequisites; capture real `gh stack view --json` output.
2. On a throwaway stack in one repo: `init`, `add -Am`, `submit`, `sync`, `view`.
3. `gh stack init` works in a repo with no remote, so local fixture repos are
   sufficient for everything except `submit` and `merge`.
4. On a throwaway stack across two repos: full cycle through `/stack-start`,
   `/stack-commit`, `/stack-create-pr`, `/stack-status`, `/stack-checkout`,
   `/stack-rebase`, `/stack-merge`, confirming manifest contents after each.
5. Confirm a step touching only one of two repos reports the other as skipped.
6. Confirm the guard fires when `gh stack` is absent.
7. Delete the manifest and confirm `/stack-status` reconstructs and asks rather
   than writing silently.

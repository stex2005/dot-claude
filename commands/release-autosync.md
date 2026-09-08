---
description: Merge a release-candidate back into develop across the unloader codebase — dispatches merge-into-branch.yaml per repo, verifies by content, and never deletes the RC branch.
allowed-tools: Bash(gh workflow run:*), Bash(gh run list:*), Bash(gh run view:*), Bash(gh api:*), Bash(gh pr list:*), Bash(gh repo view:*), Bash(gh auth status), Bash(git show:*), Bash(git ls-remote:*), Bash(git fetch:*), Bash(git log:*), Bash(duckctl sw:*), Bash(pwd), Bash(ls:*), Bash(cat:*), Bash(grep:*), Bash(test:*), Bash(echo:*), Bash(for *), Bash(sleep:*), Read, Glob
argument-hint: "[version] [repos...] [--check-only]"
---

## Context

- Current directory: !`pwd`
- Repos dir env: !`printenv CONTORO_REPOS_DIR || echo "<unset>"`
- Current software version: !`duckctl sw version 2>/dev/null || echo "<duckctl unavailable>"`
- gh on PATH: !`command -v gh >/dev/null 2>&1 && gh auth status 2>&1 | head -2 || echo "<gh missing>"`
- Manifest RC configs: !`git -C ~/repos/.unloader_repos branch -r 2>/dev/null | grep -E 'origin/v[0-9].*rc$' | tail -5 || echo "<manifest repo not found under ~/repos — set CONTORO_REPOS_DIR if it lives elsewhere>"`
- Arguments: $ARGUMENTS — `[version]` (e.g. `v3.2.0`), optional `[repos...]` to narrow the sweep, `--check-only` to preview without merging

## What this does

Carry RC stabilization work **back onto `develop`**, repo by repo, by dispatching the existing
`merge-into-branch.yaml` GitHub Action with `target_branch=develop`.

**The gap this fills:** `autosync-main-to-develop.yaml` fires only on push to `main`. Fixes that
land directly on `release-candidate/vX.Y.Z` during stabilization therefore never reach `develop`
until the release itself merges — every feature branch cut in the meantime is missing them, and
the same fix gets re-applied by hand. This command closes that window while the RC is still open.

**Direction matters.** `/release-check` reports `develop` **ahead of** the RC (post-cut work that
will *not* ship). This command handles the mirror case: the RC **ahead of** `develop` (shipped
fixes that `develop` does not yet have). They are different problems; this one fixes only the
second.

**Execution model:** survey read-only, confirm once, then merge for real. `--check-only` runs the
sweep with `check_only=true` and writes nothing. The command is **re-runnable** — run it after
every batch of RC fixes.

**This command never touches `main`, tags, or the manifest.** It is independent of
`/release-dispatch` and can run before, between, or after `/release-check`.

## Workspace detection

1. Repos root: `$CONTORO_REPOS_DIR` if set, else `~/repos`. Must contain `.unloader_repos`.
2. `gh` must be on `PATH` and authenticated — **stop** otherwise.
3. `duckctl` is optional here (used only to suggest a version when none is given).

## Step 0 — Resolve version and repo set

1. Normalize `[version]` to `vX.Y.Z`. If absent, infer from the `vX.Y.Zrc` config branches; one
   candidate → confirm, several or none → **ask**. Never guess.
2. Enumerate repos from the manifest, **never hardcoded** (the list grows between releases):
   ```bash
   git -C <repos-root>/.unloader_repos show origin/<version>rc:cpc.repos
   ```
3. If `repos...` were given, resolve each against that list (exact match, then substring) and
   narrow the sweep to them; error on any that don't resolve.

## Step 1 — Survey every repo (read-only)

For each repo in scope, gather:

1. **RC branch exists** — `gh api repos/contoroinc/<repo>/branches/release-candidate/<version>`.
   Absent → the repo did not participate in this RC; skip it and say so.
2. **What the RC would bring to `develop`** — judge by **content, not commit count**:
   ```bash
   gh api "repos/contoroinc/<repo>/compare/develop...release-candidate/<version>" \
     --jq '{status, ahead_by, files: (.files|length)}'
   ```
   `files == 0` → `develop` already has everything; **skip the repo, do not dispatch**. A nonzero
   `ahead_by` with zero changed files is a content-free merge commit — do not chase it.
3. **Commit subjects that would land** — for every repo with `files > 0`:
   ```bash
   gh api "repos/contoroinc/<repo>/compare/develop...release-candidate/<version>" \
     --jq '.commits[].commit.message' | head -1
   ```
   The user needs to recognize the work, not a count.
4. **Open PRs into `develop`** — `gh pr list --repo contoroinc/<repo> --base develop --state open`.
   Not a blocker; report the count so a surprise conflict is expected rather than mysterious.
5. **`merge-into-branch.yaml` on the repo's *default* branch** — `workflow_dispatch` is only
   offered from the default branch, so otherwise the dispatch silently never runs. Missing →
   **blocker** for that repo.
6. **`PRIVATE_DEPLOY_KEY` present** — `gh api repos/contoroinc/<repo>/actions/secrets --jq
   '.secrets[].name'`. Without it the shared workflow dies at **`Setup up SSH agent`**. Missing →
   **blocker** for that repo.

Print the survey as a table:

```
## RC → develop sync: release-candidate/<version>

| Repo | RC | vs develop | commits | open PRs → develop | merge-wf@default | DEPLOY_KEY | action |
|------|----|-----------|---------|--------------------|------------------|------------|--------|
| task_executor | yes | 6 files | 4 | 0 | yes (develop) | yes | merge |
| unloading_robot_hal | yes | 0 files | 0 | 1 | yes (develop) | yes | skip (no-op) |
| operator_ui | yes | 3 files | 2 | 0 | no (develop) | yes | BLOCKED |
```

**Preflight the whole fleet before dispatching any repo.** If any in-scope repo hits a blocker,
stop and report all of them — a mid-sweep failure leaves `develop` half-synced across repos.

## Step 2 — Confirm

Show the participating list (repos with `files > 0` only) and, indented under each, the commit
subjects that will land on `develop`. Then ask for confirmation **once**.

- `--check-only` → dispatch the sweep with `check_only=true`, report whether each merge would be
  clean, and **stop**. Nothing else in this command runs.
- No repos with `files > 0` → report "`develop` is already up to date with the RC in every repo"
  and stop. Do not dispatch a no-op sweep.

## Step 3 — Dispatch the merge

Dispatch **from the RC ref** so `source_branch` defaults correctly, one repo at a time:

```bash
gh workflow run merge-into-branch.yaml --repo contoroinc/<repo> \
  --ref release-candidate/<version> \
  -f target_branch=develop \
  -f check_only=false \
  -f delete_source_branch=false
```

`delete_source_branch` is **`false`, always** — see Rules.

Poll each repo's latest run to completion (20s interval), then **verify independently**. A green
run is never proof:

```bash
gh api "repos/contoroinc/<repo>/compare/develop...release-candidate/<version>" --jq '.files|length'
```

- Expect `0`. Anything else means the merge did not land despite a green run — report it as a
  failure, not a success.
- `ahead_by` will still read `1` after a successful merge — the content-free merge commit. Ignore
  it; `files == 0` is the signal.

## Step 4 — Report

```
## Synced RC → develop: release-candidate/<version>

| Repo | Result | develop...RC after | Run |
|------|--------|--------------------|-----|
| task_executor | merged | 0 files | <run url> |
| unloading_robot_hal | skipped (no-op) | 0 files | — |
| perception | CONFLICT — draft PR #214 | 3 files | <run url> |
```

State plainly what remains. Do not run it.

## Handling conflicts

The merge workflow does not simply fail. It pushes a sync branch
`<safe-src>-<sha>/merge-into-develop` and opens a **draft** PR into `develop`.

- **Do not squash-merge that PR in the UI** — it rewrites commits and inflates later merges.
- Resolve on the sync branch (`git merge origin/develop`, fix, push), then re-run
  `merge-into-branch.yaml` **from the sync branch** with target `develop`.
- The workflow refuses to re-run while an open conflict PR exists for that source/target pair —
  so a repo left in conflict blocks its own next sync. Report it prominently.
- **Never auto-resolve conflicts.** Stop and report.

## Rules

- **NEVER delete the release-candidate branch.** `delete_source_branch` is hardcoded `false` and
  there is no flag to change it. The RC branch is still needed by `/release-check`,
  `/release-dispatch` (merge to `main`, then tags), and the `vX.Y.Zrc` manifest config, which
  pins every repo to it. Deleting it after a develop sync breaks the release. RC cleanup is a
  post-release step and belongs to no command in this family.
- **Merging RC → `develop` is not merging RC → `main`.** This command never touches `main`, never
  tags, and never writes the manifest. It does not advance the release; `/release-dispatch` does.
- **Skip no-ops, don't dispatch them.** A repo whose `compare/develop...RC` shows zero changed
  files needs nothing; dispatching anyway adds an empty merge commit and noise to the release
  notes.
- **Judge by content, never by commit count.** `ahead_by` counts merge commits that carry no
  files. Use `.files|length`.
- **Preflight the whole fleet before dispatching any repo.** All-or-nothing on blockers.
- **`merge-into-main.yaml` is DEPRECATED.** Consolidated into `merge-into-branch.yaml`. The old
  file still sits on `main` in several repos but not on `develop`/RC. Only ever dispatch
  `merge-into-branch.yaml`.
- **Dispatch from the RC ref**, never from `develop` or `main`.
- **A green run is never proof.** Verify every repo with `compare/develop...RC` afterwards.
- **Pushes to `develop` and `release-candidate/*` run no CI** (per-repo CI is `pull_request`-only),
  so a clean sweep says nothing about test status. Never present it as a quality signal.
- **Re-runnable by design.** Run it after each batch of RC fixes; there is no state to resume.
- Do NOT include `Co-Authored-By` lines in any commit this command makes.

## The release command family

Run in this order; each assumes the previous one succeeded. `/release-autosync` is the exception —
it is re-runnable and optional, any time the RC is open.

| Command | Does |
|---------|------|
| `/release-cut` | Cut `release-candidate/vX.Y.Z` branches + the `vX.Y.Zrc` sw config |
| `/release-autosync` | Merge the RC back into `develop` (re-runnable; never deletes the RC) |
| `/release-check` | Read-only readiness audit of the RC — BLOCKERS / WARNINGS / READY |
| `/release-dispatch` | Merge → tag + GitHub Release → `duckctl sw save` → verify the build |
| `/release-notes` | The whole-release Confluence page |
| `/release-blob` | Per-author feature blobs, for standup/Jira |

**Two names, always distinct:** the product-repo git **branch** is `release-candidate/vX.Y.Z`
(identical in every repo — cross-repo CI triggers on it, never rename it); the `duckctl sw`
config is `vX.Y.Zrc` for the RC and `vX.Y.Z` for the release.

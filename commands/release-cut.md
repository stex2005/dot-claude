---
description: Cut a release-candidate across the unloader codebase — release-candidate/vX.Y.Z branches in product repos plus a matching duckctl sw config in .unloader_repos.
allowed-tools: Bash(git *), Bash(duckctl *), Bash(cd *), Bash(ls *), Bash(for *), Bash(grep *), Bash(cat *), Bash(find *), Bash(pwd *), Bash(test *), Read, Glob
argument-hint: "[version] [repos...]"
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Repos dir env: !`printenv CONTORO_REPOS_DIR || echo "<unset>"`
- Arguments: $ARGUMENTS — optional `[version]` (e.g. `v3.1.4`) and/or `[repos...]` (repo names to scope a patch)

## What this does

Cut a release-candidate in **two layers, in one command**. **Two distinct names are in play
— keep them separate:**

- **Product-repo branch name:** `release-candidate/vX.Y.Z` (the git branch). Fixed — cross-repo
  CI (`pull_request` on `release-candidate/*`) matches on this prefix, so it must be identical
  in every repo and must NOT be renamed.
- **Software-version (sw config) name:** `vX.Y.Zrc` (e.g. `v3.2.0rc`). This is the `duckctl sw`
  config/branch name in `.unloader_repos` — what `duckctl sw save|load|version` use. It is NOT
  `release-candidate/vX.Y.Z`.

1. **Product repos** (`contoro_utils`, `unloading_robot/src/*`, `unloading_robot_ws`) — create
   and push a `release-candidate/vX.Y.Z` branch from `origin/develop`.
2. **Manifest repo** (`<repos-root>/.unloader_repos`) — write a matching software-version
   config named `vX.Y.Zrc` via `duckctl sw save vX.Y.Zrc --branches`, pinning participating
   repos to their new `release-candidate/vX.Y.Z` branch and carrying every other repo over on
   its existing pinned ref.

**The RC number is uniform across all participating repos, never a per-repo tag** — the branch
`release-candidate/vX.Y.Z` is identical everywhere so cross-repo CI fires, and the single sw
config `vX.Y.Zrc` points at it.

## Workspace detection

This command operates on the **repos root**, not a single git repo.

1. Resolve the repos root: `$CONTORO_REPOS_DIR` if set, else `~/repos`.
2. It must contain `.unloader_repos` (the manifest repo). If not found, **stop** and ask the
   user for the repos root.
3. `duckctl` must be on `PATH` (the manifest write depends on it). If missing, **stop**.

## Steps

### Step 0 — Discovery (read-only, mutate nothing)

1. `duckctl sw version` → current software version (e.g. `v3.1.3`).
2. `duckctl sw ls` → authoritative repo list and each repo's currently-pinned ref.
   Cross-check against `<repos-root>/.unloader_repos/cpc.repos`.
3. Confirm each repo path from the manifest exists under the repos root.

### Step 1 — Determine the target version

- If a `version` arg was given, normalize to `vX.Y.Z`. Infer the bump level by diffing
  against the current version: patch digit changed → **patch (per-repo)**; minor or major
  changed → **release (across-repos)**.
- Otherwise, compute candidates from the current version and **ask the user major / minor /
  patch** (e.g. `v3.1.3` → major `v4.0.0`, minor `v3.2.0`, patch `v3.1.4`). Confirm the string.
- Derive the two names from `<version>` (`vX.Y.Z`): the **RC branch** is
  `release-candidate/<version>` (uniform across every participating repo), and the **sw config
  name** is `<version>rc` (e.g. `v3.2.0rc`).

### Step 2 — Determine participating repos (scope from bump level)

- **Patch (per-repo):** participants are the named `repos...` only. Resolve each against the
  manifest repo list (exact match, then substring); error on any that don't resolve. If no
  `repos...` were given, **ask which repo(s) to patch** — do not default to all. Every other
  repo carries over its existing pinned ref.
- **Release (major/minor, across-repos):** **all** manifest repos participate. If `repos...`
  were passed alongside a release-level bump, warn about the mismatch and ask whether to
  narrow the scope or proceed across all.
- Print the participating list (and, for a patch, the carried-over repos) and **confirm
  before any writes**.

### Step 3 — Preflight every participating repo (read-only, all-or-nothing)

For each participating repo, run from its directory:

1. `git fetch origin`.
2. Working tree must be clean. Collect every dirty repo; if any is dirty, **stop and report
   all of them** — cut nothing.
3. `origin/develop` must exist. If missing, **stop**.
4. If `release-candidate/<version>` already exists (local or remote), flag it and ask whether
   to re-cut (force) or abort. **Default: abort.**

Only proceed to Step 4 if every participating repo passes.

### Step 4 — Cut RC branches in the product repos

For each participating repo, from `origin/develop`:

```bash
git checkout -B release-candidate/<version> origin/develop
git push -u origin release-candidate/<version>
```

- Use `--force-with-lease` on the push **only** when re-cutting an existing RC (Step 3.4).
  Never `git push --force`.
- Leave each repo checked out on its RC branch so `sw save --branches` records it.

### Step 5 — Write the manifest config via duckctl

With every participating repo checked out on `release-candidate/<version>`, save the config
under the **`<version>rc`** name (NOT `release-candidate/<version>`):

1. Preview first:
   ```bash
   duckctl sw save <version>rc --branches --like <current-version> --dump
   ```
   Show the resulting `cpc.repos` and its diff vs the current config. Each participating repo's
   `version:` line should read `release-candidate/<version>` (its checked-out branch). `--like
   <current-version>` seeds the repo list/order so non-participating repos carry over on their
   existing pinned ref.
2. On approval, run the real save (drop `--dump`):
   ```bash
   duckctl sw save <version>rc --branches --like <current-version>
   ```
3. **Always verify the push.** `sw save` skips the commit/push when `cpc.repos` content is
   unchanged from an existing config (only the config name differs) — the local `<version>rc`
   branch then exists but is NOT on the remote. Check and push if missing:
   ```bash
   git -C <repos-root>/.unloader_repos push -u origin <version>rc
   ```

### Step 6 — Summary

Print a table and the follow-up command:

```
## RC cut: <version>rc  (branches: release-candidate/<version>, mode: release | patch)

| Repo | Old ref | New ref | Pushed |
|------|---------|---------|--------|
| unloading_robot_common | v3.1.3 | release-candidate/v3.1.4 | yes |
| unloading_robot_hal    | v3.1.0 | v3.1.0 (carried over)    | —   |
| ...

Manifest config: <version>rc  (pins repos to release-candidate/<version>, pushed: yes/no)
Load it with:    duckctl sw load <version>rc
```

## Rules

- **Keep the two names distinct.** Product-repo **branch** = `release-candidate/vX.Y.Z` (never
  rename — renaming breaks the `pull_request` CI trigger `release-candidate/*`). Manifest **sw
  config name** = `vX.Y.Zrc`. The `vX.Y.Zrc` config pins every repo to its
  `release-candidate/vX.Y.Z` branch.
- **The RC number is uniform** across all participating repos — never a per-repo tag.
- **Read-only discovery and preflight before any mutation.** Cutting is all-or-nothing across
  participating repos: if any preflight fails, cut nothing.
- **Clean working tree required** in every participating repo; refuse otherwise.
- **NEVER `git push --force`.** Use `--force-with-lease`, and only when re-cutting an existing
  RC that the user approved.
- **Never auto-resolve conflicts.** Stop and report.
- **Confirm twice:** the participating list (Step 2) and the `cpc.repos` diff (Step 5) before
  writing.
- Do NOT include `Co-Authored-By` lines in any commit this command makes.
- Promoting an RC to a final release (merge to `main`, tag, `sw save`) is out of scope — that is
  `/release-dispatch`, gated by `/release-check`.

## The release command family

Run in this order; each assumes the previous one succeeded.

| Command | Does |
|---------|------|
| `/release-cut` | Cut `release-candidate/vX.Y.Z` branches + the `vX.Y.Zrc` sw config |
| `/release-check` | Read-only readiness audit of the RC — BLOCKERS / WARNINGS / READY |
| `/release-dispatch` | Merge → tag + GitHub Release → `duckctl sw save` → verify the build |
| `/release-notes` | The whole-release Confluence page |
| `/release-blob` | Per-author feature blobs, for standup/Jira |

**Two names, always distinct:** the product-repo git **branch** is `release-candidate/vX.Y.Z`
(identical in every repo — cross-repo CI triggers on it, never rename it); the `duckctl sw`
config is `vX.Y.Zrc` for the RC and `vX.Y.Z` for the release.

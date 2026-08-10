---
description: Read-only release-readiness check for an unloader release-candidate — per-repo RC/main/develop state, open PRs, merge-workflow dispatchability, deploy-key secrets, and the matching duckctl sw config.
allowed-tools: Bash(git log:*), Bash(git rev-list:*), Bash(git merge-base:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git show:*), Bash(git ls-remote:*), Bash(git config:*), Bash(gh api:*), Bash(gh pr list:*), Bash(gh repo view:*), Bash(gh auth status), Bash(duckctl sw version), Bash(duckctl sw versions:*), Bash(duckctl sw ls:*), Bash(duckctl sw status:*), Bash(pwd), Bash(ls:*), Bash(cat:*), Bash(grep:*), Bash(test:*), Bash(echo:*), Bash(command:*), Bash(for *), Read, Glob
argument-hint: "[version]"
---

## Context

- Current directory: !`pwd`
- Repos dir env: !`printenv CONTORO_REPOS_DIR || echo "<unset>"`
- Current software version: !`duckctl sw version 2>/dev/null || echo "<duckctl unavailable>"`
- gh on PATH: !`command -v gh >/dev/null 2>&1 && gh auth status 2>&1 | head -2 || echo "<gh missing>"`
- Manifest version branches: !`git -C ~/repos/.unloader_repos branch -r 2>/dev/null | grep -E 'origin/v[0-9]' | tail -8 || echo "<manifest repo not found under ~/repos — set CONTORO_REPOS_DIR if it lives elsewhere>"`
- Arguments: $ARGUMENTS — optional `[version]` (e.g. `v3.2.0`)

## What this does

Answer one question: **is `release-candidate/vX.Y.Z` ready to be promoted to `main` and tagged?**
It is **strictly read-only** — it inspects, it never fetches, pushes, tags, merges, or dispatches.

**Naming reminder** (see `/release-cut`): the product-repo git **branch** is
`release-candidate/vX.Y.Z` — identical in every repo, because cross-repo CI triggers on
`pull_request` against `release-candidate/*`; never rename it. The release **tag** is `vX.Y.Z`
on `main`. The `.unloader_repos` **sw config branch** is `vX.Y.Zrc` for the RC and `vX.Y.Z` for
the release. This command reads all three.

## Workspace detection

Operates on the **repos root**, not a single git repo.

1. Resolve the repos root: `$CONTORO_REPOS_DIR` if set, else `~/repos`.
2. It must contain `.unloader_repos` (the manifest repo). If not, **stop** and ask for the root.
3. `gh` must be on `PATH` and authenticated — the secret and workflow checks (Step 2.6, 2.7)
   have no local equivalent. If `gh` is missing, **stop**; a partial verdict is worse than none.
4. `duckctl` is optional (only Step 3 uses it); fall back to reading `cpc.repos` directly.

## Steps

### Step 0 — Resolve the version

1. Use the `[version]` arg, normalized to `vX.Y.Z`.
2. If absent, infer candidates: `release-candidate/*` branches present across the repos plus
   `vX.Y.Zrc` branches in `.unloader_repos`. One candidate → confirm it. Several or none →
   **ask**. Never guess.

### Step 1 — Enumerate the repo set from the manifest (never hardcode)

```bash
git -C <repos-root>/.unloader_repos show origin/<version>rc:cpc.repos
```

- Take the repo list and the GitHub name from each `url:` field (`contoroinc/<name>`).
- **The list grows** — `unloading_robot_msgs` was added after v3.1 and is absent from v3.1.x
  configs. As of `v3.2.0rc` there are 12 repos.
- If the `<version>rc` config branch is missing, fall back to the `release-candidate/*` branches
  found under the repos root and **flag the missing config as a blocker for Step 3**.
- **Not every repo is cloned locally.** Drive the per-repo checks from `gh api` so coverage is
  complete; use local git only as the cross-check in Step 2.2.

### Step 2 — Per-repo checks

For each repo (`R = contoroinc/<name>`, `RC = release-candidate/<version>`):

1. **RC branch exists** — `gh api repos/R/git/ref/heads/RC`. Missing → **blocker**.
2. **RC vs `main`** — `gh api "repos/R/compare/main...RC" --jq '{status,ahead_by,behind_by}'`.
   - `ahead` → normal, this is the merge that will ship; report the commit count.
   - `identical` / `behind` → `main` already contains the RC. The merge is a **NO-OP**; this
     repo needs only a tag. **Warning**, and say so explicitly.
   - `diverged` → `main` has commits the RC does not. **Blocker.**
   - **Cross-check locally when the repo is cloned**, and prefer the local answer — but only
     after confirming the local mirror is current, since this command never fetches:
     ```bash
     git -C <repo> ls-remote origin main refs/heads/RC     # remote truth
     git -C <repo> rev-parse origin/main origin/RC          # local mirror
     git -C <repo> rev-list --left-right --count origin/main...origin/RC
     ```
     If the two SHAs disagree, the local mirror is stale → use the API answer and note it.
3. **`develop` ahead of RC** — post-cut work that will **not** ship:
   `gh api "repos/R/compare/RC...develop" --jq '.ahead_by'`, then **list the commit subjects**
   (`.commits[].commit.message | first line`) so the release owner can confirm nothing needed
   was left behind. Non-zero → **warning**.
4. **Open PRs targeting the RC** — any open PR means the RC is **not frozen**:
   ```bash
   gh pr list -R R --state open --base RC \
     --json number,title,reviewDecision,statusCheckRollup,mergeable
   ```
   Any result → **blocker**. Report number, title, review decision, CI rollup, mergeable state.
5. **RC head SHA** — `gh api repos/R/git/ref/heads/RC --jq .object.sha` (short form). This is
   the fingerprint that catches an RC moving mid-release; compare against the SHA from an
   earlier run of this command if the user has one. Moved → **warning**.
6. **`merge-into-branch.yaml` on the repo's DEFAULT branch** — the dispatchability gate.
   GitHub only offers `workflow_dispatch` from the **default** branch, so a workflow living
   only on `main` or only on the RC is **not runnable**:
   ```bash
   DEF=$(gh api repos/R --jq .default_branch)
   gh api "repos/R/contents/.github/workflows?ref=$DEF" --jq '.[].name'
   ```
   Absent from the default branch → **blocker**. Report the default branch name alongside.
7. **`PRIVATE_DEPLOY_KEY` repo secret** —
   `gh api repos/R/actions/secrets --jq '.secrets[].name'`. The shared merge/autosync workflows
   forward it to `common_github_workflows`; without it they fail at the **`Setup up SSH agent`**
   step. Missing → **blocker**. (`operator_ui` was missing it entirely on 2026-08-04.)
8. **`autosync-main-to-develop.yaml`** — from the same workflow listing as 2.6. Absent →
   **warning**: `main` will silently drift ahead of `develop` after the release merge.

### Step 3 — Manifest layer

1. The `<version>rc` config branch exists **on the remote** of `.unloader_repos`:
   `git -C <repos-root>/.unloader_repos ls-remote --heads origin <version>rc`.
   A local-only branch is a **blocker** — `duckctl sw save` skips the commit/push when the
   resulting `cpc.repos` is byte-identical to an existing config, leaving the branch unpushed.
2. Every repo pinned by that config **resolves**: each `version:` ref exists in its repo
   (`gh api repos/R/git/ref/heads/<ref>`, or `.../git/ref/tags/<ref>` for a tag pin). Any
   unresolvable pin → **blocker**.
3. Cross-check the config's repo set against the repos actually carrying an RC branch. A repo
   with an RC branch but absent from the config (or vice versa) → **blocker**.
4. Note whether a **release** config branch `<version>` (no `rc`) already exists — if it does,
   this release may already be partly promoted.

### Step 4 — Report

Print one compact table, then the verdict blocks. Keep the table to one line per repo.

```
## Release check: <version>   (RC branch: release-candidate/<version>, sw config: <version>rc)

| Repo | RC | vs main | dev ahead | open PRs | merge-wf@default | DEPLOY_KEY | autosync | RC head |
|------|----|---------|-----------|----------|------------------|------------|----------|---------|
| task_executor | yes | ahead 156 | 4 | 0 | yes (develop) | yes | yes | 04a564a |
| operator_ui   | yes | identical | 0 | 1 | no (develop)  | MISSING | yes | 1b2c3d4 |
| ...

Manifest: <version>rc pushed: yes | 12/12 pins resolve | release config <version>: absent
```

Then, clearly separated:

```
### BLOCKERS  (n)
- operator_ui — PRIVATE_DEPLOY_KEY secret missing; merge workflow will fail at "Setup up SSH agent"
- operator_ui — merge-into-branch.yaml not on default branch `develop`; workflow_dispatch unavailable
- perception  — RC diverged from main (main +3 / RC +12)

### WARNINGS  (n)
- common — main already contains the RC (identical): merge is a NO-OP, this repo needs only the tag
- task_executor — develop is 4 commits ahead of the RC and will NOT ship:
    - a1b2c3d fix: ...
- teleop — no autosync-main-to-develop.yaml; main will drift ahead of develop

### READY  (n/12)
- hal, kuka_experimental, debugger, ...

VERDICT: NOT READY — n blockers across m repos.
```

- Under `develop ahead`, always print the actual commit subjects (indented) — the count alone
  is not actionable.
- If the verdict is clean, say **READY** and list what the operator would do next; do **not**
  run any of it.

## Rules

- **Strictly read-only.** No `push`, `tag`, `merge`, `checkout`, `fetch`, `workflow run`, `gh pr
  merge`, `duckctl sw save|load|archive`. Report state; the operator acts.
- **Never fetch to freshen a local mirror.** Treat `origin/*` refs as possibly stale, verify
  with `git ls-remote`, and prefer `gh api` whenever they disagree.
- **Enumerate repos from `cpc.repos`, never from memory.** The list grows between releases.
- **`merge-into-main.yaml` is DEPRECATED and misleading.** It was consolidated into the generic
  `merge-into-branch.yaml` (`target_branch` input). The old file still sits on `main` in several
  repos but not on `develop`/RC. Dispatched against an RC ref it fails; against `main` it
  silently merges `main` into itself. Only `merge-into-branch.yaml` counts — and only on the
  **default** branch.
- **Pushes directly to `release-candidate/*` run NO CI** — per-repo CI is `pull_request`-only.
  A green history is not evidence the RC content was tested; state this in every report where a
  repo's RC is ahead of `main`.
- **`contoro_utils` is tag-versioned, not plain git-flow** (`create-release-candidate.yaml`,
  auto-tags `vX.Y.Z.rc0` / `vX.Y+1.0.dev0`). Its tagging step differs from the other repos —
  **FLAG it for manual review**; do not assert a procedure for it, that path is unverified.
- **Blockers:** missing RC branch, diverged RC, any open PR into the RC, missing
  `PRIVATE_DEPLOY_KEY`, merge workflow absent from the default branch, unpushed/unresolvable
  manifest config.
  **Warnings:** post-cut `develop` drift, no-op merges, missing autosync workflow, RC head moved.
- **Never invent state.** Every cell traces to a `gh`/`git` invocation in this run; on an API
  error print `?` and name the failed call rather than guessing.

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

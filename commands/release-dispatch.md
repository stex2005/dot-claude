---
description: Execute a release across the unloader codebase — merge release-candidate branches into main, tag every repo, save the duckctl sw version, and verify the image build. Dry run first.
allowed-tools: Bash(gh workflow run:*), Bash(gh run list:*), Bash(gh run view:*), Bash(gh api:*), Bash(gh pr list:*), Bash(gh repo view:*), Bash(gh auth status), Bash(git show:*), Bash(git ls-remote:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git status:*), Bash(git branch:*), Bash(git push:*), Bash(duckctl sw:*), Bash(pwd), Bash(ls:*), Bash(cat:*), Bash(grep:*), Bash(test:*), Bash(echo:*), Bash(for *), Bash(sleep:*), Read, Glob
argument-hint: "[version] [--execute] [--step N]"
---

## Context

- Current directory: !`pwd`
- Repos dir env: !`printenv CONTORO_REPOS_DIR || echo "<unset>"`
- Current software version: !`duckctl sw version 2>/dev/null || echo "<duckctl unavailable>"`
- gh on PATH: !`command -v gh >/dev/null 2>&1 && gh auth status 2>&1 | head -2 || echo "<gh missing>"`
- Manifest RC configs: !`git -C ~/repos/.unloader_repos branch -r 2>/dev/null | grep -E 'origin/v[0-9].*rc$' | tail -5 || echo "<manifest repo not found under ~/repos — set CONTORO_REPOS_DIR if it lives elsewhere>"`
- Arguments: $ARGUMENTS — `[version]` (e.g. `v3.2.0`), `--execute` for real writes, `--step N` to run one step

## What this does

Take a validated release candidate all the way to a released software version, in **four steps**:

| Step | Action | Layer |
|------|--------|-------|
| 1 | Merge `release-candidate/vX.Y.Z` → `main` in every repo | product repos |
| 2 | Tag `vX.Y.Z` on each repo's `main` **and publish the GitHub Release** | product repos |
| 3 | `duckctl sw save vX.Y.Z --pin --like <seed>` | manifest |
| 4 | Verify the image build fired and the release installs | artifacts |

**Dry run is the default.** Without `--execute` the command performs Step 1 with
`check_only=true` and reports what Steps 2–4 *would* do, writing nothing. `--step N` runs a
single step — use it to resume after a partial run.

Readiness is a separate command: run **`/release-check <version>`** first and require a clean
verdict. This command re-checks the blockers but does not replace it.

## Workspace detection

1. Repos root: `$CONTORO_REPOS_DIR` if set, else `~/repos`. Must contain `.unloader_repos`.
2. `gh` must be on `PATH` and authenticated — **stop** otherwise; a half-released fleet is worse
   than an unreleased one.
3. `duckctl` is required for Step 3 only.

## Step 0 — Resolve version and repo set

1. Normalize `[version]` to `vX.Y.Z`. If absent, infer from `vX.Y.Zrc` config branches; one
   candidate → confirm, several or none → **ask**. Never guess.
2. Enumerate repos from the manifest, **never hardcoded** (the list grows between releases):
   ```bash
   git -C <repos-root>/.unloader_repos show origin/<version>rc:cpc.repos
   ```
3. Print the participating list and **confirm before any write**.

## Step 1 — Merge RC into `main`

Preflight, across **every** repo before dispatching **any** — a mid-sweep failure leaves the
fleet half-merged:

- No open PRs targeting `release-candidate/<version>` (RC not frozen).
- No repo `diverged` from `main`.
- `PRIVATE_DEPLOY_KEY` present everywhere — without it the shared workflow dies at
  **`Setup up SSH agent`**.
- `merge-into-branch.yaml` on each repo's **default** branch — `workflow_dispatch` is only
  offered from the default branch, so otherwise the dispatch never runs.

Dispatch **from the RC ref** so `source_branch` defaults correctly:

```bash
gh workflow run merge-into-branch.yaml --repo contoroinc/<repo> \
  --ref release-candidate/<version> \
  -f target_branch=main \
  -f check_only=<true|false> \
  -f delete_source_branch=false
```

`delete_source_branch` is **always false** here — the RC branch is still needed for Steps 2–3.

Poll each repo's latest run to completion (20s interval), then **verify independently**:

```bash
gh api "repos/contoroinc/<repo>/compare/main...release-candidate/<version>" --jq '{status,ahead_by}'
```

- After `--execute`: expect `identical`/`behind` with `ahead_by: 0`. Still `ahead` → the merge
  did not land despite a green run.
- After a dry run: expect `ahead` with an **unchanged** count. Anything else means `check_only`
  did not hold — stop.

**Autosync follows automatically** and needs its own interpretation — see the section below.

## Step 2 — Tag and Release every repo

**A git tag is not a GitHub Release.** The fleet convention is a published **Release** — that is
what shows on the repo's Releases tab and what carries the notes. Creating only the tag leaves
that tab empty and looks like the release never happened. Do both.

Preflight: refuse if the tag *or* the Release already exists in any repo; report and stop.

**2a — tag** at each repo's **`main` tip** (the RC merge commit):

```bash
SHA=$(gh api repos/contoroinc/<repo>/commits/main --jq .sha)
gh api -X POST repos/contoroinc/<repo>/git/refs -f ref="refs/tags/<version>" -f sha="$SHA"
```

**2b — publish the Release** on that tag, with generated notes:

```bash
gh api -X POST repos/contoroinc/<repo>/releases \
  -f tag_name=<version> -f name=<version> \
  -F generate_release_notes=true -F draft=false -F prerelease=false
```

- **Major/minor:** tag all repos uniformly, even those whose code did not change, so the fleet
  reads one version everywhere. **Patch:** tag only the changed repos; the rest carry over.
- Verify every tag resolves to its `main` tip, and that each Release exists and is `latest`.
- Generated notes are raw — they include autosync/merge PRs and already-shipped ports. Curate
  them with `/release-notes`, which knows what to strip.
- **Releases fire `release: published` workflows.** In `contoro_utils` that is
  `publish-to-codeartifact.yaml`; see Repo-specific notes.

## Step 3 — Save the software version

Check every repo out at its new tag, then:

```bash
duckctl sw status                                     # confirm each repo is on the right tag
duckctl sw save <version> --pin --like <seed> --dump  # preview
duckctl sw save <version> --pin --like <seed>         # commit
```

- **`--pin`, not `--branches`.** A release must be immutable; `--branches` is for RCs.
- **`--like` seeds the repo list.** It does not affect the pins — those come from the checked-out
  state — but it makes the set deterministic and *errors* on a repo missing from disk instead of
  silently omitting it. Without it you get an interactive `Include <repo>?` prompt over a
  filesystem scan that also sweeps up non-release repos.
- **Choose the seed by release kind:**
  - **Patch (`vX.Y.Z`, Z > 0) → `--like` the newest existing release config in the same line**,
    i.e. `vX.Y.(Z-1)` when it exists, falling back down the line to `vX.Y.0`. That is the release
    being patched, and it is the closest description of what the fleet is running now. Seeding
    from `develop` risks pulling in a repo added after the cut that is not part of this line;
    seeding from `vX.Y.0` when later patches exist reaches further back than necessary and
    reintroduces a repo set the line has already moved past.
    Ex: `v3.2.3` → `--like v3.2.2` (not `v3.2.0`); `v3.2.1` → `--like v3.2.0`.
  - **Minor / major (`vX.Y.0`) → `--like develop`.** Here the previous line is the wrong seed
    for the opposite reason: an older release config can be *missing* repos added since
    (`unloading_robot_msgs` was added after v3.1 and is absent from every v3.1.x config).
  - Either way, confirm the seed's repo count against the `<version>rc` config before saving —
    they must match.
- **`--like` reads the LOCAL branch, and a stale one silently yields the wrong repo set.**
  `.unloader_repos` is a working clone whose branches can lag origin by months, and a release
  config branch may not exist locally at all. Refresh the seed branch before saving, and never
  skip the `--dump` preview:
  ```bash
  SEED=<develop|vX.Y.(Z-1)>
  git -C <repos-root>/.unloader_repos fetch origin
  git -C <repos-root>/.unloader_repos merge-base --is-ancestor "$SEED" "origin/$SEED" \
    && git -C <repos-root>/.unloader_repos branch -f "$SEED" "origin/$SEED"
  ```
  Read the `--dump` output as a repo *set*, not just a pin list: a missing repo and an
  unexpected extra one both look like a normal config until you count them.
- **Always verify the push.** `sw save` skips the commit when the resulting `cpc.repos` is
  byte-identical to an existing config, leaving a local-only branch:
  ```bash
  git -C <repos-root>/.unloader_repos ls-remote --heads origin <version>
  ```

## Step 4 — Verify artifacts

- Creating the `vX.Y.Z` branch in `.unloader_repos` fires `trigger-docker-build.yml`, which
  dispatches `build-push-images.yml` in `unloading_robot_ws`. **Confirm the run actually
  started**; if not, trigger it manually with the version as input.
- Confirm the release installs: `duckctl sw install <version> -y`.
- Report what remains and do **not** run it: archive the RC config (`duckctl sw archive
  <version>rc`), delete the `release-candidate/<version>` branches, write the release notes
  (`/release-notes`), announce in **#software-releases**.

## Interpreting the autosync

Each push to `main` triggers `autosync-main-to-develop.yaml`. **A `success` conclusion does not
mean `develop` was updated** — the shared workflow gates on *content*, not commits:

```bash
git merge-tree --write-tree origin/develop origin/main   # tree unchanged → SKIP, job still "success"
```

After a release merge this legitimately skips in most repos: `develop` already contains the RC
content, because the RC was cut from `develop`. Check the job list — `Syncing branches: skipped`
is the healthy outcome.

**Judge sync health by content, never by commit count:**

```bash
gh api "repos/contoroinc/<repo>/compare/develop...main" --jq '.files|length'   # 0 → develop has everything
```

`compare/develop...main` will still report `ahead_by: 1` — that is the content-free merge
commit, not missing work. Do not chase it.

## Handling conflicts

The merge workflow does not simply fail. It pushes a sync branch
`<safe-src>-<sha>/merge-into-<target>` and opens a **draft** PR into the target.

- **Do not squash-merge that PR in the UI** — it rewrites commits and inflates later merges.
- Resolve on the sync branch (`git merge origin/main`, fix, push), then re-run
  `merge-into-branch.yaml` **from the sync branch** with target `main`.
- The workflow refuses to re-run while an open conflict PR exists for that source/target pair.

## Repo-specific notes

- **`contoro_utils` is tag-versioned**, not plain git-flow: `create-release-candidate.yaml`
  auto-tags `vX.Y.Z.rc0` on the RC and `vX.Y+1.0.dev0` on `develop`. Its historical release tags
  sat on the **RC head** (`v3.1.0` → the `release-candidate/v3.1.0` commit) rather than the merge
  commit; both are reachable from `main`, and tagging the `main` tip keeps the fleet uniform.
  `setuptools_scm` uses `--first-parent`, so a release tag on `main` does not disturb develop's
  dev versioning.
- **`contoro_utils` publishing:** `publish-to-codeartifact.yaml` fires on `release: published`
  and on push to `main` — **a bare git tag does not publish it**. If v`X.Y.Z` must reach
  CodeArtifact, cut a GitHub Release, and note that the push-to-main publish ran *before* the
  tag existed, so it derived a dev version rather than the release version.

## Rules

- **Dry run first, always.** `--execute` without a preceding clean `/release-check` and a
  successful `check_only` sweep is a mistake; say so and offer the dry run.
- **Never pass `delete_source_branch=true`** from this command. RC cleanup is a separate,
  post-release step.
- **`merge-into-main.yaml` is DEPRECATED.** Consolidated into `merge-into-branch.yaml`. The old
  file still sits on `main` in several repos but not on `develop`/RC — dispatched against an RC
  ref it fails, against `main` it silently merges `main` into itself and reports success. Only
  ever dispatch `merge-into-branch.yaml`.
- **Dispatch from the RC ref**, never from `main`.
- **A green run is never proof.** Verify every step against repository state, not exit codes:
  merges via `compare`, tags via the ref API, the manifest via `ls-remote`, the build via a run
  listing.
- **Steps are ordered and not independent.** Tags require the merge; the manifest save requires
  the tags; the build requires the manifest branch. Never skip forward.
- **Pushes to `release-candidate/*` run no CI** (per-repo CI is `pull_request`-only), so a clean
  merge says nothing about test status. Never present a successful sweep as a quality signal.
- **Stop and report on any per-repo failure.** Do not continue to the next step with a partial
  fleet.

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

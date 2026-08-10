---
description: Generate a fully-populated "vX.Y Release Notes" Confluence draft for a release-candidate — aggregated PRs across all product repos, synthesized change table, a ranked top-5–10 operator TL;DR with IssueTracking (IT) links, and sample config.
allowed-tools: Bash(git *), Bash(gh *), Bash(duckctl *), Bash(cd *), Bash(ls *), Bash(for *), Bash(grep *), Bash(cat *), Bash(find *), Bash(pwd *), Bash(test *), Bash(echo *), Read, Glob
argument-hint: "[version]"
---

## Context

- Current directory: !`pwd`
- Repos dir env: !`printenv CONTORO_REPOS_DIR || echo "<unset>"`
- Current software version: !`duckctl sw version 2>/dev/null || echo "<duckctl unavailable>"`
- gh on PATH: !`command -v gh >/dev/null 2>&1 && gh --version | head -1 || echo "<gh missing>"`
- Arguments: $ARGUMENTS — optional `[version]` (e.g. `v3.2.0`). Defaults to the current RC.

## What this does

Generate the **`vX.Y Release Notes`** page for a release-candidate as a **Confluence draft**,
mirroring the existing v3.1 Release Notes page
(<https://contoro.atlassian.net/wiki/spaces/Software1/pages/1207173266/v3.1+Release+Notes>).

It aggregates every merged PR across all product repos in the RC — from the previous release
line up to the `release-candidate/vX.Y.Z` branches — then **fully writes** the page: a grouped
change table, the operator TL;DR, critical changes, upgrade steps, and a sample config. It is
read-only until the final page-creation step, which is **confirmed** and creates a **draft**
(never auto-publishes).

**Naming reminder** (see `/release-cut`): the git branches are
`release-candidate/vX.Y.Z`; the `duckctl sw` config is `vX.Y.Zrc`. This command reads the
branches.

## Workspace detection

Operates on the **repos root**, not a single git repo.

1. Resolve the repos root: `$CONTORO_REPOS_DIR` if set, else `~/repos`.
2. It must contain `.unloader_repos` (the manifest repo). If not, **stop** and ask for the root.
3. `duckctl` must be on `PATH`. If missing, **stop**.
4. `gh` must be on `PATH` and authenticated (`gh auth status`). If missing, warn — Step 1 will
   fall back to `git log` commit subjects (noisier, no PR links, no authors).
5. The Atlassian integration must be available (the `getConfluencePage` / `createConfluencePage`
   tools). If not, **stop** before Step 3 and offer to write a local markdown file instead.

## Steps

### Step 0 — Resolve version and range (read-only)

1. **Target version.** Use the `[version]` arg (normalize to `vX.Y.Z`). If absent, derive from
   `duckctl sw version` (strip a trailing `rc`) or from the `release-candidate/*` branches
   present in the repos. Confirm the string.
2. **RC branch** per repo = `release-candidate/vX.Y.Z`. Verify it exists (local or
   `origin/`) in every repo; `git fetch origin` first. Report any repo missing it and **stop**.
3. **Baseline** = the previous release line's **final** sw config: the highest non-rc config
   with minor `< Y` from `duckctl sw versions` (e.g. target `v3.2.0` → highest `v3.1.*`). Ask
   the user to confirm the baseline config, or accept an override.
4. **Per-repo baseline ref** via `duckctl sw ls <baseline>` — each repo's pinned tag (repos
   sit at heterogeneous tags, e.g. kuka `v3.1.0`, perception `v3.1.1`, common `v3.1.3`).
5. Print the resolved range table (`repo | baseline_ref | release-candidate/vX.Y.Z`) and
   **confirm before gathering**.

### Step 1 — Gather PRs per repo (read-only)

**Enumerate the repo set from the manifest, not from memory.** Iterate over *every* repo in
`.unloader_repos/cpc.repos` **and** `.unloader_repos/rtpc.repos` (skip the latter only if empty).
Do **not** drop the low-activity/meta repos — `unloading_robot_ws`, `unloading_robot_operator_ui`,
`kuka_experimental`, `contoro_utils` — a repo with 0 PRs in range is a finding to state, not a
repo to silently omit. Also include any new dependency repo referenced by the RC even if it is
not yet in the manifest (e.g. `unloading_robot_msgs`, discoverable via a "wire … into the
workspace" PR in `unloading_robot_ws`). At the end, print a coverage table (`repo | #PRs`) for
all manifest repos so the user can confirm nothing was skipped.

For each repo, enumerate PRs merged in `baseline_ref..release-candidate/vX.Y.Z`:

```bash
# commits in range, then the PR each merged commit belongs to
git -C <repo> log --oneline <baseline_ref>..origin/release-candidate/<version>
gh -R contoroinc/<repo> pr list --state merged --search "..." --json number,title,author,labels,url,mergedAt
```

- Prefer `gh` (number, title, author, labels, URL). A reliable approach: collect PR numbers
  from merge-commit subjects / `gh pr list --search "<sha>"` for the commits in range, then
  fetch each PR's metadata.
- **Fall back** to `git log --no-merges` commit subjects when `gh` is unavailable or a repo has
  no PRs in range. Note the fallback explicitly in the output.
- Map each repo path to its GitHub name (`contoroinc/<name>`) from `.unloader_repos/cpc.repos`
  `url:` fields.
- **Never invent PR numbers.** Only emit numbers returned by `gh`/`git` in this step.
- **Harvest IssueTracking (IT) references.** Grep each repo's commit subjects *and* bodies in
  range for `IT-[0-9]+`, and note which PR each ticket maps to — these become the TL;DR links
  (Step 2.4). Ex:
  ```bash
  git -C <repo> log --pretty=format:'%h %s%n%b' <baseline_ref>..origin/release-candidate/<version> \
    | grep -oiE 'IT-[0-9]+' | sort -u
  ```
  IT tickets are Jira issues at `https://contoro.atlassian.net/browse/IT-<n>`.
  **Never invent an IT number** — only link tickets that actually appear in the commit text.

### Step 1b — Strip noise and already-shipped work (do this before synthesizing)

A raw range is roughly **30% noise**, and some of what remains already shipped in the previous
line. Filter before counting or writing anything, and report what was dropped and why — a silent
filter is indistinguishable from a bug.

Drop from the change list:

1. **Merge / sync / autosync PRs.** `Merged 'X' into 'Y'`, `Sync <branch> into <branch>`,
   `Autosync 'main' to 'develop'`, and anything authored by `@github-actions[bot]`. These are
   the single largest category — in v3.2.0 task_executor alone had 39 of them.
   **`git log --no-merges` does NOT remove these** — they are merge commits, so `--no-merges`
   hides them from commit output while `gh pr list` and GitHub's generated notes still show them
   as PRs. Filter by subject and author, not by commit shape.
2. **CI-only PRs** — `chore(ci):`, `fix(ci):`, `ci:`, `chore(deps):`. Keep them out of the
   operator-facing table; they may be worth a single line in a Refactoring/Infra footnote.
3. **Already shipped in the previous line.** When a fix was *ported* or cherry-picked onto a
   previous release branch rather than merged, it exists as two commits with different SHAs, so
   a range diff counts it as new. The squash subject keeps the original `(#N)`, so detect by PR
   number, not SHA:
   ```bash
   # already-shipped set = every (#N) reachable from the previous release line
   { git -C <repo> log --format='%s' origin/release-candidate/vX.$((Y-1)).0 2>/dev/null
     for t in $(git -C <repo> tag -l "vX.$((Y-1)).*"); do git -C <repo> log --format='%s' "$t"; done
   } | grep -oP '#\K[0-9]+' | sort -u > /tmp/shipped_prs

   git -C <repo> log --format='%s' --no-merges <baseline_ref>..origin/release-candidate/<version> \
     | grep -oP '\(#\K[0-9]+(?=\))' | sort -u > /tmp/range_prs

   comm -12 /tmp/range_prs /tmp/shipped_prs      # → already shipped, exclude
   ```
   Use the previous minor's **RC branch and all its `vX.(Y-1).*` tags** — the per-repo baseline
   sw-config tag alone is not enough, because it misses cherry-picks that landed after the tag
   point.
   `git cherry` is **not** reliable here: ports are usually adapted to the release branch, so
   the patch IDs differ even though the change is the same.
   Duplicates cluster in exactly the repos that received patch releases; a repo with no patches
   should show zero. If it doesn't, the baseline is probably wrong.

Also flag **feature-banner overlap**: if a surviving cluster's headline (e.g. "auto-recovery")
already headlined the previous release notes, present it as a *vX.Y increment* and say which
parts shipped earlier — don't re-announce the capability.

Print a per-repo table of `kept | dropped (by reason)` and keep the dropped list on disk so the
filtering is auditable. Flag borderline cases rather than deciding silently — a ported fix that
was later revised on `develop` is legitimately both "already shipped" and "new".

### Step 2 — Synthesize the page body

Author the full page, matching the v3.1 Release Notes structure and tone:

1. **Heading** `# vX.Y.0`.
2. **Upgrade Process** (mechanical):
   ```
   * `duckctl sw reset`
   * `duckctl sw install vX.Y.0 -y`
   * `duckctl up`
   ```
3. **Critical Changes** — a short bullet list of must-know operator/config changes, synthesized
   from the notable PRs (breaking changes, new required settings, hardware-revision gating).
4. **TL;DR; for Operators** — a **ranked list of the top 5–10 features/bugfixes**, most notable
   first, derived from the actual change table (Step 2.5) — not generic themes. Each item:
   - one plain-language sentence on what changed and why the operator cares;
   - tagged `(new)` for a capability, `(platform)` for hardware/interface changes, or
     `Fix —` for a bugfix;
   - **the real PR links** for that item (same repo-grouped format as the table), and
   - **an IssueTracking link** (`[IT-<n>](https://contoro.atlassian.net/browse/IT-<n>)`) whenever
     the item's commits reference one (from the Step 1 harvest). Prioritize field-incident
     bugfixes that carry an IT ticket — those matter most to operators.
   Close with a one-line "Also in this release:" sentence sweeping up the remaining notable
   work (msgs package, motion-stack unification, infra) so nothing major is dropped.
   Rank by operator/field impact: new capabilities and field-incident fixes above refactors and
   internal tooling.
5. **Change table** `| Repo | Authors | Changes | PRs |`:
   - Group related PRs across repos into one **semantic row** with a human-readable **Changes**
     description (like the v3.1 page — one feature/fix per row, not one PR per row).
   - **Authors:** deduped display names across the row's PRs.
   - **PRs:** grouped by repo, `<RepoDisplayName> [#N](url), [#N](url); <OtherRepo> [#N](url)`.
   - Repo display names: Task Executor, Common, Process Orchestrator, Perception, Contoro Utils,
     HAL, Teleop, Debugger, Operator UI, Kuka, WS.
6. **Sample Configuration** — a reference hardware-config block, prefixed with:
   *"Use this as a reference. Do not copy-paste this text into a duck without verifying every
   value."* Source it from a canonical config in the repos if one exists; otherwise carry the
   v3.1 page's block as a labeled placeholder.

Render the full draft to the user for review.

### Step 3 — Create the Confluence draft (confirmed)

1. Show the rendered page and **confirm** creation.
2. On approval, create it as a **draft** via the Atlassian integration:
   - space key `Software1`, title `vX.Y Release Notes`, `contentFormat: markdown`, status draft.
   - Reference the v3.1 page (`getConfluencePage` 1207173266) for exact formatting parity.
3. Return the page URL. **Never publish** — leave it as a draft for human review.
4. If the Atlassian integration is unavailable, write the notes to a local markdown file
   (e.g. `<repos-root>/RELEASE_NOTES_vX.Y.0.md`) and hand back the path instead.

## Rules

- **Read-only until Step 3.** Gathering and synthesis mutate nothing.
- **Confirm twice:** the resolved range (Step 0.5) and the rendered page before creating it
  (Step 3.1).
- **Never invent PR numbers, links, or authors** — every entry must trace to `gh`/`git` output
  from Step 1. If unsure, omit rather than guess.
- **TL;DR is ranked and evidence-based:** the top 5–10 items come straight from the change
  table, carry their real PR links, and cite an `IT-<n>` ticket whenever the commits reference
  one. Never fabricate an IT number — link only tickets found in Step 1's harvest.
- **Draft only.** Create the Confluence page as a draft; never auto-publish.
- **Sample config is a reference**, always labeled "verify every value" — never presented as a
  ready-to-apply config.
- **Reuse `/release-cut` naming:** branches `release-candidate/vX.Y.Z`, sw config
  `vX.Y.Zrc`. This command reads branches.

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

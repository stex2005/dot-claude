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
5. The Atlassian integration must be available (`getConfluencePage` / `createConfluencePage` /
   `updateConfluencePage`, plus `getContentFormatGuide` for the HTML panel syntax). If not,
   **stop** before Step 3 and offer to write a local markdown file instead — flagging that the
   panels do not survive that fallback.

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

Author the full page, matching the v3.1 Release Notes structure and tone.

**Every section below carries a panel type** — the page is read by operators under time
pressure, and the panel colour is the first thing they see. Assign them as specified; do not
leave a section as bare prose because it "looks fine", and do not panel *everything* — a page
where every block is coloured signals nothing. Prose between panels is what makes the panels
read as emphasis.

| Section | Panel | Why |
|---------|-------|-----|
| Provenance line | `info` | Neutral context: which branches, cut when |
| Upgrade Process | `info` | Mechanical steps, no judgement |
| Config migration / blocking steps | `warning` | A duck on an unmigrated config will not start |
| Critical Changes | `warning` | Breaking changes that stop unloading if missed |
| TL;DR; for Operators | `success` | What the operator gains this release |
| Shipped but not active | `note` | Off by default, opt-in, or deferred — see below |
| Change table | **none** | Tables are forbidden inside panels — see Step 3 |
| Sample Configuration caveat | `warning` | Copy-pasting it unverified breaks a robot |

**`note` is for capability that shipped but does nothing yet.** A feature disabled by default,
one gated behind a rosparam the operator must flip, or work that was cut from the release and
will land next — all of it is real, none of it changes behaviour on upgrade. Put it in a `note`
panel after the TL;DR. Written as `info` it reads like an upgrade step; written as `success` it
implies the operator already has it. Include the switch that turns it on (`/TE/<param>`, a UI
toggle) so the panel is actionable rather than trivia. Omit the panel entirely when the release
has no such items.

Reserve `error` for a known-broken item shipping in the release (a regression accepted at the
cut, a feature disabled late). If there is none, do not use it — an `error` panel on a healthy
release trains operators to ignore red.

1. **Heading** `# vX.Y.0`, followed by the provenance line in an **`info` panel**: which
   branches the notes were generated from, the cut date, and the sw config name.
2. **Upgrade Process** (mechanical) in an **`info` panel**, the commands as a code block
   *inside* the panel (code blocks are legal panel children):
   ```
   * `duckctl sw reset`
   * `duckctl sw install vX.Y.0 -y`
   * `duckctl up`
   ```
   Any step that must happen or the robot will not start — a config-schema migration, a
   required new key, a one-time volume wipe — goes in a **separate `warning` panel** directly
   beneath, never buried in the `info` list.
3. **Critical Changes** — a short bullet list of must-know operator/config changes, synthesized
   from the notable PRs (breaking changes, new required settings, hardware-revision gating),
   wrapped in a **`warning` panel**. Bullet lists are legal panel children, so the whole list
   goes in one panel rather than one panel per bullet.
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
   Wrap the whole ranked list in a **`success` panel** — one panel around the list, not one per
   item. The "Also in this release:" closer sits inside it. If an item is a fix for something
   that bit the fleet, it still belongs here: `success` describes the release's value to the
   operator, not the mood of each line.
5. **Change table** `| Repo | Authors | Changes | PRs |` — **not in a panel**, tables are
   rejected there (Step 3):
   - Group related PRs across repos into one **semantic row** with a human-readable **Changes**
     description (like the v3.1 page — one feature/fix per row, not one PR per row).
   - **Authors:** deduped display names across the row's PRs.
   - **PRs:** grouped by repo, `<RepoDisplayName> [#N](url), [#N](url); <OtherRepo> [#N](url)`.
   - Repo display names: Task Executor, Common, Process Orchestrator, Perception, Contoro Utils,
     HAL, Teleop, Debugger, Operator UI, Kuka, WS.
6. **Sample Configuration** — a reference hardware-config block. Put the caveat *"Use this as a
   reference. Do not copy-paste this text into a duck without verifying every value."* in a
   **`warning` panel**, and call out anything the schema changed this release (a new required
   key, a promoted field). The YAML itself goes in a code block — either inside that panel or
   directly beneath it; both render, so prefer inside so the caveat cannot be scrolled past.
   Source it from a canonical config in the repos if one exists; otherwise carry the v3.1
   page's block as a labeled placeholder.

Render the full draft to the user for review.

### Step 3 — Create the Confluence draft (confirmed)

**Author the body as HTML, not markdown.** `contentFormat: markdown` cannot express panels at
all — it silently produces a flat page with no coloured blocks, which looks like the panel
instruction was ignored rather than unsupported. Panels require `contentFormat: html`.

1. Show the rendered page and **confirm** creation.
2. **Call `getContentFormatGuide` first** with `{ toolName: "createConfluencePage" }` (or
   `updateConfluencePage` when editing an existing page) and follow what it returns. It is the
   canonical source for the HTML dialect; the syntax below is a summary, and the guide wins
   where they disagree.
3. On approval, create it as a **draft** via the Atlassian integration:
   - space key `Software1`, title `vX.Y Release Notes`, **`contentFormat: html`**, status draft.
   - Reference the v3.1 page (`getConfluencePage` 1207173266) for structure and tone parity —
     note it predates panels, so copy its shape, not its flatness.
4. Return the page URL. **Never publish** — leave it as a draft for human review.
5. If the Atlassian integration is unavailable, write the notes to a local markdown file
   (e.g. `<repos-root>/RELEASE_NOTES_vX.Y.0.md`) and hand back the path instead — noting in the
   handoff that panels are lost in that fallback.

#### Panel syntax

```html
<div data-type="panel-info"><p>Generated from the frozen release-candidate/v3.3.0 branches…</p></div>
<div data-type="panel-warning"><p><strong>Config migration is required.</strong></p><ul><li>…</li></ul></div>
<div data-type="panel-success"><p>The highest-impact features and fixes, most notable first:</p><ol><li>…</li></ol></div>
```

Types: `info`, `note`, `warning`, `success`, `error` (`tip` is accepted as `info`).

**A panel's children are restricted.** Legal: paragraphs, headings, bullet/ordered lists, code
blocks, rules. **Illegal: tables, expands, blockquotes, nested panels.** Two consequences that
will bite:

- **The change table must live outside every panel.** Putting it in one is rejected by the
  converter or silently mangled. Give it a plain `<h3>` heading instead.
- **A panel cannot hold another panel**, so the migration `warning` sits *beside* the upgrade
  `info` panel, not inside it.

Do **not** emit Confluence storage XML (`<ac:structured-macro>`, `<ac:rich-text-body>`, CDATA)
to get a panel — it renders as visible raw text on the page. The `data-type` div above is the
supported form.

Panels do not nest inside markdown either: if you have an existing markdown page to convert,
rewrite the body as HTML rather than splicing HTML fragments into markdown.

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
- **HTML, not markdown.** The body is `contentFormat: html` because panels need it; call
  `getContentFormatGuide` before authoring. A page that came out flat and uncoloured means the
  format was wrong, not that the panels were unnecessary.
- **Panels are semantic, not decorative.** `warning` = will break the robot or the upgrade;
  `success` = what the operator gains; `info` = neutral context and mechanical steps; `note` =
  shipped but inactive (off by default, opt-in, deferred); `error` only for something
  known-broken that is shipping anyway. Never pick a type for contrast.
- **Never put the change table in a panel** — tables are not legal panel children.
- **Sample config is a reference**, always labeled "verify every value" in a `warning` panel —
  never presented as a ready-to-apply config.
- **Reuse `/release-cut` naming:** branches `release-candidate/vX.Y.Z`, sw config
  `vX.Y.Zrc`. This command reads branches.

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

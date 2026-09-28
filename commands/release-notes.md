---
description: Generate a fully-populated "vX.Y Release Notes <date>" Confluence page — aggregated PRs across all product repos, operator-first sections in Confluence panels, a Detailed Changes table, and placeholders for the human-written Recommendations and Test/Validation sections.
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

Generate the **`vX.Y Release Notes <Mon D, YYYY>`** page for a release as a **Confluence draft**,
mirroring the v3.3 Release Notes page, which is the current model for structure, section order
and panel use
(<https://contoro.atlassian.net/wiki/spaces/Software1/pages/1416167594>).
The older v3.1 page predates panels and the operator-first ordering — do not copy its shape.

It aggregates every merged PR across all product repos in the RC — from the previous release
line up to the `release-candidate/vX.Y.Z` branches — then **fully writes** the page: a grouped
Detailed Changes table, the operator sections, critical changes, upgrade steps, and a sample
config — leaving Recommendations for Operators and Test and Validation Results for a human. It is
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
  range for `IT-[0-9]+`, and note which PR each ticket maps to — these become the feature links
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

**Section order is operator-first.** What an operator must do, then what they get, then what
they should do about it, then the evidence, then the engineering detail. Breaking changes sit
*below* the operator sections, not above them — the upgrade steps already carry anything that
blocks a start. Use `<h3>` for every section heading.

This is the element order of the v3.3 page, read back as HTML. Reproduce it exactly.

| # | Section (`<h3>`) | Contents, in order | Source |
|---|------------------|--------------------|--------|
| — | *(no heading)* | `info` panel — provenance | generated |
| 1 | Upgrade Instructions | numbered list, then `warning` panel headed **One-Time Steps** | generated |
| 2 | New Features for Operators | settings **table** (screenshots inside it), then `success` panel | generated |
| 3 | **Recommendations for Operators** | supporting image(s), then `info` panel | **ad hoc — ask, never invent** |
| 4 | **Test and Validation Results** | **table**, then `note` panel | **ad hoc — ask, never invent** |
| 5 | Silent Changes | `warning` panel | generated |
| 6 | Critical Changes | **`custom` panel** — `:rainbow:`, `#E6FCFF` | generated |
| 7 | Detailed Changes | **table**, no panel | generated |
| 8 | Change log of this page | plain paragraphs, no panel | generated |
| 9 | Sample Configuration | `warning` panel **with the YAML inside it** | generated |

**Title carries the release date**: `vX.Y Release Notes <Mon D, YYYY>` (e.g.
`v3.3 Release Notes Sep 22, 2026`), so a reader can tell at a glance which cut they are looking
at.

**Sections 3 and 4 are written by humans, per release.** See "Ad hoc sections" below — this is
the rule most likely to be broken, and the most damaging when it is.

**`note` is for capability that shipped but does nothing yet.** A feature disabled by default,
one gated behind a rosparam the operator must flip, or work that was cut from the release and
will land next — all of it is real, none of it changes behaviour on upgrade. Written as `info`
it reads like an upgrade step; written as `success` it implies the operator already has it.
Include the switch that turns it on (`/TE/<param>`, a UI toggle) so the panel is actionable
rather than trivia. Omit it entirely when the release has no such items.

Reserve `error` for a known-broken item shipping in the release (a regression accepted at the
cut, a feature disabled late). If there is none, do not use it — an `error` panel on a healthy
release trains operators to ignore red.

**`panel-custom` is allowed** where a section wants its own identity rather than one of the five
semantics — v3.3 uses one on Critical Changes
(`data-type="panel-custom" data-icon=":rainbow:" data-color="#E6FCFF"`). Pick `data-color` from
the supported background palette only; an off-palette hex is dropped.

### Ad hoc sections — ask, never generate

**Recommendations for Operators** and **Test and Validation Results** are written fresh for
every release by the release owner and the test team. They are not derivable from PRs, and a
plausible-looking invention is worse here than an empty heading:

- **Recommendations for Operators** is per-container-type operating advice — which grasp mode
  suits which load, which SKU switches to set for fixed-SKU versus mixed-SKU containers, on-ramp
  dimension requirements and their diagram. It reflects what the field learned, not what the
  code does.
- **Test and Validation Results** is measured data: goal versus measured **CPH** and **CPI** per
  test container, the run names behind each figure, and a pass mark. **Never fabricate a number,
  a run name, or a pass mark.** Ship the section with its table skeleton and a visible
  placeholder, and ask the release owner to fill it — an invented CPH figure is a claim about a
  robot nobody measured.

Emit both headings every time, with their panel and, for §4, the empty table skeleton
(`Container | Goal | Measured | Runs | Pass`). Then **ask the user** for the content before
creating the page, and say plainly in the draft which sections are awaiting human input.

**Provenance line** — before the first heading, in an **`info` panel**: the version, whether it
is released or still a candidate and on what date, the branches the notes were generated from,
the cut date, and the sw config name. Once the release ships, say so here — a page that still
reads "frozen release-candidate" after the tags exist tells an operator nothing about whether
they can install it.

1. **Upgrade Instructions** — a numbered list of the commands in the order they are run
   (`duckctl sw reset` → `duckctl sw install vX.Y.0 -y` → any credential/migration step →
   `duckctl up`). Directly beneath, a **`warning` panel headed "One-Time Steps"** carrying
   everything that must happen or the duck will not start: a config-schema migration, a new
   required key, credentials a new service needs. Number those too — they are a procedure, not
   a list of facts.
2. **New Features for Operators** — open with one line on what the release was *for*
   ("v3.3 focuses on improving CPI relative to CPH across customer deployments"), then the
   ranked features, most notable first, in a **`success` panel**. Each item:
   - a **short bold headline** naming the change, tagged `(new)` for a capability,
     `(platform)` for hardware/interface changes, or `Fix —` for a bugfix;
   - one or two plain sentences on what changed and what the operator will notice — outcomes,
     not mechanism ("no more unloading boxes from the middle of the wall", not "the ranking
     comparator now sorts against the wall plane");
   - an **IssueTracking link** (`[IT-<n>](https://contoro.atlassian.net/browse/IT-<n>)`) whenever
     the item's commits reference one (Step 1 harvest). Field-incident fixes with an IT ticket
     rank above refactors.
   Where a feature introduces operator-facing **settings**, put them in a **table above the
   `success` panel, one column per switch** — the v3.3 page uses three columns for the three SKU
   switches, with the **screenshot in the top row and its description beneath**. Each description
   says what the switch does, what turning it off means, and a **Suggested:** value with the
   container type it suits. Screenshots go **inside that table**, uploaded as page attachments and
   referenced as media — never a local path. Omit the table when the release adds no settings.
   Close the `success` panel with a one-line "Also in this release:" sweeping up the rest.
3. **Recommendations for Operators** — **`info` panel. Ad hoc: ask, do not generate.**
4. **Test and Validation Results** — **table + `note` panel. Ad hoc: ask, do not generate.**
5. **Silent Changes** — a **`warning` panel** for behaviour that changed with no switch, no
   error and nothing in the UI to reveal it: a retuned default, a new clamp, a heuristic that
   now refuses something it used to accept. These are the changes that generate "the robot used
   to do X" reports weeks later, and they are exactly what a PR-derived list buries. Omit the
   section if the release genuinely has none.
6. **Critical Changes** — a bullet list of must-know operator/config changes (breaking changes,
   new required settings, hardware-revision gating) in a **`custom` panel**:
   `data-type="panel-custom" data-icon=":rainbow:" data-color="#E6FCFF"`. That is the house style
   on this section — it reads as "read this" without competing with the `warning` panels above it.
   One panel around the whole list, not one per bullet.
7. **Detailed Changes** — `| Repo | Authors | Changes | PRs |` — **not in a panel**, tables are
   rejected there (Step 3):
   - Group related PRs across repos into one **semantic row** with a human-readable **Changes**
     description — one feature/fix per row, not one PR per row.
   - **Authors:** deduped display names across the row's PRs.
   - **PRs:** grouped by repo, `<RepoDisplayName> [#N](url), [#N](url); <OtherRepo> [#N](url)`.
   - Repo display names: Task Executor, Common, Process Orchestrator, Perception, Contoro Utils,
     HAL, Teleop, Debugger, Operator UI, Kuka, WS.
8. **Change log of this page** — plain paragraphs, no panel: what was added after the initial
   draft, what was added at the RC freeze, and what was folded in later, each with its PR links.
   This is how a reader tells whether the page kept pace with the release.
9. **Sample Configuration** — a reference hardware-config block. Open a **`warning` panel** with
   the caveat *"Use this as a reference. Do not copy-paste this text into a duck without verifying
   every value."*, name anything the schema changed this release (a new required key, a promoted
   field), and **put the YAML inside that same panel** so the caveat cannot be scrolled past.
   **Include it in full even on a patch** that changes no config — the v3.3 page carries the whole
   block, and linking to another page instead breaks the pattern a reader expects.
   Note: a `<pre>` code block does **not** survive the round-trip — Confluence flattens it to
   paragraphs inside the panel. The content is preserved, the monospace framing is not; do not
   "fix" it by re-authoring on a later edit.

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
   - space key `Software1`, title `vX.Y Release Notes <Mon D, YYYY>`, **`contentFormat: html`**,
     status draft.
   - Reference the **v3.3 page** (`getConfluencePage` 1416167594) for structure, section order,
     panel use and tone. Fetch it as `contentFormat: html` — a markdown fetch silently drops
     every panel div, so the page looks flat and you will copy the wrong shape.
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
- **New Features for Operators is ranked and evidence-based:** items come straight from the
  Detailed Changes table, lead with a short bold headline and an operator-visible outcome, and
  cite an `IT-<n>` ticket whenever the commits reference one. Never fabricate an IT number —
  link only tickets found in Step 1's harvest.
- **Never generate Recommendations for Operators or Test and Validation Results.** Both are
  written per release by the release owner and the test team. Emit the headings, the panel and
  the empty table skeleton, then ask. A fabricated CPH/CPI figure is a claim about a robot
  nobody measured.
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

---
description: Generate the Confluence release notes for a release line — "vX.Y Release Notes", a short operator summary kept current through hotfixes, plus one child page per version ("vX.Y.0 Release Notes" with the PR-level change table, behaviour changes and sample config; "vX.Y.Z Release Notes <date>" per patch) — aggregated across all product repos, with placeholders for the human-written Recommendations and Test/Validation sections.
allowed-tools: Bash(git *), Bash(gh *), Bash(duckctl *), Bash(cd *), Bash(ls *), Bash(for *), Bash(grep *), Bash(cat *), Bash(find *), Bash(pwd *), Bash(test *), Bash(echo *), Read, Glob
argument-hint: "[version] [sync|update] [--jira | --confluence]"
---

## Context

- Current directory: !`pwd`
- Repos dir env: !`printenv CONTORO_REPOS_DIR || echo "<unset>"`
- Current software version: !`duckctl sw version 2>/dev/null || echo "<duckctl unavailable>"`
- gh on PATH: !`command -v gh >/dev/null 2>&1 && gh --version | head -1 || echo "<gh missing>"`
- Arguments: $ARGUMENTS — optional `[version]` (e.g. `v3.2.0`; defaults to the current RC), optional op `sync` (alias `update`), optional target `--jira` / `--confluence` (default both).

## What this does

Generate a release line's notes as **a summary page plus one child page per version**, modelled on v3.4
(<https://contoro.atlassian.net/wiki/spaces/Software1/pages/1597669385>, the release owner's own
edit of the generated page):

| Page | Audience | Holds |
|---|---|---|
| **`vX.Y Release Notes`** (parent) | operators | the summary: how to upgrade, the high-level new features, recommendations, test results, technical changes, and a **Release History** row per version. Short, and **kept current through every hotfix** (`vX.Y.1`, `vX.Y.2`, …) — it describes the line, not one cut. |
| **`vX.Y.0 Release Notes`** (child of the notes page) | engineers | the minor release in detail: provenance, Behaviour Changes, the PR-level **Detailed Changes** table, the page change log, and the **Sample Configuration**. |
| **`vX.Y.Z Release Notes <Mon D, YYYY>`** (child, one per patch) | engineers + field | one patch in detail: what it fixes and why, upgrade steps, test results for the fix, silent/critical changes, its Detailed Changes rows. Example: [v3.4.1](https://contoro.atlassian.net/wiki/spaces/Software1/pages/1611595847). |

**A patch is split across two pages.** The headline — one bold line plus one sentence, the
ticket, and a link — goes on the summary page (feature list and Release History row). Everything
else about the patch — mechanism, test evidence, silent changes, PRs — goes on its own
`vX.Y.Z` page. Never paste the patch page's explanation into the summary.

**The operator page is a summary, not a changelog.** It says what an operator will see, use or
must do, in their words. Anything an operator would not act on — PR numbers, internal
mechanisms, refactors, CI — lives on the per-version pages. When in doubt, it goes there.

The v3.3 page (<https://contoro.atlassian.net/wiki/spaces/Software1/pages/1416167594>) is the
older single-page shape that mixed both audiences — do not copy its layout, only its tone.

It aggregates every merged PR across all product repos in the RC — from the previous release
line up to the `release-candidate/vX.Y.Z` branches — then **fully writes** both pages, leaving
Recommendations for Operators and Test and Validation Results for a human. It is read-only until
the page writes, which are **confirmed**. New pages are created as **drafts**; a page that
already exists keeps its status.

## Modes

| Invocation | Does |
|---|---|
| `/release-notes [version]` | **Create** — the full flow below: gather, synthesize, create both draft pages (Steps 0–3) |
| `/release-notes [version] sync` (or `update`) | **Sync** existing pages — re-gather and refresh both in place, plus the Jira side (Step 4). Run it after every hotfix. |

If the user hands you a page URL, or `vX.Y Release Notes` already exists (often a copy of the
previous release's page), that page is the target: run **sync** against it, never create a
second one.

`sync` takes a target flag, like `/release-scope`: default is **both**.
- `--confluence` — refresh the two release-notes pages only.
- `--jira` — Jira only: link the release's merged PRs into the SRT feature tickets.

One preview covers every pending write (Jira and Confluence), and one OK applies it. "Go ahead"
given before the preview existed is not that OK.

**Naming reminder** (see `/release-cut`): the git branches are
`release-candidate/vX.Y.Z`; the `duckctl sw` config is `vX.Y.Zrc`. This command reads the
branches.

## Workspace detection

Operates on the **repos root**, not a single git repo.

1. Resolve the repos root: `$CONTORO_REPOS_DIR` if set, else `~/repos`.
2. It must contain `.unloader_repos` (the manifest repo). If not, **stop** and ask for the root.
3. `duckctl` is optional. Without it, resolve the baseline from the manifest directly:
   `git -C <repos-root>/.unloader_repos show origin/<baseline>:cpc.repos` gives each repo's
   pinned `version:`.
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

### Step 2 — Synthesize the two page bodies

**Headings sit inside their panel.** Each section on the operator page opens with a coloured
panel holding only its `<h3>`, and the content follows below it, outside the panel:
`<div data-type="panel-success"><h3>New Features for Operators</h3></div><p>…</p><table>…</table>`.
The panel colour labels the section; the content stays free to hold tables and screenshots,
which a panel cannot. Use `<h3>` for every section heading on both pages.

**Icons are part of the house style.** Neutral sections use a `panel-custom` heading with an
emoji icon and the light-blue `#DEEBFF` background; only the sections that carry a warning or a
gain keep a semantic panel colour. The icons and colours in the Page 1 table are the release
owner's choices — reproduce them exactly:

```html
<div data-type="panel-custom" data-icon=":arrow_right:" data-color="#DEEBFF"><h3>Installation Instructions</h3></div>
<div data-type="panel-custom" data-icon=":duck:" data-color="#DEEBFF"><h3>Recommendations for Operators</h3></div>
```

Panels are semantic, and the colour is the first thing an operator sees: `info` = neutral
context and mechanical steps, `warning` = will break the robot or the upgrade, `success` = what
the operator gains, `note` = shipped but not active yet, `error` only for something known-broken
that ships anyway (never on a healthy release; it trains operators to ignore red).
`panel-custom` is allowed where a section wants its own identity; pick `data-color` from the
supported palette only (an off-palette hex is dropped).

#### Page 1 — `vX.Y Release Notes` (operators)

Element order, as on the v3.4 page. Reproduce it.

| # | Section | Shape | Source |
|---|---------|-------|--------|
| — | *(no heading)* | `info` panel — current-version status line | generated |
| — | Supported Hardware | `panel-custom` heading `:wrench:` `#DEEBFF`; table `Component \| <versions> \| Notes`; one check-your-config line; one italic caveat line | generated from code, see below |
| 1 | Installation Instructions | `panel-custom` heading `:arrow_right:` `#DEEBFF`; `duckctl --version` code block; numbered command list | generated |
| 2 | One-Time Steps | `warning` heading panel; numbered list | generated |
| 3 | New Features for Operators | `success` heading panel; one intro line; settings tables (screenshots inside); `success` panel with the ranked list; optional `note` panel | generated |
| 4 | **Recommendations for Operators** | `panel-custom` heading `:duck:` `#DEEBFF`; plain paragraphs and supporting image(s), no body panel | **ad hoc — ask, never invent** |
| 5 | **Test and Validation Results** | `panel-custom` heading `:test_tube:` `#DEEBFF`; one plain paragraph, then the table, no body panel | **ad hoc — ask, never invent** |
| 6 | Technical Changes | `panel-custom` heading `:gear:` `#E6FCFF`; bullet list | generated |
| 7 | Release History | `panel-custom` heading `:calendar_spiral:` `#DEEBFF`; table `Version \| Date \| What changed for operators`; links to every per-version page | generated, one row per version |

- **Status line** — current version, whether it is released or still a candidate and as of when,
  that the page is updated with every hotfix, and links to the per-version pages. A patch still
  in RC is named as such ("**v3.4.1** is in release candidate (`v3.4.1rc`)"). Once a version
  ships, say so here: "release candidate" after the tags exist tells an operator nothing about
  whether they can install it.
  Released form: "**Current version: vX.Y.Z** released on <date>." — and the Release History row
  carries the same date.
- **Supported Hardware** — the hardware revisions the line runs on, so an operator can tell
  whether a robot can take the release without reading every page (asked for by field, Oct 2026).
  Rows: Gripper, Camera mount, Mobile base, Conveyor (the four `hardware.revision` fields).
  One revision column per run of versions with identical support (`v3.4.0, v3.4.1`); split the
  column when a patch changes support. Notes: when a revision first became supported, partial
  support (e.g. calibration covers only some grippers), fitting rules, and named non-support for
  revisions people ask about.
  **Derive it from the code at the release tags, never from memory or the fleet configs** —
  the schema accepts any string, so support is whatever the code branches on. Read with
  `git grep`/`git show <tag>:` (each repo at the tag the release config pins):
  - Kuka `kr_70_r2100/urdf/kr_70_r2100.xacro` — `gripper_revs` (fatal otherwise),
    `camera_mount_specific_revs`, `conveyor_mesh_revs`, mobile-base meshes;
    `config/hardware_compatibility.yaml` — conveyor ↔ base fitting rules.
  - Common `utils/common_motion_tools/constants.py` `CONVEYOR_DECK_Z_M` (KeyError otherwise);
    `common_motion_tools.py` per-gripper branches; `commander/bundles/cams_ml.py` camera mount.
  - HAL `HalSplit/revE_Driver/reve_gripper_service.py`, `hw_configuration/modbus_config.py`,
    `config.py` (mobile base).
  - Perception `config/calibration/sensor_config.yaml` `feasible_hw_pairs`, `scripts/run_cali.py`,
    `calibration/update_lidar_transform.py` (vert-lidar TFs per base).
  - Contoro Utils `config.py` — gripper / camera-mount majors are pydantic `Literal`s.
  List a revision as supported only when URDF, motion and HAL all handle it; put partial
  support in Notes. Caveat line: supported = model, motion parameters and drivers exist, not
  field-tested in every combination. Ask the release owner if the code is ambiguous.
- **Installation Instructions** — the commands in run order (`duckctl sw reset` → `duckctl sw install
  vX.Y.Z -y` → verify migration / required keys → `duckctl up`), with the minimum duckctl
  version above them when the release needs one.
- **One-Time Steps** — everything that must happen or the duck will not start or will lose a
  capability: a config-schema migration, a new required key (`device_id`), credentials, a cloud
  deploy that must ship with the rollout. Numbered — a procedure, not a list of facts.
- **New Features for Operators** — this is the section the page exists for.
  - **Intro line:** what the release does for an operator and which new controls they get
    ("v3.4 keeps the robot unloading with fewer operator interventions, and gives operators three
    new controls: …"). Name the controls; no `code` formatting for version numbers.
  - **Settings tables:** every operator-facing control (UI button, toggle, switch) gets a column,
    two columns per table, **screenshot in the header row above the control's name, description
    below**. Each description says what it does, what off means, and a **Suggested:** value with
    the container type or situation it suits. Screenshots are uploaded by the release owner as
    page attachments — leave the slot with "*Screenshot to add*" and ask; never point at a local
    path.
  - **The ranked `success` list** — at most ~8 items, high-level, most operator-relevant first:
    new controls first (matching the tables), then autonomy and reliability fixes, then
    visibility. Each item is a **short bold headline** tagged `(new)` or `Fix —`, one or two plain
    sentences on what the operator will see or do — outcomes, not mechanism ("the robot rescans
    from where it stands", not "PO consumes `/rescan_requested`") — and an `IT-<n>` / `SRT-<n>`
    link when one exists. Scope limits go in the headline ("automovecorr ducks only"). No
    "Also in this release" sweep: what doesn't make the list belongs on the version page.
  - **`note` panel** for capability that ships but does nothing until configured or until
    something else lands (hardware support needing a config flag, events the dashboard doesn't
    show yet). Name the switch that turns it on. Omit it when empty.
- **Technical Changes** — the short list a field engineer must know: schema migrations, renamed
  or removed parameters, required keys, interface/service changes that forbid mixing versions,
  hardware-revision gating. One bullet each, no PR numbers.
- **Release History** — one row per version, oldest first (as the v3.4 page has it). On a hotfix,
  add its row — what an operator will notice, in **one sentence**, the ticket, and a link to its
  `vX.Y.Z` page; mark it "(release candidate)" until tagged — and update the status line. If the
  hotfix changes what an operator sees, add one item to the feature list headlined
  `Fix (vX.Y.Z) — …` with one sentence and the ticket; the mechanism stays on the patch page.

#### Page 2 — `vX.Y.0 Release Notes` (engineers), child of page 1

| # | Section (`<h3>`) | Shape | Source |
|---|------------------|-------|--------|
| — | *(no heading)* | `info` panel — provenance and a link back to the notes page | generated |
| 1 | Behaviour Changes | `warning` panel | generated |
| 2 | Detailed Changes | table, no panel | generated |
| 3 | Change log of this page | plain paragraphs | generated |
| 4 | Sample Configuration | `warning` panel with the YAML inside it | generated |

- **Provenance** — the version, the branches generated from, the baseline (previous release and
  each repo's pinned tag), the cut date, the sw config name.
- **Behaviour Changes** — behaviour that changed with no switch and nothing in the UI to reveal
  it: a retuned default, a new clamp, a heuristic that now refuses something it used to accept.
  These generate "the robot used to do X" reports weeks later. Omit when there are none.
- **Detailed Changes** — `| Repo | Authors | Changes | PRs |`, **not in a panel** (tables are
  illegal there):
  - Group related PRs across repos into one **semantic row** — one feature/fix per row.
  - **Authors:** deduped display names across the row's PRs.
  - **PRs:** grouped by repo, `<RepoDisplayName> [#N](url), [#N](url); <OtherRepo> [#N](url)`.
  - Repo display names: Task Executor, Common, Process Orchestrator, Perception, Contoro Utils,
    HAL, Teleop, Debugger, Operator UI, Kuka, WS.
  - Build/CI/test-only PRs go in one final "no robot behaviour change" row.
- **Change log of this page** — what was generated when, what landed on the RC after the cut,
  what was folded in later (each with PR numbers), and what Step 1b left out as already shipped.
  Hotfixes do not go here — each gets its own page (Page 3).
- **Sample Configuration** — a `warning` panel opening with *"Use this as a reference. Do not
  copy-paste this text into a duck without verifying every value."*, naming what the schema
  changed this release, with the full YAML inside the same panel as
  `<pre><code class="language-yaml">` (it round-trips as a code macro). A patch that changes no
  config links here instead of repeating it.

#### Page 3 — `vX.Y.Z Release Notes <Mon D, YYYY>` (one per patch), child of page 1

Element order, as on the v3.4.1 page:

| # | Section | Shape |
|---|---------|-------|
| — | *(no heading)* | `info` panel — "vX.Y.Z is a patch on top of vX.Y.(Z-1). It fixes …", the ticket, a link to the summary page; then status (release candidate / released on), branches, sw config, where the sample config lives; then a **Supported hardware** line ("unchanged from vX.Y.(Z-1)" plus the one-line list, or what changed) linking the summary table |
| 1 | Upgrade Instructions | `info` heading panel; numbered commands; bold **One-Time Steps** paragraph ("Coming from vX.Y.(Z-1): …"), including whether `--retag` is safe |
| 2 | New Features for Operators | `success` heading panel; numbered list, each fix with its full explanation and PR link |
| 3 | **Test and Validation Results** | `info` heading panel; table — **ad hoc, ask, never invent** |
| 4 | Silent Changes | `warning` heading panel; bullets — omit when none |
| 5 | Critical Changes | `panel-custom` `:rainbow:` `#E6FCFF` heading; bullets (say "no breaking changes" explicitly) |
| 6 | Detailed Changes | `info` heading panel; the Page 2 table; one line naming the repos that stay on the previous tag |

The title date is the release date; while in RC, use the cut date and re-date on tag.

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

Emit both headings every time, in their icon panels, with a one-line bold placeholder
paragraph ("**Awaiting input from the release owner.** …" / "**Awaiting input from the test
team.** …") and, for the results, the empty table skeleton (`Container | Goal | Measured | Runs |
Pass`) below that paragraph. Then **ask the user** for the content before
writing, and say plainly on the page which sections are awaiting human input. A page copied
from the previous release carries that release's recommendations and results — never keep them
as this release's without asking.

Render both drafts to the user for review.

### Step 3 — Create the Confluence pages (confirmed)

**Author the bodies as HTML, not markdown.** Markdown cannot express panels at all — it silently
produces a flat page, which looks like the panel instruction was ignored rather than
unsupported.

1. Show the rendered pages and **confirm** creation.
2. **Call `getContentFormatGuide` first** with `{ toolName: "createConfluencePage" }` (or
   `updateConfluencePage` when editing) and follow what it returns. It is the canonical source
   for the HTML dialect; the syntax below is a summary, and the guide wins where they disagree.
3. On approval, create as **drafts** in space `Software1`, `contentFormat: html`:
   - the notes page, title `vX.Y Release Notes`;
   - the version page, title `vX.Y.0 Release Notes` (or `vX.Y.Z Release Notes <Mon D, YYYY>` for
     a patch), **parent = the notes page**. Create the notes page first if it does not exist,
     then the child, then update the notes page's links with the child's real URL.
   - Read the v3.4 pages as `contentFormat: html` for structure and tone — a markdown fetch
     silently drops every panel div.
4. Read both pages back as HTML and check the panels, tables, media and code block survived.
   Return both URLs. **Never publish** a page this command created.
5. If the Atlassian integration is unavailable, write the notes to two local markdown files and
   hand back the paths — noting that panels are lost in that fallback.

#### Panel syntax

```html
<div data-type="panel-info"><p><strong>Current version: v3.4.0</strong>, release candidate…</p></div>
<div data-type="panel-warning"><h3>One-Time Steps</h3></div><ol><li>…</li></ol>
<div data-type="panel-success"><h3>New Features for Operators</h3></div><p>…</p><table>…</table>
<div data-type="panel-custom" data-icon=":gear:" data-color="#E6FCFF"><h3>Technical Changes</h3></div><ul><li>…</li></ul>
```

Types: `info`, `note`, `warning`, `success`, `error` (`tip` is accepted as `info`).

**A panel's children are restricted.** Legal: paragraphs, headings, bullet/ordered lists, code
blocks, rules. **Illegal: tables, expands, blockquotes, nested panels.** Two consequences that
will bite:

- **Tables live outside every panel** — the settings tables, the results table, Release History
  and Detailed Changes. That is why section headings sit in their own panel with the content
  below it.
- **A panel cannot hold another panel.**
- **Preserve hand-added media.** On an update, copy every `data-type="media"` node (its `data-id`
  and `data-collection`) verbatim from the page as read; never invent media IDs. Moving content
  to the other page drops its screenshots unless they are re-uploaded there — leave media on
  the page that owns it.

Do **not** emit Confluence storage XML (`<ac:structured-macro>`, `<ac:rich-text-body>`, CDATA)
to get a panel — it renders as visible raw text on the page. The `data-type` div above is the
supported form.

Panels do not nest inside markdown either: if you have an existing markdown page to convert,
rewrite the body as HTML rather than splicing HTML fragments into markdown.

### Step 4 — Sync the existing pages and Jira (`sync` / `update`)

Re-runnable at any point while the RC is open, after dispatch for late fixes, and **after every
hotfix** — that is what keeps the operator page current.

1. **Resolve and gather** exactly as Steps 0–1b (same range confirmation).
2. **Map PRs to features.** Read the release's Jira epic (`/release-scope`: project `SRT`, epic
   summary `vX.Y`, features = `parent = <epic>`, subtasks = `parent in (<features>)`) and each
   ticket's description. A PR belongs to a feature when the ticket's `## Pull requests` section
   (or a hand-written PR table) lists it; otherwise match on content as `/release-scope sync`
   does. Unmatched merged PRs stay unmatched — never force a mapping.
3. **Jira part** (skipped with `--confluence`) — follow `/release-scope`'s "Linking PRs" rules:
   add each newly matched **high-confidence** PR to its ticket's `## Pull requests` section with
   its current state; replace only that section; leave hand-written PR tables alone. Mark
   tickets owned by someone else **(owner: Name)** in the preview.
4. **Confluence part** (skipped with `--jira`):
   - Find the pages: title `vX.Y Release Notes*` in space `Software1` (CQL), and its children
     (list the notes page's descendants): `vX.Y.0 Release Notes` and one `vX.Y.Z Release Notes*`
     per patch. No notes page → offer create mode; never guess another page. No page for the
     version being synced → create it as a child (Page 2 or Page 3 shape). A legacy
     `vX.Y Release Details` child is renamed to `vX.Y.0 Release Notes`; say so in the preview.
     Read every page you will touch as `contentFormat: html`.
   - **Old single-page layout** (Detailed Changes, change log or sample config still on the
     notes page): move them to the details page as part of the sync, and say so in the preview.
   - **Version page** (the one for the version being synced): regenerate provenance, Behaviour /
     Silent Changes and Detailed Changes from the fresh gather (and the sample config on
     `vX.Y.0`); add a **Jira** column to Detailed Changes with the feature key from step 2 (blank
     when unmatched); on `vX.Y.0`, append a dated change-log paragraph. Other versions' pages
     are not touched.
   - **Notes page:** update the status line, the Instructions version, One-Time Steps and
     Technical Changes when the gather changes them; add the **Release History** row for a new
     version. Re-derive **Supported Hardware** at the new tags: unchanged → add the version to the
     existing column header; changed → split the column and say what changed in Notes. Touch the New Features list only when an operator-visible feature was added,
     removed or changed — propose the wording in the preview.
   - **The release owner edits the notes page directly** — wording, ordering, which features
     make the list, screenshots. Treat every difference from what this command last wrote as a
     hand edit: **carry it over verbatim**, including media nodes, and never "fix" it back. A
     feature the owner removed from the list stays removed (it is still on its version page). The ad hoc
     sections are always carried over.
   - Keep each page's status: a draft stays a draft; a published page is updated in place, with
     `versionMessage: "release-notes sync"`. Keep the titles.
5. **Preview** — one block:
   - Jira: per ticket, the PR lines being added.
   - Notes page: status/history changes, proposed New Features edits, changed upgrade or
     migration steps, and every hand-edited block being kept.
   - Version page: rows added / removed / changed in Detailed Changes, Behaviour Changes added or
     dropped, sample-config changes.
   - Unmatched merged PRs (no feature ticket), and features with no merged PR yet.
   - One question: apply all / apply some (which) / cancel.
6. On approval write Jira first, then the details page, then the notes page
   (`updateConfluencePage`, `contentFormat: html`, `getContentFormatGuide` once first), each
   with the `snapshotToken` from its read — a conflict means the owner edited meanwhile: re-read
   and merge, never overwrite. Return both page URLs and the tickets touched.

## Rules

- **Read-only until Step 3** (or the Step 4 write). Gathering and synthesis mutate nothing.
- **Confirm twice:** the resolved range (Step 0.5) and the rendered page before creating it
  (Step 3.1).
- **Never invent PR numbers, links, or authors** — every entry must trace to `gh`/`git` output
  from Step 1. If unsure, omit rather than guess.
- **Summary vs. version pages.** The notes page is an operator summary kept current through
  hotfixes — one line per patch; PR numbers, mechanisms, test evidence, refactors and CI go on
  the per-version page. When unsure which page something belongs on, it goes on the version page.
- **New Features for Operators is ranked, high-level and evidence-based:** at most ~8 items,
  new operator controls first, each a short bold headline plus an operator-visible outcome,
  citing an `IT-<n>` / `SRT-<n>` ticket whenever one exists. Never fabricate a ticket number —
  link only tickets found in Step 1's harvest or the PR bodies.
- **Never generate Recommendations for Operators or Test and Validation Results.** Both are
  written per release by the release owner and the test team. Emit the headings, the panel and
  the empty table skeleton, then ask. A fabricated CPH/CPI figure is a claim about a robot
  nobody measured.
- **Draft only.** Create new pages as drafts; never auto-publish. `sync` never changes a page's draft/published status — and writing to a published page is live, so say so before the OK.
- **`sync` never touches the ad hoc sections or hand edits** — they are carried over verbatim (media included) and listed in the preview.
- **HTML, not markdown.** The body is `contentFormat: html` because panels need it; call
  `getContentFormatGuide` before authoring. A page that came out flat and uncoloured means the
  format was wrong, not that the panels were unnecessary.
- **Panels are semantic, not decorative.** `warning` = will break the robot or the upgrade;
  `success` = what the operator gains; `info` = neutral context and mechanical steps; `note` =
  shipped but inactive (off by default, opt-in, deferred); `error` only for something
  known-broken that is shipping anyway. Never pick a type for contrast.
- **Never put a table in a panel** — tables are not legal panel children; headings go in the panel, content below.
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
| `/release-notes` | The operator Release Notes page + one child page per version (vX.Y.0, each patch); `sync` refreshes them (after every hotfix) and links PRs into the SRT feature tickets |
| `/release-blob` | Per-author feature blobs, for standup/Jira |

**Two names, always distinct:** the product-repo git **branch** is `release-candidate/vX.Y.Z`
(identical in every repo — cross-repo CI triggers on it, never rename it); the `duckctl sw`
config is `vX.Y.Zrc` for the RC and `vX.Y.Z` for the release.

---
description: Generate per-feature release-note "blobs" (.md) for one author's top 5–10 macro contributions in a release-candidate — clustered across all product repos, with real PR links.
allowed-tools: Bash(git *), Bash(gh *), Bash(duckctl *), Bash(cd *), Bash(ls *), Bash(for *), Bash(grep *), Bash(awk *), Bash(cat *), Bash(find *), Bash(pwd *), Bash(test *), Bash(echo *), Bash(xdg-open *), Read, Write, Glob
argument-hint: "[version] [author]"
---

## Context

- Current directory: !`pwd`
- Repos dir env: !`printenv CONTORO_REPOS_DIR || echo "<unset>"`
- Current software version: !`duckctl sw version 2>/dev/null || echo "<duckctl unavailable>"`
- Git author (default subject): !`git config user.name 2>/dev/null || echo "<unset>"`
- Arguments: $ARGUMENTS — optional `[version]` (e.g. `v3.2.0`) and `[author]` (display-name
  substring, e.g. `Stefano`). Defaults: current RC, and the invoking git user.

## What this does

For one **author**, mine a release-candidate across all product repos and produce **5–10
per-feature release-note "blobs"** — one Markdown file per macro feature the author led,
each with a summary, what-changed, PR links grouped by repo, and authors. This is the
per-contributor companion to `/release-notes` (which builds the whole-release page);
it reuses the same range resolution and PR gathering.

Output is a set of `.md` files (paste-ready for Jira/Confluence/standup) — it does **not**
publish anything.

**Naming reminder** (see `/release-cut`): git branches are `release-candidate/vX.Y.Z`;
the `duckctl sw` config is `vX.Y.Zrc`. This command reads the branches.

## Workspace detection

Operates on the **repos root**, not a single git repo.

1. Resolve the repos root: `$CONTORO_REPOS_DIR` if set, else `~/repos`.
2. It must contain `.unloader_repos` (the manifest repo). If not, **stop** and ask for the root.
3. `duckctl` must be on `PATH`. If missing, **stop**.
4. `gh` optional — used only to enrich author display names; `git log` is authoritative for
   PR numbers (squash-merge subjects carry `(#N)`).

## Steps

### Step 0 — Resolve version, author, and range (read-only)

1. **Target version** = `[version]` arg, else current RC (`duckctl sw version` minus a trailing
   `rc`, or the `release-candidate/*` branches present). RC branch per repo =
   `release-candidate/vX.Y.Z`; `git fetch origin` and verify it exists in every repo.
2. **Author** = `[author]` arg (display-name substring), else `git config user.name`. Confirm
   the resolved author string.
3. **Baseline** = the previous release line's final sw config (highest non-rc `vX.(Y-1).*` from
   `duckctl sw versions`); per-repo baseline ref via `duckctl sw ls <baseline>`. Confirm the
   baseline, accept an override.
4. Print the resolved range (`repo | baseline_ref | release-candidate/vX.Y.Z`) and the author,
   and **confirm before gathering**.

### Step 1 — Gather and attribute PRs (read-only)

For each repo, dump `git log --no-merges --format='%an%x09%s' <baseline_ref>..origin/release-candidate/<version>`.
For each commit extract: repo display name, PR number (trailing `(#N)` in the subject), author
(`%an`), subject. Write a TSV to the scratchpad.

- Map repo path → display name (Task Executor, Common, Process Orchestrator, Perception,
  Contoro Utils, HAL, Teleop, Debugger, Operator UI, Kuka, WS, Msgs) and → GitHub slug from
  `.unloader_repos/cpc.repos` `url:` fields (for PR links
  `https://github.com/contoroinc/<slug>/pull/<N>`).
- **Never invent PR numbers** — only emit what `git`/`gh` returned.

### Step 1.5 — Strip noise and already-shipped work

Apply **`/release-notes` Step 1b** verbatim — merge/sync/autosync/bot PRs, CI-only PRs, and
work already shipped in the previous line (detected by PR number against the previous minor's
RC branch and its `vX.(Y-1).*` tags). That is the canonical filter; do not re-derive it here.

Two things matter more for a blob than for the notes page:

- Re-announcing a prior-release feature under an author's name is worse than a stray line in a
  table — sanity-check that a known prior-release PR resolves to *already-shipped*.
- Report the split per repo (`range | already-shipped | new`) before clustering, so a wrong
  baseline shows up as an implausible ratio rather than a confident wrong blob.

### Step 2 — Filter to the author and cluster into macro features

1. Filter the surviving (new-only) TSV to the target author (`%an` substring match; account for
   name variants).
2. **Cluster** the author's PRs into **5–10 macro features** — semantic groups spanning repos
   (e.g. a goal-migration stack, an auto-recovery feature, a subsystem overhaul). Use conv-commit
   scopes, `v3.2/<feature>` branch tags, IT-/ticket refs, and subject similarity as signals.
3. **Rank** clusters by contribution weight (PR count + cross-repo breadth + feat vs. fix) and
   keep the top 5–10. Fold genuinely-small standalone PRs into the nearest feature; list any
   dropped singletons so nothing is silently lost.
4. For each cluster, note co-authored PRs (PRs in the feature not by the target author) as
   *related* rather than attributing them to the author.

### Step 3 — Write one blob per feature

For each feature, write `<NN>-<slug>-release-note.md` to the output directory (default: the
session scratchpad; accept an override) with this shape:

```markdown
# <Feature Title>

## Summary
<2–4 sentences: what it is and why it matters.>

## What changed
- <bullet per sub-area / repo>

## PRs
- **<Repo>:** [#N](https://github.com/contoroinc/<slug>/pull/N), ...
- ...
<optional: _Related (co-authored):_ <Repo> [#N](url) — <what> (<author>).>

## Authors
<Target author>[, co-authors if the feature is genuinely shared]
```

Keep each blob concise (match the tone of the whole-release page's change descriptions). Then
print the list of files written and offer to open them (`xdg-open`).

### Step 4 — Summary

Print a table: `# | Feature | repos | PR count | file`. Offer follow-ups: create Jira tickets
(one per blob) via the Atlassian integration, or fold the blobs into the `/release-notes`
page. Do neither without explicit approval.

## Rules

- **Read-only** through Steps 0–2; Step 3 only writes local `.md` files. No publishing.
- **Confirm** the resolved range + author before gathering (Step 0.4).
- **Never invent PR numbers, links, or authors** — every entry traces to Step 1 output.
- **Attribute honestly:** the author's line lists the target author; PRs in a feature by other
  people are marked *related / co-authored*, not claimed.
- **No silent drops:** when trimming to the top 5–10, list what was folded or omitted.
- **Isolate vs. the previous release (Step 1.5):** subtract PR numbers reachable from the prior
  minor's RC branch ∪ its tags before clustering — never re-announce a cherry-picked
  prior-release feature; reframe surviving prior-release banners as increments.
- **Reuse `/release-cut` naming** and `/release-notes` range logic.

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

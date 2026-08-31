# gh stack Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the eight `stack-*` slash commands to delegate all per-repo stacked-PR mechanics to the `gh stack` extension, keeping only the multi-repo orchestration that `gh stack` has no concept of.

**Architecture:** Each command is a markdown prompt that loops over repos in a workspace and shells out to `gh stack`. Cross-repo correlation of a logical step lives in a single `.stack-manifest.json` at the workspace root, because `gh stack`'s auto-generated branch names cannot carry that information. No shared helper scripts — the canonical manifest schema and `jq` snippets are defined once in `docs/stacked-pr-workflow.md` and referenced by every command.

**Tech Stack:** Markdown command prompts, bash, `jq`, `gh` 2.98.0, `gh-stack` v0.1.0, git.

**Spec:** `docs/superpowers/specs/2026-08-31-gh-stack-adoption-design.md`
**Measured CLI schema:** `docs/gh-stack-json-reference.md`

## Global Constraints

- Requires `gh` >= 2.90.0 and the `github/gh-stack` extension. Installed: gh 2.98.0, gh-stack v0.1.0.
- Every rewritten command MUST open with the guard block (below) and stop if `gh stack` is unavailable. **Never** fall back to hand-rolled git stacking — a silent fallback creates branches the manifest does not know about.
- Branch names come from `gh stack` auto-naming (`MM-DD-<slug>`). Commands MUST NOT pass explicit branch names to `gh stack add`.
- The manifest is written **only in multi-repo mode**. In single-repo mode `.git/gh-stack` is sufficient.
- `branches[].base` in `gh stack view --json` is a **commit SHA, not a branch name**. Derive parent relationships from array order, which is bottom-first.
- `branches[].pr` is **omitted** when no PR exists. Always guard with `// empty` or `?`.
- The manifest stores branches, never PR numbers. PR state is derived on demand.
- Preserve existing command names. Do not rename files.
- Repo keys in the manifest are directory names relative to the workspace root.

## Canonical blocks

These exact blocks are written into `docs/stacked-pr-workflow.md` by Task 1 and referenced by every later task. Copy them verbatim; do not paraphrase.

**Guard block:**

```bash
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is not installed."; exit 1; }
gh extension list 2>/dev/null | grep -q 'github/gh-stack' || {
  echo "ERROR: gh-stack not installed. Run: gh extension install github/gh-stack"
  exit 1
}
```

**Workspace and manifest resolution:**

```bash
if [ -d .git ]; then MODE=single; WS="$PWD"; else MODE=multi; WS="$PWD"; fi
MANIFEST="$WS/.stack-manifest.json"
repos() { for d in "$WS"/*/; do [ -d "$d/.git" ] && basename "$d"; done; }
```

**Manifest reads:**

```bash
# trunk branch for a repo
jq -r --arg r "$repo" '.trunk[$r] // empty' "$MANIFEST"
# branch recorded for step n in a repo (empty if repo skips the step)
jq -r --arg r "$repo" --argjson n "$n" \
  '.steps[] | select(.n==$n) | .branches[$r] // empty' "$MANIFEST"
# repos participating in step n
jq -r --argjson n "$n" '.steps[] | select(.n==$n) | .branches | keys[]' "$MANIFEST"
# highest step number so far (0 if none)
jq -r '[.steps[].n] | max // 0' "$MANIFEST"
```

**Manifest writes** (always via temp file, never in-place):

```bash
# create
jq -n --arg name "$name" --arg plan "$plan" --argjson trunk "$trunk_json" \
  '{version:1, name:$name, plan:$plan, trunk:$trunk, steps:[]}' > "$MANIFEST"

# record a branch for a step, creating the step if absent
jq --arg r "$repo" --arg b "$branch" --arg t "$title" --argjson n "$n" '
  if any(.steps[]; .n==$n)
  then .steps |= map(if .n==$n then .branches[$r] = $b else . end)
  else .steps += [{n:$n, title:$t, merged:false, branches:{($r):$b}}]
  end' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

# mark every step up to and including n as merged
jq --argjson n "$n" '.steps |= map(if .n<=$n then .merged=true else . end)' \
  "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

# rename a branch
jq --arg r "$repo" --arg old "$old" --arg new "$new" \
  '.steps |= map(if .branches[$r]==$old then .branches[$r]=$new else . end)' \
  "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

# drop a branch, discarding steps left with no repos
jq --arg r "$repo" --arg b "$b" '
  .steps |= map(if .branches[$r]==$b then del(.branches[$r]) else . end)
  | .steps |= map(select(.branches | length > 0))' \
  "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
```

## Test fixture

`gh stack init` works without a remote, so every task except Tasks 6 and 8 is verifiable locally. Referred to below as **the fixture**:

```bash
FIX=/tmp/claude-1000/-home-stefano-dot-claude/2bd4cc78-816b-46a9-bf46-b8384ed49f61/scratchpad/fixture
rm -rf "$FIX" && mkdir -p "$FIX"
for r in repo-alpha repo-beta; do
  mkdir -p "$FIX/$r" && cd "$FIX/$r"
  git init -q -b main && git config user.email t@e.st && git config user.name Test
  echo seed > seed.txt && git add -A && git commit -qm "seed"
done
cd "$FIX"
```

`repo-alpha` and `repo-beta` both use `main` as trunk. To exercise the mixed-trunk path, rename one: `git -C "$FIX/repo-beta" branch -m main develop`.

## File Structure

| File | Responsibility |
|---|---|
| `docs/stacked-pr-workflow.md` | Rewritten. Canonical manifest schema, guard block, jq snippets, migration guide, corrected command table. Single source of truth for the shared blocks. |
| `commands/stack-start.md` | **New.** `gh stack init` per repo; creates the manifest. |
| `commands/stack-commit.md` | Rewritten. Plan classification retained; mechanics become `gh stack add -Am`. |
| `commands/stack-status.md` | Rewritten. Aggregates `gh stack view --json` grouped by logical step. |
| `commands/stack-checkout.md` | Rewritten. Manifest-driven checkout plus `gh stack` navigation passthrough. |
| `commands/stack-create-pr.md` | Rewritten. `gh stack submit --auto --open` plus cross-repo PR body references. |
| `commands/stack-rebase.md` | Rewritten. `gh stack sync` with explicit conflict/divergence reporting. |
| `commands/stack-merge.md` | **New.** `gh stack merge` with preview and confirmation. |
| `commands/stack-modify.md` | **New.** Preconditions, TUI handoff, manifest reconciliation. |
| `commands/stack-create-summary.md` | Re-sourced from manifest + `--json`. |
| `commands/stack-create-diagram.md` | Re-sourced from manifest + `--json`. |
| `commands/stack-port.md` | Committed unchanged from `~/.claude/commands/`. |

---

### Task 1: Rewrite the workflow doc as the single source of truth

Everything else references this file, so it lands first.

**Files:**
- Modify: `docs/stacked-pr-workflow.md` (full rewrite)

**Interfaces:**
- Consumes: `docs/gh-stack-json-reference.md` for the measured JSON shape.
- Produces: named sections that later tasks cite by heading — `## Guard`, `## Workspace and manifest resolution`, `## Manifest schema`, `## Manifest reads`, `## Manifest writes`, `## Migration`.

- [ ] **Step 1: Replace the "How it works" and "Rules" sections**

Describe `gh stack`'s model, not the hand-rolled one: a stack is an ordered list of branches, bottom is closest to trunk, `submit` links them into a Stack object on github.com, and retargeting after merge is automatic via `sync`. Keep the "< 400 lines of diff per PR" rule — that is a review-practice rule `gh stack` does not supersede. Delete rules 2, 3, and 5 (branch naming, manual branching, manual retargeting), which `gh stack` now handles.

- [ ] **Step 2: Replace the "Workflow" section**

```markdown
### Starting a new stack
/stack-start <plan-or-name>

### Adding a step
/stack-commit            # classifies changes, runs gh stack add -Am per repo

### Opening PRs
/stack-create-pr         # gh stack submit --auto --open per repo

### After a PR merges
/stack-rebase            # gh stack sync: retargets, rebases, prunes

### Merging
/stack-merge step2       # gh stack merge, with preview and confirmation
```

- [ ] **Step 3: Add the shared blocks**

Copy the **Guard block**, **Workspace and manifest resolution**, **Manifest reads**, and **Manifest writes** blocks from this plan's "Canonical blocks" section verbatim, under those exact headings.

- [ ] **Step 4: Add the manifest schema section**

Copy the schema and field notes from the spec's "The manifest" section, including that PR numbers are deliberately not stored and that `base` is a SHA.

- [ ] **Step 5: Add the migration section**

```markdown
## Migrating in-flight `refactor/stepN-*` branches

Per repo, adopt existing branches bottom-first:

    gh stack init --base develop refactor/step1-foo refactor/step2-bar

Then record them in the manifest with the step-recording jq snippet, using
their existing numbers. Adopted branches keep their old names; only new
layers get auto-generated names. Migrate one repo at a time.
```

- [ ] **Step 6: Fix the command table**

The current table names four commands that do not exist. Replace with the eleven real ones: `/stack-start`, `/stack-commit`, `/stack-create-pr`, `/stack-rebase`, `/stack-status`, `/stack-checkout`, `/stack-merge`, `/stack-modify`, `/stack-create-summary`, `/stack-create-diagram`, `/stack-port`.

- [ ] **Step 7: Verify no stale references remain**

Run: `grep -nE '/commit-stack|/create-pr-stack|/rebase-stack|/checkout-latest-step|refactor/step|gh pr edit --base' docs/stacked-pr-workflow.md`
Expected: only matches inside the Migration section.

- [ ] **Step 8: Commit**

```bash
git add docs/stacked-pr-workflow.md
git commit -m "docs: rewrite stacked-PR workflow around gh stack"
```

---

### Task 2: `/stack-start`

**Files:**
- Create: `commands/stack-start.md`

**Interfaces:**
- Consumes: guard block, workspace resolution, manifest create snippet.
- Produces: `.stack-manifest.json` with `version`, `name`, `plan`, `trunk`, and `steps: []`; one initialized `gh stack` per participating repo.

- [ ] **Step 1: Write the frontmatter**

```markdown
---
description: Start a new stack across the repos a plan touches — gh stack init per repo, plus the workspace manifest.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *), Read, Write, Glob
---
```

- [ ] **Step 2: Write the Context and guard sections**

Include `!`pwd`` and `!`ls`` context lines, `$ARGUMENTS` as the plan path or stack name, then the guard block under a "## Preflight" heading, citing `docs/stacked-pr-workflow.md#guard`.

- [ ] **Step 3: Write the repo selection step**

Instruct: if `$ARGUMENTS` is a path to a plan file, read it and propose the repos it mentions; otherwise list all repos in the workspace. Always confirm the selection with the user before initializing — `gh stack init` mutates repos.

- [ ] **Step 4: Write the trunk detection and init step**

```bash
trunk=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) \
  || trunk=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$trunk" ] || trunk=$(for b in develop main master; do
    git show-ref -q --verify "refs/heads/$b" && echo "$b" && break; done)
gh stack init --base "$trunk"
```

Note that `gh stack init` with no branch argument is interactive; pass a first branch name derived from the stack name (e.g. `<name>-base`) to keep it non-interactive.

- [ ] **Step 5: Write the manifest creation step**

Build `$trunk_json` as `{"repo-alpha":"main","repo-beta":"develop"}` from the per-repo detection, then use the manifest create snippet.

- [ ] **Step 6: Write the guard against clobbering**

If `.stack-manifest.json` already exists, show its `name` and step count and require explicit confirmation before overwriting. Losing it loses all cross-repo correlation.

- [ ] **Step 7: Verify against the fixture**

Build the fixture, rename `repo-beta`'s trunk to `develop`, run the command's steps by hand, then:

Run: `jq . "$FIX/.stack-manifest.json"`
Expected: `version: 1`, `trunk` = `{"repo-alpha":"main","repo-beta":"develop"}`, `steps: []`.
Run: `git -C "$FIX/repo-alpha" branch --list`
Expected: trunk plus one new stack branch.

- [ ] **Step 8: Commit**

```bash
git add commands/stack-start.md
git commit -m "feat: add /stack-start for gh stack initialization"
```

---

### Task 3: `/stack-commit`

**Files:**
- Modify: `commands/stack-commit.md` (rewrite the mechanics, keep the classification logic)

**Interfaces:**
- Consumes: manifest reads (highest step, trunk), manifest write (record a branch).
- Produces: a new layer or a commit on the current layer per repo, and a manifest step entry recording each repo's auto-generated branch name.

- [ ] **Step 1: Preserve the classification section**

Keep the existing "read the plan, decide which step these changes belong to" logic verbatim from the current file. That reasoning is the command's value and `gh stack` does not replace it. Only the git mechanics below it change.

- [ ] **Step 2: Replace branch creation with `gh stack add`**

```bash
# New step: let gh stack name the branch
gh stack add -Am "$message"
# Existing step: plain commit on the current layer
git add -A && git commit -m "$message"
```

State explicitly: **never** pass a branch name to `gh stack add`, and **never** use `gh stack add` for an existing step — it would create a spurious layer.

- [ ] **Step 3: Handle the no-prior-commits warning**

Document that immediately after `/stack-start` the first `gh stack add -Am` commits to the existing branch instead of creating a layer, printing `Branch <x> has no prior commits — adding your commit here instead of creating a new branch`. This is expected, not an error; the manifest still records that branch as step 1.

- [ ] **Step 4: Read back the branch name**

```bash
branch=$(gh stack view --json | jq -r '.currentBranch')
```

- [ ] **Step 5: Record in the manifest**

Use the record-a-branch snippet with `$n` = the classified step number and `$title` = the step title from the plan.

- [ ] **Step 6: Verify against the fixture**

From a fixture with `/stack-start` already run, make a change in `repo-alpha` only, run the command's steps with message `Add widget`, then:

Run: `jq '.steps' "$FIX/.stack-manifest.json"`
Expected: one step, `branches` containing only `repo-alpha`.

**Note on the expected branch name.** The first commit after `/stack-start` is
the no-prior-commits case documented in Step 3: it lands on the seed branch and
keeps the seed name, so the recorded branch is `<name>-base`, **not**
`MM-DD-add_widget`. To exercise auto-naming, add a genuine second layer and
confirm that one matches `MM-DD-<slug>`. Verify both.
Run: `jq -r '.steps[0].branches | keys | length' "$FIX/.stack-manifest.json"`
Expected: `1` — repo-beta absent, confirming a step can touch a subset of repos.

- [ ] **Step 7: Commit**

```bash
git add commands/stack-commit.md
git commit -m "feat: rewrite /stack-commit on gh stack add"
```

---

### Task 4: `/stack-status`

**Files:**
- Modify: `commands/stack-status.md` (rewrite)

**Interfaces:**
- Consumes: manifest reads; `gh stack view --json` per repo.
- Produces: a dashboard grouped by logical step. No writes except the confirmed reconstruction path.

- [ ] **Step 1: Replace branch discovery**

Delete the `git branch --list '*/step*'` globbing. Replace with, per repo:

```bash
gh stack view --json 2>/dev/null
```

Exit code 2 means no stack in that repo — report it as "no stack" rather than an error.

- [ ] **Step 2: Write the join logic**

For each step in the manifest, for each repo in `steps[].branches`, find the matching entry in that repo's `branches[]` by `name` and read `isMerged`, `isQueued`, `needsRebase`, and `pr.number` / `pr.state` when present.

- [ ] **Step 3: Handle the omitted `pr` field**

```bash
jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.number // "—"'
```

Never assume `pr` exists; a branch that has not been submitted has no `pr` key at all.

- [ ] **Step 4: Write the output format**

```
Step 2 — Extract gripper class
  unloading_robot_ws  08-31-gripper_class   PR #412 OPEN    ⚠ needs rebase
  contoro_utils       08-31-gripper_types   PR #77  MERGED
  cloud-platform      —                     (not in this step)
```

Group by step, list every workspace repo, mark non-participating repos explicitly.

- [ ] **Step 5: Write the missing-manifest fallback**

If `.stack-manifest.json` is absent, reconstruct positionally — layer index N in each repo becomes step N — display the guess, state plainly that it is a guess that will be wrong if any repo skipped a step, and ask the user to confirm before writing the manifest. Never write it silently.

- [ ] **Step 6: Verify against the fixture**

With a fixture where `repo-alpha` has two layers and `repo-beta` one:

Run the command's steps.
Expected: two step groups; `repo-beta` shown as not participating in step 2; no crash on the absent `pr` field.
Then `rm "$FIX/.stack-manifest.json"` and re-run.
Expected: a reconstruction offer, and the file still absent until confirmed.

- [ ] **Step 7: Commit**

```bash
git add commands/stack-status.md
git commit -m "feat: rewrite /stack-status on gh stack view --json"
```

---

### Task 5: `/stack-checkout`

**Files:**
- Modify: `commands/stack-checkout.md` (rewrite)

**Interfaces:**
- Consumes: manifest read (branch for step n in repo).
- Produces: each participating repo checked out to its recorded branch; non-participating repos untouched and reported.

- [ ] **Step 1: Replace the argument table**

```markdown
| Argument | Behavior |
|---|---|
| `stepN` | Check out the branch the manifest records for step N in each participating repo |
| `top` / `bottom` | `gh stack top` / `gh stack bottom` in every repo with a stack |
| `up [n]` / `down [n]` | `gh stack up [n]` / `gh stack down [n]` in every repo with a stack |
| `trunk` | `gh stack trunk` in every repo |
| (none) | Defaults to `top` |
```

Delete the `base`/`latest` arguments and the `*/stepN*` globbing — branch names no longer encode step numbers.

- [ ] **Step 2: Write the stepN path**

```bash
branch=$(jq -r --arg r "$repo" --argjson n "$n" \
  '.steps[] | select(.n==$n) | .branches[$r] // empty' "$MANIFEST")
if [ -z "$branch" ]; then
  echo "$repo: not part of step $n — leaving on $(git -C "$repo" branch --show-current)"
else
  git -C "$repo" checkout "$branch"
fi
```

- [ ] **Step 3: Write the dirty-tree check**

Before checking out, run `git -C "$repo" status --porcelain`. If non-empty, skip that repo and report it rather than letting checkout fail or carry changes across branches.

- [ ] **Step 4: Verify against the fixture**

Run: the command with `step1`, in a fixture where only `repo-alpha` participates in step 1.
Expected: `repo-alpha` on its step-1 branch; `repo-beta` reported as not participating and left where it was.
Then dirty `repo-alpha` with `echo x >> seed.txt` and re-run.
Expected: `repo-alpha` skipped with a dirty-tree message, not a failed checkout.

- [ ] **Step 5: Commit**

```bash
git add commands/stack-checkout.md
git commit -m "feat: rewrite /stack-checkout on the manifest and gh stack navigation"
```

---

### Task 6: `/stack-create-pr`

Needs a real GitHub remote; not fixture-verifiable.

**Files:**
- Modify: `commands/stack-create-pr.md` (rewrite)

**Semantic limit (confirmed against `gh stack submit --help`):** submit has no
branch- or step-targeting flag; it pushes every branch in the repo's stack. A
`stepN` argument selects which *repos* to submit in, not which layer. Submitting
a repo submits its whole local stack.

**Interfaces:**
- Consumes: manifest read (repos in step n).
- Produces: PRs on GitHub, a Stack object per repo, and a cross-repo reference block in each PR body.

- [ ] **Step 1: Delete the retarget mode**

Remove the `retarget` argument and all `gh pr edit --base` logic. Replace with a line pointing at `/stack-rebase`, which retargets via `gh stack sync`.

- [ ] **Step 2: Replace PR creation**

```bash
gh stack submit --auto --open
```

State why both flags are needed: `--auto` skips the interactive editor, and without `--open` the extension creates drafts.

- [ ] **Step 3: Write the cross-repo reference step**

After submitting in every repo, collect `pr.url` per repo per step, then append to each PR body:

```markdown
---
Part of a multi-repo stack:
- unloading_robot_ws: https://github.com/contoroinc/unloading_robot_ws/pull/412
- contoro_utils: https://github.com/contoroinc/contoro_utils/pull/77
```

Explain that GitHub's Stack object is per-repo and cannot express this, which is why the body is edited.

- [ ] **Step 4: Write the preview and confirmation**

`submit` is outward-facing. List the branches and target repos and require confirmation before the first `gh stack submit`.

- [ ] **Step 5: Verify on a throwaway remote**

Create one private throwaway repo (confirm with the user first — this creates something on GitHub), push a two-layer stack, run the command.
Expected: two PRs, the second based on the first, both non-draft, both bodies carrying the reference block.
Confirm the `pr` object's real keys against `docs/gh-stack-json-reference.md` and correct that file if `number`/`state`/`url` differ.

- [ ] **Step 6: Commit**

```bash
git add commands/stack-create-pr.md docs/gh-stack-json-reference.md
git commit -m "feat: rewrite /stack-create-pr on gh stack submit"
```

---

### Task 7: `/stack-rebase`

**Files:**
- Modify: `commands/stack-rebase.md` (rewrite)

**Interfaces:**
- Consumes: manifest reads; manifest drop-a-branch snippet for pruned branches.
- Produces: synced stacks; per-repo status including partial failures.

- [ ] **Step 1: Replace the cascading rebase loop**

Delete the hand-rolled per-branch `git rebase` chain. Replace with, per repo:

```bash
gh stack sync --prune
```

- [ ] **Step 2: Write the conflict path**

Exit code 3 means a rebase conflict. The command must stop for that repo, print the conflicted files, and tell the user to resolve, `git add`, then run `gh stack rebase --continue` — or `gh stack rebase --abort` to restore. It MUST NOT attempt automatic resolution.

- [ ] **Step 3: Write the divergence path**

In a non-interactive terminal a diverged local/remote stack aborts the sync with exit 0 and nothing pushed. Detect this from the output and report it as a real failure for that repo, not a success.

- [ ] **Step 4: Continue across repos**

A failure in one repo must not abort the loop. Sync every repo, then print a per-repo summary of synced / conflicted / diverged.

- [ ] **Step 5: Prune the manifest**

For each branch `--prune` deleted, apply the drop-a-branch snippet so the manifest does not keep pointing at deleted branches.

- [ ] **Step 6: Verify against the fixture**

Add a commit to `repo-alpha`'s trunk, then run the command's steps.
Expected: layers rebased onto the new trunk tip, per-repo summary printed, `repo-beta` reported as having nothing to do.
Then create a deliberate conflict and re-run.
Expected: conflict reported with the resolve instructions, the loop still reaching `repo-beta`.

- [ ] **Step 7: Commit**

```bash
git add commands/stack-rebase.md
git commit -m "feat: rewrite /stack-rebase on gh stack sync"
```

---

### Task 8: `/stack-merge`

Needs a real GitHub remote; not fixture-verifiable. This is the only destructive command.

**Files:**
- Create: `commands/stack-merge.md`

**Interfaces:**
- Consumes: manifest read (branch for step n); `gh stack view --json` for PR numbers.
- Produces: merged PRs; manifest steps marked merged.

- [ ] **Step 1: Write the frontmatter**

```markdown
---
description: Merge a stack up to a chosen step across repos, with preview and confirmation.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *), Read
---
```

- [ ] **Step 2: Resolve step to PR per repo**

```bash
branch=$(jq -r --arg r "$repo" --argjson n "$n" \
  '.steps[] | select(.n==$n) | .branches[$r] // empty' "$MANIFEST")
pr=$(gh stack view --json | jq -r --arg b "$branch" \
  '.branches[] | select(.name==$b) | .pr.number // empty')
```

If `$pr` is empty, that repo's step has not been submitted — report and skip it.

- [ ] **Step 3: Write the preview**

Before merging anything, print every repo, every PR that will merge, and the merge method. Require explicit confirmation. Do not proceed on ambiguity.

- [ ] **Step 4: Merge**

```bash
gh stack merge "$pr" --yes --squash
```

- [ ] **Step 5: Report partial success honestly**

State prominently in the command that all-or-nothing applies **per repo, not across repos**: repo A's stack can merge while repo B's fails on branch protection. The summary must show each repo's outcome separately and never claim workspace-wide success unless every repo succeeded.

- [ ] **Step 6: Mark merged in the manifest**

Apply the mark-merged snippet with `$n`, only for repos that actually succeeded.

- [ ] **Step 7: Verify on a throwaway remote**

Using the Task 6 throwaway repo, merge step 1.
Expected: the bottom PR merges, the next PR retargets to trunk on the next `/stack-rebase`, and `jq '.steps[0].merged'` returns `true`.
Also confirm that declining at the preview prompt leaves every PR open.

- [ ] **Step 8: Commit**

```bash
git add commands/stack-merge.md
git commit -m "feat: add /stack-merge for stacked-PR merges"
```

---

### Task 9: `/stack-modify`

**Files:**
- Create: `commands/stack-modify.md`

**Interfaces:**
- Consumes: manifest rename and drop snippets.
- Produces: a manifest reconciled with the post-TUI stack.

- [ ] **Step 1: Write the frontmatter and repo resolution**

```markdown
---
description: Restructure one repo's stack via gh stack modify, then reconcile the workspace manifest.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Read
---
```

`gh stack modify` is an interactive TUI and single-repo by nature. Resolve exactly one repo; if the argument is ambiguous, ask.

- [ ] **Step 2: Check preconditions**

```bash
[ -z "$(git status --porcelain)" ] || { echo "Working tree must be clean."; exit 1; }
[ ! -d .git/rebase-merge ] && [ ! -d .git/rebase-apply ] || { echo "Rebase in progress."; exit 1; }
```

Also state the extension's other preconditions: linear history, and no PR in the stack queued for merge.

- [ ] **Step 3: Snapshot before the TUI**

```bash
before=$(gh stack view --json | jq -r '.branches[].name')
```

- [ ] **Step 4: Hand off**

Run `gh stack modify` and let the user drive it. Do not attempt to script the TUI.

- [ ] **Step 5: Reconcile afterwards**

```bash
after=$(gh stack view --json | jq -r '.branches[].name')
```

Branches in `before` but not `after` were dropped or folded — apply the drop snippet. For renames, ask the user which old name maps to which new one rather than guessing from position, then apply the rename snippet. Reordering does not change the manifest, since steps carry explicit numbers.

- [ ] **Step 6: Remind about resubmitting**

If the stack was already submitted, print: `Structure changed — run /stack-create-pr to push and recreate the stack on GitHub.`

- [ ] **Step 7: Verify against the fixture**

In a three-layer fixture stack, run the command and use the TUI to rename the middle branch.
Expected: the reconciliation prompt appears, and after answering, `jq '.steps[1].branches' "$FIX/.stack-manifest.json"` shows the new name.

- [ ] **Step 8: Commit**

```bash
git add commands/stack-modify.md
git commit -m "feat: add /stack-modify with manifest reconciliation"
```

---

### Task 10: Re-source the summary and diagram commands

**Files:**
- Modify: `commands/stack-create-summary.md`
- Modify: `commands/stack-create-diagram.md`

**Interfaces:**
- Consumes: manifest reads; `gh stack view --json`.
- Produces: unchanged output formats, accurate inputs.

- [ ] **Step 1: Replace branch discovery in both files**

Delete every `git branch --list '*/step*'` and any `*/stepN*` glob. Replace with reading `.stack-manifest.json` for step numbers, titles, and per-repo branches, and `gh stack view --json` for live state.

- [ ] **Step 2: Add PR numbers and merge state to the diagram**

The diagram can now label each node with its PR number and mark merged layers, since `gh stack view --json` supplies `pr.number` and `isMerged`. Guard the absent `pr` key with `// empty`.

- [ ] **Step 3: Do not use `base` for edges**

State explicitly in both files that `branches[].base` is a commit SHA. Draw parent edges from array order — `branches[i]`'s parent is `branches[i-1]`, and `branches[0]`'s parent is `trunk`.

- [ ] **Step 4: Verify against the fixture**

Run both commands' steps against a two-repo fixture.
Expected: the summary lists steps by number and title with the right repos; the diagram edges follow array order and merged layers are marked.

- [ ] **Step 5: Commit**

```bash
git add commands/stack-create-summary.md commands/stack-create-diagram.md
git commit -m "feat: re-source summary and diagram from the stack manifest"
```

---

### Task 11: Commit `/stack-port` and sweep for stale conventions

**Files:**
- Create: `commands/stack-port.md` (copy from `~/.claude/commands/stack-port.md`)
- Modify: any file still carrying stale references

**Interfaces:**
- Consumes: nothing.
- Produces: a repo whose `commands/` matches what is installed.

- [ ] **Step 1: Copy the uncommitted command**

```bash
cp ~/.claude/commands/stack-port.md commands/stack-port.md
```

It is installed but was never committed, so a fresh `install.sh` run would lose it.

- [ ] **Step 2: Update it for auto-naming**

`/stack-port` cherry-picks a stack onto a different base. Replace any `*/step*` branch discovery with manifest reads, and note that ported branches keep their source names — porting does not rename.

- [ ] **Step 3: Sweep the whole commands directory**

Run: `grep -rnE 'refactor/step|\*/step|gh pr edit --base|checkout -b .*step' commands/`
Expected: no matches outside `/stack-port`'s documented migration notes.

- [ ] **Step 4: Confirm every command carries the guard**

Run: `grep -L 'gh extension list' commands/stack-*.md`
Expected: no output — every `stack-*` command lists the extension check. `/stack-port` is exempt only if it never invokes `gh stack`; if it does, it needs the guard too.

Then confirm the guard actually fires:

```bash
( PATH=/nonexistent
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is not installed."; exit 1; } )
echo "exit=$?"
```

Expected: `ERROR: gh is not installed.` then `exit=1`, with no git or `gh stack` command attempted afterwards.

- [ ] **Step 5: Confirm install parity**

Run: `diff <(ls commands/) <(ls ~/.claude/commands/)`
Expected: the repo now has `stack-start.md`, `stack-merge.md`, and `stack-modify.md` that the install dir lacks; no file present only in the install dir.

- [ ] **Step 6: Install and smoke-test**

```bash
./install.sh
```

Expected: eleven `stack-*` commands in `~/.claude/commands/`.

- [ ] **Step 7: Commit**

```bash
git add commands/
git commit -m "feat: commit /stack-port and sweep stale step-branch conventions"
```

---

## Open items carried from the spec

- **`contoroinc` preview enablement is unverified.** Tasks 6 and 8 will fail at the org level if stacked PRs are not enabled. Confirm before starting Task 6.
- **The `pr` object's keys are inferred, not observed.** Task 6 Step 5 confirms them and corrects `docs/gh-stack-json-reference.md` if wrong. Tasks 4, 8, and 10 depend on those key names, so Task 6 should run before them if possible — or expect a small follow-up correction.
- **Manifest drift is unmitigated by tooling.** The chosen approach has no shared script, so the canonical blocks in `docs/stacked-pr-workflow.md` are the only defense. If drift appears, the fallback is `scripts/stack-lib.sh` plus an `install.sh` change — deferred, not precluded.

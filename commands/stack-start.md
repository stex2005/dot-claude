---
description: Start a new stack across the repos a plan touches — gh stack init per repo, plus the workspace manifest.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *), Read, Write, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (a path to a plan file, or a stack name if there is no plan)

## Preflight

Run the guard block from `docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack` is the only supported mechanism for creating stack branches — never
fall back to hand-rolled `git checkout -b` stacking, even if the guard fails.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`.

In single-repo mode (`MODE=single`) this command still runs `gh stack init` on the
current repo (Step 3 below), but skips manifest creation entirely (Step 4) — `gh
stack`'s own `.git/gh-stack` state is sufficient for one repo, per
`docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`.

## Your task

### Step 1: Determine the stack name, plan, and candidate repos

1. If `$ARGUMENTS` is a path to an existing plan file, read it.
   - Derive the stack `name` from its filename: strip the date prefix and the `.md`
     extension (e.g. `2026-08-31-gripper-refactor.md` → `gripper-refactor`).
   - Record `plan` as that file path.
   - Scan the plan for the repo directory names it mentions and propose those (limited
     to repos actually present via `repos()`) as the candidate set.
2. Otherwise, treat `$ARGUMENTS` itself as the stack `name`, leave `plan` empty (`""`),
   and propose every repo from `repos()` as the candidate set (in single-repo mode,
   the current repo is the only candidate).
3. **Show the proposed stack name and repo list to the user and get explicit
   confirmation (or a corrected list) before continuing.** `gh stack init` mutates
   every repo it touches — there is no dry-run, and Step 3 acts on whatever set is
   confirmed here.

### Step 2: Guard against clobbering an existing manifest

Skip this step in single-repo mode.

```bash
if [ -f "$MANIFEST" ]; then
  jq -r '"Existing stack: \(.name) (\(.steps | length) step(s))"' "$MANIFEST"
fi
```

If `$MANIFEST` already exists, show its `name` and step count (via the snippet above)
and require the user to explicitly confirm before continuing — overwriting it loses
all cross-repo step correlation, with no way to recover it. If they don't confirm,
stop without touching any repo.

### Step 3: Per-repo trunk detection and `gh stack init`

For each confirmed repo, run inside that repo (`cd "$WS/$repo"` in multi-repo mode; the
current directory in single-repo mode):

```bash
trunk=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) \
  || trunk=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$trunk" ] || trunk=$(for b in develop main master; do
    git show-ref -q --verify "refs/heads/$b" && echo "$b" && break; done)
gh stack init --base "$trunk" "${name}-base"
```

`gh stack init` with no branch argument is interactive, so this passes an explicit seed
branch name (`<name>-base`) to keep it non-interactive. This is the one place a stack
command passes `gh stack` an explicit branch name: `gh stack add`, used later by
`/stack-commit` to add layers, always relies on its own `MM-DD-<slug>` auto-naming —
never pass it a name.

Keep a note of the `$trunk` detected for each repo; Step 4 needs all of them.

### Step 4: Write the manifest

Skip this step in single-repo mode — nothing left to do.

Build `$trunk_json` from the per-repo trunk values collected in Step 3, e.g. for repos
`repo-alpha` (trunk `main`) and `repo-beta` (trunk `develop`):

```bash
trunk_json=$(jq -n --arg r1 repo-alpha --arg t1 main --arg r2 repo-beta --arg t2 develop \
  '{($r1):$t1,($r2):$t2}')
# {"repo-alpha":"main","repo-beta":"develop"}
```

Then create the manifest with the create snippet in
`docs/stacked-pr-workflow.md#manifest-writes`, using this `$name`, `$plan`, and
`$trunk_json`. The schema is defined in `docs/stacked-pr-workflow.md#manifest-schema`.
The result always has `steps: []` — no step exists until `/stack-commit` records the
first one.

### Step 5: Report

Print the stack name, the mode (single/multi), each repo initialized with its detected
trunk and seed branch, and — in multi-repo mode — the manifest path.

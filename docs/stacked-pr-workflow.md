# Stacked PR Workflow

## Why

We want to keep refactoring and feature work moving without blocking on code review, while keeping PRs small and reviewable. Large, long-lived branches lead to painful merges and are hard to review. Stacked PRs solve both problems.

## How it works

A stack is an ordered list of branches, managed by the `github/gh-stack` CLI
extension. The branch closest to trunk is the **bottom** of the stack; each
later branch stacks on top of the one below it.

```
develop (trunk)
  ← 08-31-split_gripper_files   (bottom)
    ← 08-31-gripper_class
      ← 08-31-planning           (top)
```

`gh stack submit` links the stack's branches into a single Stack object on
github.com, with each PR targeting the branch below it. Retargeting after a
merge is automatic: `gh stack sync` retargets, rebases, and prunes the
remaining branches — there is no manual per-PR retargeting step.

Review happens **bottom-up**: only the PR targeting trunk (the bottom of the
stack) is reviewed at any given time. Once it merges, `gh stack sync`
retargets the next PR to trunk and it becomes the new review target.

## Rules

1. **< 400 lines of diff per PR.** If a step is bigger, split it further.
2. **Bottom-up review.** The reviewer only looks at the PR going into trunk.

## Workflow

### Starting a new stack

```
/stack-start <plan-or-name>
```

### Adding a step

```
/stack-commit            # classifies changes, runs gh stack add -Am per repo
```

### Opening PRs

```
/stack-create-pr         # gh stack submit --auto --open per repo
```

### After a PR merges

```
/stack-rebase            # gh stack sync: retargets, rebases, prunes
```

### Merging

```
/stack-merge step2       # gh stack merge, with preview and confirmation
```

## Guard

Every stack command starts by checking `gh` and the `gh-stack` extension are
present:

```bash
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is not installed."; exit 1; }
gh extension list 2>/dev/null | grep -q 'github/gh-stack' || {
  echo "ERROR: gh-stack not installed. Run: gh extension install github/gh-stack"
  exit 1
}
```

## Workspace and manifest resolution

```bash
if [ -d .git ]; then MODE=single; WS="$PWD"; else MODE=multi; WS="$PWD"; fi
MANIFEST="$WS/.stack-manifest.json"
repos() { for d in "$WS"/*/; do [ -d "$d/.git" ] && basename "$d"; done; }
```

## Manifest schema

```json
{
  "version": 1,
  "name": "gripper-refactor",
  "plan": "unloading_robot_ws/docs/superpowers/plans/2026-08-31-gripper-refactor.md",
  "trunk": { "unloading_robot_ws": "develop", "contoro_utils": "main" },
  "steps": [
    { "n": 1, "title": "Split gripper files", "merged": false,
      "branches": { "unloading_robot_ws": "08-31-split_gripper_files" } },
    { "n": 2, "title": "Extract gripper class", "merged": false,
      "branches": { "unloading_robot_ws": "08-31-gripper_class",
                    "contoro_utils":      "08-31-gripper_types" } }
  ]
}
```

Field notes:

- `trunk` is recorded per repo because the repos disagree (`develop` vs `main`).
- `steps[].branches` lists **only** the repos participating in that step. This
  is what expresses a step touching two of five repos — something positional
  alignment across `gh stack view --json` could not represent.
- `steps[].merged` is set by `/stack-merge` and by the sync path.
- Repo keys are directory names relative to the workspace root.
- PR numbers are deliberately **not** stored. They are derived from
  `gh stack view --json` on demand, so the manifest cannot go stale as PRs are
  opened, retargeted, merged, or closed.

Related, and easy to get backwards: `gh stack view --json`'s `branches[].base`
field is a **commit SHA, not a branch name** — parent relationships come from
array order (`branches` is bottom-first), never from `base`. This is also why
`branches[].pr` must always be read with a `// empty` guard: it is omitted
entirely, not null, when no PR exists for that branch yet.

## Manifest reads

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

## Manifest writes

Always via temp file, never in-place:

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

## Migration

**Migrating in-flight `refactor/stepN-*` branches**

Per repo, adopt existing branches bottom-first:

    gh stack init --base develop refactor/step1-foo refactor/step2-bar

Then record them in the manifest with the step-recording jq snippet, using
their existing numbers. Adopted branches keep their old names; only new
layers get auto-generated names. Migrate one repo at a time.

## Claude Code commands

| Command | What it does |
|---|---|
| `/stack-start` | Initializes a new stack: runs `gh stack init` per participating repo and writes the manifest skeleton |
| `/stack-commit` | Classifies uncommitted changes against the plan and commits to the correct step — `gh stack add -Am` for a new step, a plain `git commit` to extend the current one |
| `/stack-create-pr` | Opens chained PRs per repo via `gh stack submit --auto --open`, then writes cross-repo reference blocks into each PR body |
| `/stack-rebase` | Runs `gh stack sync` per repo: retargets, rebases, and prunes after a merge |
| `/stack-status` | Dashboard of step branches, grouped by logical step and joined against the manifest, across all repos |
| `/stack-checkout` | Checks out the branch for a given step (or `top`/`bottom`/`up`/`down`) in each participating repo |
| `/stack-merge` | Merges up to a given step via `gh stack merge` per repo, with a preview and confirmation before acting |
| `/stack-modify` | Hands off to the `gh stack modify` TUI, then reconciles renamed and dropped branches into the manifest |
| `/stack-create-summary` | Generates or updates a text summary of the stack — goals, repos, changes, status, risks per step |
| `/stack-create-diagram` | Renders a diagram of the PR stack across repos, including PR numbers and merge state |
| `/stack-port` | Ports a stack of branches onto a different base branch by cherry-picking, with cross-base API mismatch checks |

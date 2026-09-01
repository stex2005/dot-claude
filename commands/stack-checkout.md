---
description: "Checkout a specific step branch across all repos, or navigate the stack (top/bottom/up/down/trunk)."
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *)
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (one of: `stepN`, `top`, `bottom`, `up [n]`, `down [n]`, `trunk`; defaults to `top` if empty)

## Preflight

Run the guard block from `~/.claude/docs/stacked-pr-workflow.md#guard` and stop immediately
if it fails. `gh stack` navigation and the manifest are the only supported sources of branch
data — **never** fall back to hand-rolled `*/stepN*` branch globbing, even if the guard
fails.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`~/.claude/docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is
read only when `MODE=multi`. In single-repo mode there is no manifest: a `stepN` argument is
resolved instead from the **1-indexed bottom-first position** of the branch in `gh stack
view --json .branches` — the identical rule `/stack-status` and `/stack-commit` use.

## Your task

| Argument | Behavior |
|---|---|
| `stepN` | Check out the branch the manifest records for step N in each participating repo |
| `top` / `bottom` | `gh stack top` / `gh stack bottom` in every repo with a stack |
| `up [n]` / `down [n]` | `gh stack up [n]` / `gh stack down [n]` in every repo with a stack |
| `trunk` | `gh stack trunk` in every repo |
| (none) | Defaults to `top` |

### Step 1: Parse the argument

Split `$ARGUMENTS` into an action and an optional numeric argument (`up 3` → action
`up`, n `3`). No argument at all means action `top`.

- If the action matches `^step[0-9]+$`, extract `N` — this is the **stepN path**
  (Step 2 below).
- If the action is `top`, `bottom`, or `trunk`, it takes no numeric argument.
- If the action is `up` or `down`, an optional trailing integer selects how many
  branches to move; omit it to let `gh stack up`/`gh stack down` use their own default
  (one branch).
- Anything else is not a recognized argument — report the table above and stop.

### Step 2: The `stepN` path

**Every path below checks the working tree before checking out anything** — a dirty
tree is skipped and reported, never carried across branches or left to fail mid-loop.

**Multi-repo mode:** for each repo from `repos()`:

```bash
dirty=$(git -C "$WS/$repo" status --porcelain)
# This is the "branch recorded for step n in a repo" snippet from
# ~/.claude/docs/stacked-pr-workflow.md#manifest-reads, verbatim. The jq
# variable is $n (bound by --argjson n from the shell's $N) — writing $N inside
# the filter is a jq compile error, not a lookup miss, and the resulting empty
# capture silently reports every repo as "not part of step N".
branch=$(jq -r --arg r "$repo" --argjson n "$N" \
  '.steps[] | select(.n==$n) | .branches[$r] // empty' "$MANIFEST")
if [ -z "$branch" ]; then
  echo "$repo: not part of step $N — leaving on $(git -C "$WS/$repo" branch --show-current)"
elif [ -n "$dirty" ]; then
  echo "$repo: uncommitted changes — skipping checkout of $branch"
else
  git -C "$WS/$repo" checkout "$branch" && echo "$repo: checked out $branch"
fi
```

A repo with no entry for step `N` in the manifest is not participating in that step:
leave it exactly where it is and report it, per the table above — this is not an error
and not a fallback case.

**Single-repo mode:** there is no manifest; resolve the branch positionally.

```bash
json=$(gh stack view --json 2>/dev/null); rc=$?
if [ "$rc" -eq 2 ]; then
  echo "no stack here"
elif [ "$rc" -eq 6 ]; then
  echo "on $(git branch --show-current), which belongs to multiple stacks — gh stack cannot tell which one you mean. Check out a non-trunk branch of the intended stack and re-run."
else
  total=$(jq '.branches | length' <<<"$json")
  if [ "$N" -lt 1 ] || [ "$N" -gt "$total" ]; then
    echo "step $N does not exist — stack has $total step(s)"
  else
    branch=$(jq -r --argjson i "$((N-1))" '.branches[$i].name' <<<"$json")
    dirty=$(git status --porcelain)
    if [ -n "$dirty" ]; then
      echo "uncommitted changes — skipping checkout of $branch"
    else
      git checkout "$branch" && echo "checked out $branch"
    fi
  fi
fi
```

### Step 3: The `top` / `bottom` / `up` / `down` / `trunk` path

**Multi-repo mode:** for each repo from `repos()`, run inside that repo:

```bash
(
  cd "$WS/$repo"
  gh stack view --json >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "$repo: no stack — skipping"
  elif [ "$rc" -eq 6 ]; then
    echo "$repo: on $(git branch --show-current), which belongs to multiple stacks — check out a non-trunk branch of the intended stack and re-run"
  else
    dirty=$(git status --porcelain)
    if [ -n "$dirty" ]; then
      echo "$repo: uncommitted changes — skipping"
    else
      gh stack "$action" $narg
    fi
  fi
)
```

`rc == 2` means "no stack in this repo" (per the exit-code contract in
`~/.claude/docs/stacked-pr-workflow.md#exit-codes`) — skip and report it, not an error.
This still holds even for repos the manifest never mentions, since this path does not
consult the manifest at all. `rc == 6` means the repo's current branch belongs to
**several** stacks (typically trunk, in a repo with more than one stack) — skip that
repo with the message above, not with a generic failure; it is a "tell `gh stack` which
stack you mean" problem, not a broken repo.

**Single-repo mode:** run the same dirty-tree check, then `gh stack "$action" $narg`
directly in the current directory. `rc == 2` here means there is no stack at all —
report "no stack" and stop.

### Step 4: Print a summary

List, one line per repo (multi-repo mode) or one line (single-repo mode), what
happened: checked out to `<branch>`, left alone (`not part of step N` /
`no stack`), or skipped (`uncommitted changes`).

## Rules

- NEVER use destructive git commands.
- NEVER check out over a dirty working tree — check `git status --porcelain` before
  every checkout, in every path, and skip that repo instead of forcing it.
- NEVER fall back to `*/stepN*` branch globbing or any other hand-rolled branch
  discovery — the manifest (multi-repo `stepN`) and `gh stack view --json` position
  (single-repo `stepN`) are the only sources; `gh stack` navigation subcommands are the
  only source for `top`/`bottom`/`up`/`down`/`trunk`.
- A repo not participating in the requested step is left untouched and reported, never
  checked out to something arbitrary and never treated as an error.
- `rc == 2` from `gh stack view` means "no stack" for that repo — report it, don't
  treat it as a failure. `rc == 6` means that repo's current branch belongs to multiple
  stacks — report the "check out a non-trunk branch of the intended stack" message and
  skip that repo, also not a failure
  (`~/.claude/docs/stacked-pr-workflow.md#exit-codes`).

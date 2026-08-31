---
description: Port a stack of step/feature branches onto a different base branch (e.g. release-candidate/v3.1.0) by cherry-picking, with cross-base API mismatch checks.
allowed-tools: Bash(git *), Bash(ls *), Bash(for *), Bash(cd *), Bash(grep *), Bash(catkin *), Bash(ruff *), Bash(jq *), Bash(gh *), Bash(mkdir *), Bash(ln *), Bash(rm *), Bash(wc *), Read, Write, Edit, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS — `<step-n> <target-base>` (e.g. `2 release-candidate/v3.1.0`). In
  multi-repo mode `<step-n>` is a step number, resolved against `$MANIFEST` per repo
  (Step 1 below) — steps no longer share one literal branch name across repos the way
  `refactor/step1` once did, because `gh stack` auto-names each repo's branch
  independently. In single-repo mode, `<step-n>` may be a step number (resolved by
  bottom-first position, same convention as `/stack-status`) or a literal branch name.

## Preflight

Run the guard block from `~/.claude/docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. Single-repo mode resolves `<step-n>` via `gh stack view --json` (Step 1), so this
command does invoke `gh stack` and is not exempt from the guard.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`~/.claude/docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is read
only when `MODE=multi`, via the manifest-read snippets in
`~/.claude/docs/stacked-pr-workflow.md#manifest-reads`; it is never written by this command —
porting reads the existing stack, it never records anything back into it. In
single-repo mode there is no manifest; resolve `<step-n>` to a branch the same way
`/stack-status` does, by 1-indexed bottom-first position in `gh stack view --json
.branches`.

**Naming.** Ported branches keep their source names — porting does not rename. The
per-repo step branches this command reads (via the manifest in multi-repo mode, or
`gh stack view --json` in single-repo mode) were auto-named by `gh stack` and are left
untouched; this command only reads them, never renames or re-adds them via `gh stack
add`. The **new** branch this command creates per repo in Step 2 (`port/<target>/<slug>`)
is a separate, bespoke name chosen by this command, not by `gh stack` — its `<slug>`
is derived from the source branch's own slug (the part after the `MM-DD-` prefix) so
provenance stays traceable, but it is a genuinely new branch, not a rename of the source.

## Goal

Port a stack of branches that were authored against one base (typically `develop`) onto a different base (typically a `release-candidate/*` branch) **without dragging the source-base history with it**. Produce a clean `port/<target>/...` branch per repo, ready for PRs.

## Why cherry-pick, not rebase

`git rebase <source-branch> --onto <target-base>` *replays every commit between the merge-base and HEAD onto the new base* — including unrelated commits that landed on the source base since the stack forked. Those unrelated commits often conflict heavily with the target base and pollute the port.

`git cherry-pick <commit>...` only replays the commits you explicitly select, so you can apply *just* the stack's own commits onto the target base. This is the right tool for port-to-RC work.

## Critical caveat — cherry-pick is textual

Cherry-pick is a 3-way *text* merge. It cannot catch:

- **API mismatches** in code added unchanged from the source base (e.g. a method that only exists on develop's `CommonMotionTools`, called from a new file the cherry-pick creates).
- **Method signatures** that differ between source and target base.
- **Constants** with different values between bases (e.g. enum renumbers).

These slip through cherry-pick AND through `catkin build` (Python doesn't typecheck attribute access at import time) AND through unit tests if they `pytest.skip()` when sim isn't running. They only surface at *runtime*.

**Your job in this skill is to surface those mismatches mechanically before declaring the port done.**

## Steps

### Step 0 — Inputs & precondition checks

1. Parse `$ARGUMENTS` for `<step-n>` and `<target-base>`. If only one is provided, ask for the other.
2. `git fetch origin` in every participating repo.
3. Verify working trees are clean. If any repo has uncommitted changes, **stop** and ask user to commit/stash first.

### Step 1 — Identify participating repos and their source branches

**Multi-repo mode**: for each repo from `repos()`, look up its branch for step `<step-n>`
with the manifest-read snippet from `~/.claude/docs/stacked-pr-workflow.md#manifest-reads`:

```bash
jq -r --arg r "$repo" --argjson n "$step_n" \
  '.steps[] | select(.n==$n) | .branches[$r] // empty' "$MANIFEST"
```

A repo with no entry for that step is not participating — skip it. Record the resolved
`$branch` per participating repo; every reference below to "the source branch" for a
repo means this per-repo `$branch`, not one literal name shared across repos.

**Single-repo mode**: if `<step-n>` parses as a number, resolve it to a branch by
1-indexed bottom-first position in `gh stack view --json .branches` (same convention as
`/stack-status`); otherwise treat `<step-n>` as a literal branch name directly.

For each participating repo, also check that `origin/<target-base>` exists. If a repo lacks the target base, **stop** and tell the user.

### Step 2 — Create port worktrees

**Do not** check out the port branch in the user's working tree — that pulls them off their current work. Create a parallel worktree dir per repo so the user's normal workspace stays intact:

```bash
mkdir -p ~/<workspace-name>-port-<target-tag>/
for repo in <participating-repos>; do
  git -C $repo worktree add -b port/<target>/<slug> \
    ~/<workspace-name>-port-<target-tag>/$repo \
    origin/<target-base>
done
```

Branch naming convention: `port/<target-without-prefix>/<slug>` — e.g. `port/v3.1.0/move_robot`.

### Step 3 — Identify source-only commits

For each repo, find the commits unique to that repo's resolved `$branch` (from Step 1) — i.e. *not* on `origin/<target-base>` or its ancestors:

```bash
git -C $repo log --oneline origin/<target-base>..$branch
```

That list is what you cherry-pick. **Do not include** commits that appear in `git log --oneline origin/<target-base>` already (auto-syncs, develop merges, etc.).

If the source branch sits on top of an earlier step (e.g. step 2 forks from step 1's branch), include the earlier step's unique commits too — repeat the same `log` range against that earlier branch's own pre-fork merge-base. In multi-repo mode, walk down to the **nearest earlier step this repo actually participates in**, falling back to `.trunk[$r]` when there is none — a repo can join the stack partway up, so step n-1 may have no branch for it at all. The parent-branch snippet and its trunk fallback are in `~/.claude/docs/stacked-pr-workflow.md#manifest-reads`; `/stack-create-summary` and `/stack-create-diagram` resolve parents the same way.

In an interactive session, **show the user the commit list per repo before cherry-picking** and ask them to confirm.

### Step 4 — Cherry-pick onto each port worktree

Pick **oldest first** so the chain replays in original order:

```bash
cd ~/<workspace-name>-port-<target-tag>/$repo
git cherry-pick <oldest>..<newest>
# OR explicit list, oldest first:
git cherry-pick <c1> <c2> <c3> ...
```

**On conflict:**

1. **Stop immediately.** Do NOT attempt to auto-resolve.
2. Show the conflicting hunks to the user with `awk '/^<<<<<<< /,/^>>>>>>> /' <file>`.
3. Identify whether the conflict comes from:
   - **Stack work intersecting target-base changes** in the same region (e.g. both edited the same function differently). → Hand-merge keeping target-base behavior, layering the stack's intent on top.
   - **A method/API that's on the source base but not the target base**. → This is a v3.1.0 compat issue; keep target-base's version and add only the part of the stack's change that's compatible (e.g. just the `enable_actions` gate without the new debounce loop). Document the shim in a comment.
4. Ask the user to pick a resolution before proceeding.
5. After resolution: `git add <files> && git -c core.editor=true cherry-pick --continue`.

### Step 5 — Pre-runtime API mismatch check

This is the step that **catches what cherry-pick cannot**. It must run on every port before declaring done.

For each new or modified Python file in the port:

1. **Grep all method calls on shared-class instances** (e.g. `self.common.<method>`, `self.node.common.<method>`, `self.gripper.<method>`, `self.kuka.<method>`). Extract a list of `<class>.<method>` references the port code uses.

2. **Verify each method exists on the target-base version of that class**:
   ```bash
   for method in <method-list>; do
     grep -l "def $method" $(find <target-base-source> -name '*.py') || echo "MISSING: $method"
   done
   ```

3. **Any `MISSING:` line is a runtime bomb.** Fix before pushing:
   - If the method's behavior is available via another API on the target base, replace the call. Common pattern: `self.common.get_current_robot_state()` → `self.kuka.get_current_state().current_state` or via a `/move_group_server/get_current_state` ServiceProxy.
   - If not, copy the method into the port (add it to the target-base class as part of the port).
   - Document each substitution as a `# v3.1.0 compat:` comment so a future reader knows why.

4. **Constant-value drift check**: for any enum constants the stack relies on (e.g. `*Result.ERROR_PREEMPTED`), verify the *numeric value* matches between source and target. If the source's stack renumbered constants, that renumber needs to be in the port too — and any consumer that compares by integer needs updating.

### Step 6 — Build verification (parallel workspace)

Don't clobber the user's main build. Set up a symlinked sibling workspace:

```bash
mkdir -p ~/<ws>-port/src
ln -sfn ~/<ws>-port-<target-tag>/<repo1> ~/<ws>-port/src/<repo1>
ln -sfn ~/<ws>-port-<target-tag>/<repo2> ~/<ws>-port/src/<repo2>
# Plus any auxiliary repos at the matching target-base ref (hal, kuka_experimental, etc.):
git -C ~/<ws>/src/<aux-repo> worktree add ~/<ws>-port-<target-tag>/<aux-repo> origin/<target-base>
ln -sfn ~/<ws>-port-<target-tag>/<aux-repo> ~/<ws>-port/src/<aux-repo>

cd ~/<ws>-port && catkin build
```

If the build fails on a Python attribute error or import error, the pre-runtime check at Step 5 missed something — go back, find the missing method, fix it.

### Step 7 — Smoke-test imports

```bash
source ~/<ws>-port/devel/setup.bash
python3 -c "
import <package>.<new_module_1>
import <package>.<new_module_2>
# Plus a constant value sanity check:
from <package>.msg import <ResultMsg>
print(<ResultMsg>.ERROR_PREEMPTED, <ResultMsg>.ERROR_*_OTHER)
"
```

This catches missing methods that the build doesn't (Python imports execute the module body but don't call individual methods).

### Step 8 — Lint per repo

```bash
cd ~/<ws>-port-<target-tag>/<repo>
ruff check .
ruff format --check .
```

Same toolchain as the main repos. Fix any drift.

### Step 9 — Push port branches

```bash
for repo in <participating>; do
  git -C ~/<ws>-port-<target-tag>/$repo push -u origin port/<target>/<slug>
done
```

### Step 10 — Open ports as PRs (optional)

If the user wants PRs, hand off to `/create-pr`-style flow with `--base <target-base>` per repo. Append a cross-repo footer linking the sibling PRs, with `org/repo#number` for GitHub auto-linking.

The PR title should signal the port: `port(rc-X.Y.Z): <description>`. Body should call out:
- Which source PR(s) this ports.
- The target base.
- The list of v3.1.0 compat shims and *why* each is needed (the API-mismatch reason).

## Rules

- **Never `git rebase` onto the target base** — that's how unrelated source-base commits leak in.
- **Never sed-edit Python files** to make rename changes; sed has truncated files in past sessions when the disk hiccuped or a write was interrupted. Use the Edit tool with `replace_all`.
- **Use `--force-with-lease`** if you ever need to force-push (collaborators may have local work).
- **Surface every conflict to the user** — never auto-resolve in port work, the choice is usually load-bearing for v3.1.0 vs source-base behavior.
- **The pre-runtime API mismatch check (Step 5) is mandatory.** It's the difference between a clean port and one that throws AttributeError at runtime.
- **Build is necessary but not sufficient.** Catkin build does NOT validate Python attribute access. Always do the import smoke test in Step 7.
- **One pass = one cherry-pick range per repo.** Don't interleave merges or rebases.

## Lessons learned (failure modes seen in real ports)

1. **`CommonMotionTools.get_current_robot_state` was on develop only.** Cherry-pick added new files calling it; build passed; runtime threw `AttributeError`. → Step 5 catches this.
2. **`box_in_proximity` signature changed** between develop and v3.1.0 (added `_m` suffix, None-handling, debounce). The cherry-pick of a develop commit that touched the call surface couldn't auto-merge. → Step 4 conflict resolution flagged this; resolution was to keep target-base version.
3. **Enum renumber leaked**: `ERROR_PREEMPTED` was 5 on develop's HomeRobot.action and 3 on aligned-with-MoveKuka. Anyone comparing by integer (e.g. debugger heuristic `code == 3`) needed updating. → Step 5 constant-value drift check.
4. **`sed -i 's/A/B/g' file.py` truncated the file mid-session** during a rename, leaving 0 bytes. The empty file got committed into a squash. The PR was clean except for one totally-empty file. → Don't use sed for code edits in port work; use the Edit tool.
5. **rostopic echo missed the result publish** — unrelated to porting, but the *symptom* was identical to "port broke action publishing." Always validate via a real `SimpleActionClient` (`get_result()`), not `rostopic echo`. The `home_robot_test.py` probe pattern is reusable.

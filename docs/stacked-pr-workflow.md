# Stacked PR Workflow

## Why

We want to keep refactoring and feature work moving without blocking on code review, while keeping PRs small and reviewable. Large, long-lived branches lead to painful merges and are hard to review. Stacked PRs solve both problems.

## How it works

Each refactor or feature is broken into small, sequential steps. Each step lives on its own branch and gets its own PR. PRs form a chain where each one targets the previous step, except the first which targets `develop`.

```
develop
  ← step1-split-files       (PR #1 → develop)
    ← step2-gripper-class   (PR #2 → step1)
      ← step3-planning      (PR #3 → step2)
```

Review happens **bottom-up**: only the PR targeting `develop` (the bottom of the stack) is reviewed at any given time. Once it merges, the next PR is retargeted to `develop` and becomes the new review target.

## Rules

1. **< 400 lines of diff per PR.** If a step is bigger, split it further.
2. **One step = one branch.** Branch naming: `refactor/step<N>-<slug>`.
3. **Each step branches from the previous one**, not from `develop`. This keeps the chain linear.
4. **Bottom-up review.** The reviewer only looks at the PR going into `develop`.
5. **Retarget after merge.** When step N merges into `develop`, retarget step N+1's PR to `develop`.

## Workflow

### Starting a new stack

1. Branch from `develop`:
   ```bash
   git checkout develop && git pull
   git checkout -b refactor/step1-split-files
   ```
2. Implement step 1, commit, push.
3. Open PR: `step1-split-files → develop`.

### Adding the next step

1. From the current step branch, create the next:
   ```bash
   git checkout -b refactor/step2-gripper-class
   ```
2. Implement step 2, commit, push.
3. Open PR: `step2-gripper-class → step1-split-files`.

### After a PR merges

1. The bottom PR (e.g. step1 → develop) gets merged.
2. Retarget the next PR (step2) to `develop`:
   ```bash
   gh pr edit <PR_NUMBER> --base develop
   ```
3. step2 → develop is now the new bottom of the stack and ready for review.

### Rebasing the stack

When `develop` moves forward and you need to update:

```bash
# From each step branch, in order:
git checkout step1-split-files && git rebase develop
git checkout step2-gripper-class && git rebase step1-split-files
git checkout step3-planning && git rebase step2-gripper-class
# Force-push each (coordinate with reviewer)
```

## Multi-repo considerations

The workspace contains multiple repos under `src/`. A single refactor step may touch one or more repos. Step branches should use the same naming convention across repos so the relationship is clear.

## Claude Code commands

| Command | What it does |
|---|---|
| `/commit-stack` | Classify changes against the plan, commit to the correct step branch, auto-advance to next step |
| `/create-pr-stack` | Create chained PRs for all steps, retarget after merges |
| `/stack-status` | Dashboard of step branches, current position, and plan status per repo |
| `/rebase-stack` | Rebase the full chain of step branches when the base moves |
| `/checkout-latest-step` | Check out the highest step branch in each repo to start a session clean |
| `/start-plan` | Break the refactor into numbered phases before starting |
| `/resume-plan` | Pick up where you left off on a saved plan |

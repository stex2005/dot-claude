---
description: Fix /pr-review findings one at a time — analyze each and propose a fix, change the code only on your go-ahead, then test and move on.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
argument-hint: [pr-number|url] [finding numbers]
---

## Goal

After a `/pr-review`, work through its findings one by one. Analyze each finding and propose a fix. Change code only when the user says so.

## Input

- Use the findings from the `/pr-review` earlier in this conversation. If there isn't one, run `/pr-review $ARGUMENTS` first.
- If the arguments name finding numbers, take only those. Otherwise go in priority order (MUST, then SHOULD, then MAY).
- Work in the checkout or worktree that holds the code under review, in every repo the findings touch. If the PR's branch isn't checked out anywhere, ask where to work. Never fix on `main` or `develop`.
- Drop or reword findings that decisions made since the review have changed.

## One finding at a time

1. **Analyze.** Read the code around the finding and follow it to where it matters. Check that it still holds, when it can happen and what the effect is. Don't edit anything yet. If the finding is wrong or narrower than the review said, say so in the proposal, even if its severity or resolution was already agreed.
2. **Propose and stop.** Show the analysis and the smallest fix that resolves the finding, then wait:

   ```
   [2/7] SHOULD · world_scanner.py:2443
   Analysis: <does it hold, when it happens, what it does, in two or three sentences>
   Proposed fix: <the change, naming the function or line>
   Test: <the test to add or run>
   Alternatives: <only if one behaves differently>
   Recommendation: fix now, follow-up or drop
   ```

3. **Fix, on a go-ahead only.** Stay inside the finding: no drive-by cleanups, even in the same function.
4. **Test.** For a behaviour change, write the test first and watch it fail. Run the narrowest tests that cover the change, plus the repo's linter on changed files. Follow the repo's rules on what is safe to run, for example on a live ROS master. Comments, constants and other changes with no behaviour effect need only the linter.
5. **Report, then propose the next.** Give the result in a few lines, and put the next finding's proposal in the same message, so each finding costs one stop:

   ```
   [2/7] SHOULD · world_scanner.py:2443 · fixed
   <what changed, one or two sentences>
   Tests: <command> → <result>, or what could not be run
   ```

If the tests fail and the cause isn't the fix, stop and ask.

A finding that isn't a code change, such as opening a PR, merge order or confirming something with another team, is listed as `needs you`. Don't act on it, and move on to the next proposal in the same turn.

## Loop

After each proposal, the user may say:

- **"go"**, **"fix"** or **"fix it"**: apply the proposed fix.
- **Feedback** ("simpler", "use a constant"): revise the proposal and show it again. Don't edit yet. Feedback is not a go-ahead. If a go-ahead comes with a new idea ("fix it, or maybe an enum?"), revise and confirm.
- **"next"** or **"skip"**: leave the finding unfixed and propose the next one.
- **"follow-up"**: leave it, record it for a follow-up issue, and propose the next one.
- **"revert"**: undo only the last fix. Don't use `git checkout` or `git restore` on a whole file if it holds earlier fixes or uncommitted work.
- **"rest"** or **"all"**: apply the remaining proposals without stopping for each. Stop only for failing tests or a fix with real alternatives.

## Finish

Never commit or push unless asked. Fixes stay in the working tree, so the user can review them together; `/commit` is the usual next step.

End with a table of every finding and its outcome (fixed, skipped, follow-up, needs you), what wasn't tested, and anything a fix changed that an existing PR comment or description still claims.

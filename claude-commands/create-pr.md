---
name: create-pr
description: Creates a Github pull request using the `gh` CLI tool. Use when asked to create a PR or pull request.
---

- Ensure all changes are committed. If not, run `/commit` first.
- Run `ruff check --fix` and `ruff format` on any changed Python files to avoid CI failures.
- Review the changes on the current branch for the relevant repo.
- If there are obvious deficiencies that should be fixed first, bring it to the developer's
  attention immediately.
- Push the branch to remote if not already pushed.
- If the user specified a target base branch in the arguments (e.g. `/create-pr develop`, `/create-pr feature/stefano/refactoring`), use that. Otherwise, ask which base branch to target.
- Draft a pull request description and write it to `pr-description.md` in the repo root for the developer to refine.
- Always use PULL_REQUEST_TEMPLATE if available in the repo.
- If not present use three main sections as markdown headers:
  - Overview: Simple prose description of the overall change; no more than 3 sentences
  - Summary of Changes: Bullet list of the main changes details
  - Testing: How the PR was tested and/or how the reviewer can test it
- Include the working title in the file for the developer to edit as needed.
- Keep the description brief and focused:
  - Make sure the big-picture is clear to a reviewer stepping in without much context
  - Don't call out small or obvious changes; the reviewer has limited time and attention
  - Do call out or highlight controversial or breaking changes
  - Provide just one or two points on how to test the changes
- Do NOT include `Co-Authored-By` lines in the PR description.
- Wait for the developer to say they've finished editing the description draft.
- Submit the PR using `gh pr`. Default to a regular PR unless asked to make a draft PR.
- Remove the description draft file.

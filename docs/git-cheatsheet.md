# Git Cheatsheet

## Rebase feature branch on develop
```bash
git fetch origin develop && git rebase origin/develop && git push --force-with-lease
```
- Replays your commits on top of latest develop (linear history, no merge commit)
- `--force-with-lease` is needed because rebase rewrites commit hashes; it's the safe version of `--force` (refuses if someone else pushed)

## Retrigger CI without code changes
```bash
# Option 1: Empty commit (simplest)
git commit --allow-empty -m "chore: retrigger CI" && git push

# Option 2: Amend last commit (no extra commit in history)
git commit --amend --no-edit && git push --force-with-lease

# Option 3: GitHub API (no git history change)
gh workflow run "<workflow-name>" --ref <branch>
```

## Revert last commit (keep in history)
```bash
git revert HEAD --no-edit && git push
```

## Remove commits from history
```bash
# Reset to a specific commit and force push
git reset --hard <commit-hash> && git push --force
```

## Commit only specific changes from a file
```bash
# Interactive hunk staging
git add -p <file>

# Or: reset file, apply only the change you want, then stage
git checkout -- <file>
# make your edit
git add <file>
```

## Check what will be in a PR
```bash
# All commits since diverging from develop
git log --oneline develop..HEAD

# Full diff against develop
git diff develop...HEAD
```

## Amend a commit message
```bash
git commit --amend -m "new message" && git push --force-with-lease
```

## Cherry-pick a commit from another branch
```bash
git cherry-pick <commit-hash>
```

## Stash and restore work in progress
```bash
git stash                  # save WIP
git stash pop              # restore WIP
git stash list             # see all stashes
```

## Update PR description via API (workaround for GitHub Projects Classic deprecation)
```bash
gh api repos/<org>/<repo>/pulls/<number> -X PATCH -f body="<new body>"
```

# Claude Code Workflow

Custom [Claude Code](https://claude.com/claude-code) slash commands for managing stacked PRs and multi-repo refactoring workflows.

## Setup

Clone directly into your Claude Code commands directory:

```bash
git clone git@github.com:stex2005/claude-code-workflow.git ~/.claude/commands/claude-code-workflow
```

Claude Code automatically discovers `.md` files in subdirectories of `~/.claude/commands/`, so all commands will be available immediately (e.g. `/stack-commit`, `/stack-create-pr`).

## Commands

### Stack workflow
| Command | Description |
|---|---|
| `/stack-commit` | Classify changes against the plan, commit to the correct step branch, auto-advance |
| `/stack-create-pr` | Create PRs for all steps or a single step across repos, with cross-references. Retarget after merges. |
| `/stack-create-diagram` | Visualize the PR stack across repos as a draw.io matrix diagram |
| `/stack-create-summary` | Generate a text summary of the stack — goals, repos, changes, status, and features per step |
| `/stack-update-summary` | Update an existing stack summary with latest changes and status |
| `/stack-status` | Dashboard of step branches, PRs, and plan status per repo |
| `/stack-rebase` | Rebase the full chain of step branches when the base moves |
| `/stack-checkout` | Check out a specific step branch across all repos |

### Planning
| Command | Description |
|---|---|
| `/start-plan` | Break work into numbered phases before starting |
| `/save-plan` | Persist the current plan to disk |
| `/resume-plan` | Pick up where you left off on a saved plan |

### General
| Command | Description |
|---|---|
| `/commit` | Lint, format, and commit changes on the current branch |
| `/create-pr` | Create a single PR for the current branch |
| `/create-diagram` | Create a draw.io XML diagram |

## Git flow

See [stacked-pr-workflow.md](stacked-pr-workflow.md) for the full stacked PR strategy.

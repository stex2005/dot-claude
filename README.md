# Claude Code Workflow

Custom [Claude Code](https://claude.com/claude-code) slash commands for managing stacked PRs and multi-repo refactoring workflows.

## Setup

Clone directly into your Claude Code commands directory:

```bash
git clone git@github.com:stex2005/claude-code-workflow.git ~/.claude/commands/claude-code-workflow
```

Claude Code automatically discovers `.md` files in subdirectories of `~/.claude/commands/`, so all commands will be available immediately (e.g. `/commit-stack`, `/create-pr-stack`).

## Commands

### Stack workflow
| Command | Description |
|---|---|
| `/commit-stack` | Classify changes against the plan, commit to the correct step branch, auto-advance |
| `/create-pr-stack` | Create chained PRs for all steps, retarget after merges |
| `/stack-status` | Dashboard of step branches, PRs, and plan status per repo |
| `/rebase-stack` | Rebase the full chain of step branches when the base moves |
| `/checkout-latest-step` | Check out the highest step branch in each repo |

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
| `/create-cross-pr` | Create PRs for one step across all repos, with cross-references |
| `/create-diagram` | Create a draw.io XML diagram |
| `/software-diagram` | Create a software architecture diagram |

## Git flow

See [stacked-pr-workflow.md](stacked-pr-workflow.md) for the full stacked PR strategy.

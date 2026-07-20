# dot-claude

Custom [Claude Code](https://claude.com/claude-code) slash commands for development workflows — stacked PRs, code review, issue management, planning, and more.

Based on [tomzx/dot-claude](https://github.com/tomzx/dot-claude).

## Setup

```bash
git clone git@github.com:stex2005/dot-claude.git ~/.dot-claude
cd ~/.dot-claude
./install.sh
```

This copies commands to `~/.claude/commands/`.

## Commands

### Stack workflow
| Command | Description |
|---|---|
| `/stack-commit` | Classify changes against the plan, commit to the correct step branch, auto-advance |
| `/stack-create-pr` | Create PRs for all steps or a single step across repos, with cross-references and stack/cross-repo tables. Retarget after merges |
| `/stack-create-diagram` | Visualize the PR stack as a draw.io matrix diagram (supports forks) |
| `/stack-create-summary` | Generate or update a text summary of the stack — goals, repos, changes, status, risks, and features |
| `/stack-status` | Dashboard of step branches, PRs, and plan status per repo |
| `/stack-rebase` | Rebase the full chain of step branches when the base moves |
| `/stack-checkout` | Check out a specific step branch across all repos |

### Planning
| Command | Description |
|---|---|
| `/start-plan` | Break work into numbered phases before starting |
| `/save-plan` | Persist the current plan to disk |
| `/resume-plan` | Pick up where you left off on a saved plan |
| `/prune-plans` | Analyze and clean up stale plans |

### Code review & PRs
| Command | Description |
|---|---|
| `/pr-review` | Comprehensive code review of a GitHub PR |
| `/address-pr-comments` | Review and address PR comments with user approval per comment |
| `/handle-pr-comment` | Reply to a specific PR comment, implement or explain rejection |
| `/commit` | Lint, format, and commit changes on the current branch |
| `/rebase` | Rebase current feature branch on default branch and push |

### Issues
| Command | Description |
|---|---|
| `/create-issue` | Create a GitHub issue with background, acceptance criteria, and time budget |
| `/prepare-issue` | Analyze an issue, assess info sufficiency, create implementation plan |
| `/handle-issue-comment` | Reply to an issue comment using codebase context |
| `/label-issue` | Auto-label an issue based on its description |

### Documentation & specs
| Command | Description |
|---|---|
| `/directory-to-spec` | Convert a directory's code into specification files |
| `/spec-review` | Review a spec for ambiguities, inconsistencies, missing info |
| `/divio-documentation` | Generate docs following the Divio/Diataxis system |
| `/create-diagram` | Create a draw.io XML diagram from code or description |

### Testing
| Command | Description |
|---|---|
| `/run-tests` | Run the task-executor pytest suite locally — sources the common `.env`, pulls the S3 `boxes.json` fixture. Optional arg: test path, `-k <pattern>`, `e2e`, or `cov` |

## License

MIT. See [LICENSE](LICENSE).

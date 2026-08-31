# `gh stack view --json` reference

Measured against **gh 2.98.0** + **gh-stack v0.1.0** on 2026-08-31.

The `stack-*` commands are written against this shape. Re-verify after
upgrading the extension — it is v0.1.0 and in public preview.

## Captured output

From a three-layer local stack with no remote (hence no `pr` objects):

```json
{
  "trunk": "main",
  "currentBranch": "08-31-add_c_layer",
  "branches": [
    {
      "name": "test-layer1",
      "base": "f03bc5d18094e4a6e17f9f58b39621def1f4358c",
      "isCurrent": false,
      "isMerged": false,
      "isQueued": false,
      "needsRebase": false
    },
    {
      "name": "08-31-add_c_layer",
      "base": "034de4340e0b564bc95be23db15a3d947aebf555",
      "isCurrent": true,
      "isMerged": false,
      "isQueued": false,
      "needsRebase": false
    }
  ]
}
```

## Field notes

| Field | Notes |
|---|---|
| `trunk` | Branch name of the stack's trunk. |
| `currentBranch` | Branch name, not an index. |
| `branches` | Ordered **bottom-first**: `branches[0]` is closest to trunk. |
| `branches[].name` | Branch name. There is no title/description field. |
| `branches[].base` | **A commit SHA, not a branch name.** Do not treat it as the parent branch name — derive the parent from array order instead. |
| `branches[].isMerged` / `isQueued` / `needsRebase` | Booleans, always present. |
| `branches[].pr` | **Omitted entirely when no PR exists** (`json:"pr,omitempty"`). Commands MUST tolerate its absence rather than assuming a null. |

## The `pr` object

Not observable from a remote-less repo. The extension binary carries struct
tags `number`, `state`, and `url` alongside `pr,omitempty`, so the expected
shape is:

```json
"pr": { "number": 42, "state": "OPEN", "url": "https://github.com/..." }
```

**This shape is inferred from struct tags, not yet observed live.** Confirm it
against a real stack with open PRs before relying on the exact key names.

## Behaviors confirmed by experiment

- `gh stack init` works in a repo with **no remote**, which makes local
  fixture testing possible without creating throwaway GitHub repos.
- Auto-generated branch names are `MM-DD-<slug_from_commit_message>`, e.g.
  `Add c layer` produced `08-31-add_c_layer`.
- `gh stack add -Am` on a branch with **no commits yet** commits to that branch
  instead of creating a new layer, and warns:
  `Branch <x> has no prior commits — adding your commit here instead of
  creating a new branch`. `/stack-commit` must expect this on the first commit
  after `/stack-start`.
- `.currentBranch` is **not always present in `.branches`.** With trunk checked
  out, `gh stack view --json` reports `"currentBranch": "main"` while `.branches`
  holds only the stack's layer branches. Any command that derives a step number
  or attaches "(current)" by locating `.currentBranch` inside `.branches` must
  define that case rather than assume a match. `gh stack sync --prune` produces
  it routinely: per `gh stack sync --help`, if you are on a branch that would be
  pruned, "your checkout is moved to the first active branch in the stack, or
  the trunk if all are merged."

## Exit codes

Measured here. The contract commands are written against is restated in
`stacked-pr-workflow.md#exit-codes`.

| Code | Command(s) | Meaning |
|---|---|---|
| `2` | `gh stack view`, and the rest | Not in a stack / stack not found. |
| `3` | `gh stack sync`, `gh stack rebase` | Rebase conflict. `sync` restores every branch to its pre-sync state first; `rebase` leaves the repo mid-rebase for interactive resolution. Load-bearing for `/stack-rebase`'s Step 2. |
| `6` | `gh stack view --json` | The current branch belongs to more than one stack, so there is no single stack to report. |

Exit 6 reproduction, in a local fixture with no remote — `gh stack init --base
main s1-base`, then `gh stack init --base main s2-base`, then `git checkout
main`:

```
$ gh stack view --json
✗ branch "main" belongs to multiple stacks; checkout a non-trunk branch first
$ echo $?
6
```

Trunk is the branch that ends up in several stacks, because every `gh stack init
--base <trunk>` roots another stack there. From any non-trunk branch the answer
is unambiguous again and `gh stack view --json` exits 0.

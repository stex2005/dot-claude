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
- Exit code 2 means "not in a stack / stack not found".

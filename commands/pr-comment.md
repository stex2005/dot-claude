---
description: Turn /pr-review findings into PR comments — drafted one at a time, short, human-like and actionable, posted only on your go-ahead.
allowed-tools: Bash(gh *), Bash(git *), Read, Write, Grep, Glob
argument-hint: <pr-number|url> [finding numbers]
---

## Goal

After a `/pr-review`, turn its findings into comments a teammate would write: a little context, the concrete failure, one clear ask. Draft them one by one. Post a comment only when the user says so.

## Input

- Use the findings from the `/pr-review` earlier in this conversation. If there isn't one, run `/pr-review $ARGUMENTS` first.
- If the arguments name finding numbers, draft only those. Otherwise go through them in priority order (MUST, then SHOULD, then MAY).
- Before drafting, ask whether any decisions have changed findings, e.g. "these two PRs merge together". Then drop or reword the findings those decisions affect.

## Drafting each comment

One finding per comment. Keep it to 2–4 sentences, plus one short follow-up paragraph if it needs it.

1. **Context, one sentence.** Say what the code does here that matters. Don't re-explain the PR.
2. **The failure.** Give the concrete scenario and its effect ("the arm runs the full trajectory after TE thinks it stopped"). When it's a race or an edge case, say how likely it is, for example "usually a few ms, up to the 1 s timeout".
3. **The ask.** Phrase it as a question or suggestion ("Could `dispatch()` check…?"). Name the function or line, but don't paste a full implementation.

Tone and style:
- Write like a colleague: "we", "could we", "I think". Assume competence.
- Don't use severity labels like MUST or SHOULD. For small things, start with "Minor:".
- Don't use reviewer-speak ("Per the review…", "This PR introduces…").
- Cite `file:line` or symbols in backticks. Refer to other comments by file and line ("the gateway race in `gateway.py:156`"), never by "above" or "below". Inline comments on different files don't appear in order.
- Only mention a comment on another PR if it is already posted, or posted in the same batch.
- Fold in context the user gives you (e.g. "we need debugger changes"), in their framing.

## Where it goes

- **Line-specific comment:** post inline on the PR head commit.
  - One line: `gh api repos/<owner>/<repo>/pulls/<n>/comments -X POST -f commit_id=<headRefOid> -f path=<path> -F line=<n> -f side=RIGHT -F body=@<file>`
  - A range: also pass `-F start_line=<a> -f start_side=RIGHT`
  - Check the line text in the PR head before posting.
- **Cross-cutting or cross-repo comment:** post on the PR conversation with `gh pr comment <n> -R <owner>/<repo> -F <file>`.
- Write each body to a file in the scratchpad and post with `-F body=@file`, so backticks and quotes survive.

## Loop

1. Show one draft at a time. Use a heading with the PR and anchor (`te#955 · gateway.py:156`), then the body as a blockquote.
2. The user may say "simpler", "shorter", "minor", or add context. Redraft and show it again. Don't post yet.
3. Post only on an explicit go-ahead ("post it", "post 3"). Rewording or reverting a draft is not a go-ahead.
4. After posting, give the comment URL. Point out anything in the posted text that's now wrong, such as a reference to an unposted comment. Offer to fix it by editing (`gh api repos/<owner>/<repo>/pulls/comments/<id> -X PATCH -F body=@file`), not by deleting and reposting.
5. End each step by saying which drafts are still unposted.

Never submit a formal review (approve or request changes) unless asked. Post single comments.

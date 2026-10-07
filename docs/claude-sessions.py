#!/usr/bin/env python3
"""List Claude Code sessions: last-active, session id, title, git branch, launch dir.

Usage: python3 ~/.claude/docs/claude-sessions.py [filter ...]
Every filter word must appear (case-insensitive) in the title, branch, cwd or id.
Newest first. Reads ~/.claude/projects/*/*.jsonl; never writes.
"""
import json, os, sys, glob, datetime, signal
signal.signal(signal.SIGPIPE, signal.SIG_DFL)

def meta(path):
    title = branch = cwd = None
    with open(path, errors="replace") as f:
        for line in f:
            if '"customTitle"' not in line and '"gitBranch"' not in line and '"cwd"' not in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            title = d.get("customTitle") or title
            branch = d.get("gitBranch") or branch
            cwd = cwd or d.get("cwd")  # launch dir = first cwd; `claude --resume` must run there
    return title, branch, cwd

words = [w.lower() for w in sys.argv[1:]]
rows = []
for p in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
    sid = os.path.basename(p)[:-6]
    title, branch, cwd = meta(p)
    hay = " ".join(x or "" for x in (title, branch, cwd, sid)).lower()
    if all(w in hay for w in words):
        rows.append((os.path.getmtime(p), sid, title or "-", branch or "-", cwd or "-"))
for m, sid, title, branch, cwd in sorted(rows, reverse=True)[:40]:
    print("\t".join((datetime.datetime.fromtimestamp(m).strftime("%Y-%m-%d %H:%M"), sid, title, branch, cwd)))

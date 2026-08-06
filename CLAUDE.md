# Witness iOS — Working Agreement for Claude Code

## Permission and change control (READ FIRST)
- Do NOT modify, refactor, or delete any existing file without first
  explaining the proposed change and getting my explicit approval.
- Propose changes as a diff and WAIT for me to say yes before writing.
- One change at a time. Do not batch multiple edits across files without
  walking me through each and getting a go-ahead.
- Never revert, overwrite, or "clean up" code you did not just write in
  this session without asking.
- If a task seems to require touching code beyond what I asked for, STOP
  and tell me what and why — do not expand scope on your own.

## Truth and correctness
- The files in this repo are the source of truth. Do not rely on memory of
  an API's shape — read the actual file (e.g. Hints.swift) before using it.
- Do not report that something compiles or "has no issues" unless you have
  actually verified it. If you haven't verified, say so plainly.

## This project's locked rules (do not violate)
- Design system is locked: WV/WT tokens, parchment + teal, Playfair serif,
  the door = entry-world-only rule, white cards on flat parchment.
- Companion name is dynamic (default "Scarlett"), read from
  Profile.companionNameKey — never hardcode it.
- Muhammad Rule: human testimony always overrides AI inference.
- Amy Rule: first-name-only mentions never auto-resolve.
- Never use real people from my life as sample data — use generic roles.

## How I work
- I am new to Xcode/macOS; when a step happens in Xcode, spell it out.
- Prefer complete, reviewable changes I can read before accepting.
- Commit points are deliberate. Do not run git commit or push unless I ask.

# Witness — Real memory detail wired (/detail) + adapter retired + large-narrative fix — Result

Date: 2026-08-09. Build **0 errors / 0 warnings**. No git.

## Applied
### New models — APIModels.swift
- `MemoryDetailDTO` (all fields optional/lenient; `exactDateEstimated: Bool?` three-state; scores `Double?`).
- `MemoryPerson {id?, canonical_name?, entity_type?, is_anchor?, role_in_memory?}` — OBJECTS (anchors-first),
  the contract difference from the list's `[String]`.
- `MemoryEmotion {emotion_type?, intensity?, trigger_description?}`, `MemoryQuote {quote_text?, emotional_tone?, speaker_name?}`.
- All with explicit snake_case `CodingKeys`.

### New — MemoryDetailViewModel.swift
- `load(id:auth:)` / `retry(id:auth:)`, `LoadState`, same 401→refresh→retry-once path as the list VM.
- Publishes `detail` + pre-split `paragraphs: [String]`.
- `splitNarrative` (nonisolated, run via `Task.detached` → OFF the main thread): PRIMARY split on
  paragraph breaks (blank lines / double newlines) so paragraphs stay intact; FALLBACK word-boundary
  hard-wrap for any paragraph > 4000 chars; plus a character hard-cut backstop for a pathological
  space-less token. No `wordCount` main-thread split anywhere.

### Rebuilt — MemoryDetailView.swift
- Now `listItem: MemoryDTO` (id + instant header) + `auth` + its own `@StateObject` detail VM;
  `.task { load(id: listItem.id, auth:) }`.
- Header (date/title instant from the list item; people-chips from `detail.people` via FlowLayout,
  anchors accented gold). Loading = spinner; failed = friendly Retry (never blank).
- Narrative = `ForEach` of the pre-split paragraphs in a `LazyVStack`, **no `.fixedSize`** — the fix.
- New Emotions section (type + intensity dots + trigger) and Quotes section (blockquote + speaker/tone).
- Read aloud + the recording player moved ABOVE the narrative (reachability on huge memories).

### MemoriesView.swift
- Destination → `MemoryDetailView(listItem: dto, auth: auth)`.
- Deleted the temp `SampleMemory(dto)` adapter, `struct SampleMemory`, and `.samples`. Kept MemoryCard + MemoryFormat.

### TalkView.swift
- `memory: SampleMemory?` → `MemoryDetailDTO?`; opening line tolerates a nil title. Now carries the real server id.

## Verified (RunCodeSnippet — actually executed, not asserted)
| Input | Result |
| --- | --- |
| ~174K chars, ONE paragraph (April 28 worst case) | 44 chunks, max 4000 chars, 0 over cap |
| Normal paragraphed narrative | 3 chunks — each an INTACT paragraph, not choppy single lines |
| Pathological 20K space-less token | 5 chunks of 4000 (char hard-cut backstop) |
| Empty string | 0 chunks (no crash) |

So the April 28 narrative renders as ≤44 bounded Text views in a LazyVStack → no single oversized
Text → no blank; and ordinary paragraphs stay whole and readable.

## Honest scope
- VERIFIED: full build 0/0; per-file diagnostics 0 issues; splitter behavior executed on-device-class
  logic via RunCodeSnippet (table above). One build error was hit and fixed mid-apply: the `@MainActor`
  VM's static splitter couldn't be called from `Task.detached` — marked `splitNarrative`/`hardWrap`
  `nonisolated`; rebuilt clean.
- NOT run interactively against the live backend — the /detail decode, the emotions/quotes layout, and
  the anchors-first people order are wired per the contract but unconfirmed against real JSON. Worth an
  on-device pass on the April 28 memory (renders + scrolls) and one memory with emotions/quotes.
- FLAGGED — two placeholder chips removed in the rebuild: the old detail screen had "Add media" and
  "Create image" buttons (pure TODOs, no backend) and a wordCount/texture metadata row (wordCount was
  the main-thread 174K split we were told to drop; texture was a fabricated location stand-in). The
  rebuild per your section list (header / narrative / emotions / quotes / Listen+Read-aloud) omits them.
  Say the word and I'll re-add Add media / Create image as disabled placeholders.
- DEFERRED (approved): Read-aloud still passes the full narrative; on the 174K memory that's impractical
  (hours of TTS, possible utterance limits) — untested, capping is a separate follow-up.

## No git.

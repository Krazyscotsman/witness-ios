# Witness — Conversation history (Ask Scarlett + Talk) — Result

Date: 2026-08-16. Build **0 errors / 0 warnings**. No git. Read-only, no audio/composer.

## Applied
- **APIModels.swift** — two SEPARATE list models + transcript model (all `nonisolated`, `.convertFromSnakeCase`):
  - `MemoryConvSummary` (id, startedAt, endedAt?, turnCount, summary?, status) + `MemoryConversationsResponse`.
  - `RecentConvSummary` (id, **memoryId: String?**, memoryTitle?, status, startedAt?, turnCount, summary?) +
    `RecentConversationsResponse`, with `static normNone(_:)` (nil/""/"None" → nil), `memoryIdNorm`, and
    **`isWholeLife { normNone(memoryTitle) == nil }`** (discriminate by memory_title, not memory_id).
  - `ConversationTurn` (turnNumber, role, content, phase?, turnType?, createdAt) + `ConversationTurnsResponse`.
- **ConversationHistory.swift** (NEW) —
  - `ConversationHistoryViewModel`: `loadMemory(memoryId:)` → `GET /api/v1/jarvis/memories/{id}/conversations`;
    `loadTalk()` → `GET /api/v1/jarvis/conversations/recent?limit=50` then **`.filter { $0.isWholeLife }`**.
    Maps either DTO → a shared `ConvRow`. LoadState loading/loaded/empty/failed; 401→refresh→retry; warm empties.
  - `TranscriptViewModel`: `load(conversationId:)` → `GET /api/v1/jarvis/conversations/{id}/turns` → `[ChatMessage]`
    (**role == "user" → user, else companion**; empty content skipped).
  - `ConversationHistoryView(scope: .memory(id)|.talk)` — own NavigationStack, "Past conversations" title, Done
    button, rows (date · N turns · summary) → `NavigationLink` → `TranscriptView` (date/turn header, reuses
    `CompanionBubble`/`UserBubble`, **no composer, no audio/TTS**). `ConvFormat` parses ISO8601 (± fractional
    seconds) → "MMM d, yyyy · h:mm a", raw fallback. Companion name from `@AppStorage(Profile.companionNameKey)`.
- **AskScarlettView.swift** — `@State showHistory`; header clock button next to ✕ (only when `memory?.id`
  present); `.sheet { ConversationHistoryView(scope: .memory(memory?.id ?? "")) }`.
- **TalkView.swift** — `@State showHistory`; header clock button before Save & exit / New;
  `.sheet { ConversationHistoryView(scope: .talk) }`.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**:
  ConversationHistory, APIModels, AskScarlettView, TalkView (0 issues each). No transient error 5.

## Traps handled (the ones you flagged)
- **`memory_id == "None"`** → decoded as `String?` (never `UUID?`); `normNone("None") == nil` (no crash — the
  same class as the context_summary bug).
- **Whole-life filter = `memory_title == nil`** (not memory_id), hardened against `"None"`/empty title.
- **role** jarvis→companion, user→user (any non-"user" role → companion bubble).
- Two list models kept **separate**; shared transcript endpoint used for both scopes.

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend** (none on this machine). Verified: compile 0/0 + the load/map/filter/
  state machine + defensive decode. A device pass confirms: the memory list, the recent+filter (whole-life only),
  the shared transcript, and the "None"/nil normalization against real rows.
- **List `summary` typed `String?`** per the verified contract. If a `summary` ever returns as an OBJECT (the
  context_summary bug class), hardening is a one-line switch to the existing `JSONValue` — flagged as the one
  field with object-risk precedent; not changed, per your verified spec.
- Read-only: no composer, no audio/TTS on transcripts, as specified.

## No git.

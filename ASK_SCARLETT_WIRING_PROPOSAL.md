# Witness — "Ask Scarlett" wiring (Option B, memory-scoped shell) — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval.** No git.

## Scope
Wire askCard → present TalkView as a `.sheet`, scoped to the memory (opening line names it),
carrying the memory id (client-side UUID now → server id later; marked). Reuse TalkView;
keep the standalone Talk tab unchanged. Build only the shell: opening + scoping + id handoff.
Do NOT build questions, transcription, voice-answer record/playback, storage, dedup, or graph
— each seam marked with a placeholder noting the backend endpoint already exists.

## Diff 1 — TalkView.swift (add optional memory context; tab unchanged)

Add context + dismiss (after @AppStorage companion):
```diff
     @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
+    // Memory-scoped "Ask Scarlett": nil = the standalone Talk tab (unchanged).
+    var memory: SampleMemory? = nil
+    @Environment(\.dismiss) private var dismiss
```

Scoped opening + session placeholder (.onAppear):
```diff
-        .onAppear { if messages.isEmpty { messages = [ChatMessage(role: .companion, text: greetingText())] } }
+        .onAppear {
+            if messages.isEmpty { messages = [ChatMessage(role: .companion, text: openingText())] }
+            // PLACEHOLDER — backend already implements this; connect later:
+            //   POST /api/v1/jarvis/witness/sessions { memory_id: <server id> }
+            // Uses memory?.id (client-side UUID today; becomes the server memory id once
+            // memories load from the backend). No network call here yet.
+        }
```

New openingText():
```swift
    // Opening line: memory-scoped when launched from a memory's "Ask Scarlett", else the
    // standalone Talk greeting. The real loop — Scarlett's questions, voice answers
    // (record↔playback), transcription of both sides, transcript (text) storage, dedup so a
    // question is never re-asked, and knowledge-graph enrichment — all live on the backend
    // and connect later. This is the front-end shell only.
    private func openingText() -> String {
        if let memory {
            return "Let's talk about “\(memory.title).” What comes back to you when you return to it?"
        }
        return greetingText()
    }
```

Save & exit also dismisses the sheet (no-op in the tab):
```diff
     private func saveAndExit() {
         // Real: POST /api/v1/jarvis/witness/sessions/{id}/end
         composerFocused = false
         thinking = false
         gateUsed = false
         withAnimation { messages = [ChatMessage(role: .companion, text: greetingText())] }
+        dismiss()   // dismisses the memory-scoped sheet; no-op when this is the Talk tab
     }
```
(The mic-button comment `/* TODO: hold-to-speak -> on-device capture, then send transcript */`
already marks the voice-answer + transcription seam — transcription is a separate task.)

## Diff 2 — MemoryDetailView.swift (wire the button)

State (after audioURL):
```diff
     @State private var audioURL: URL?
+    @State private var showAsk = false
```

askCard action (line 235):
```diff
-        Button { /* TODO: open Talk anchored to this memory */ } label: {
+        Button { showAsk = true } label: {
```

Present the scoped sheet (after .onDisappear):
```diff
         .onDisappear { audioPlayer.stop() }
+        .sheet(isPresented: $showAsk) {
+            // Memory-scoped "Ask Scarlett" — opens TalkView about this memory.
+            // Passing the whole memory for its title (opening line) + id (session handoff);
+            // memory.id is a client-side UUID today → server memory id once wired.
+            TalkView(memory: memory)
+        }
```

## Does / doesn't
- Does: tap opens TalkView as a sheet, opening line names the memory, passes memory id,
  Save & exit / swipe closes it.
- Doesn't: no questions, voice loop, transcription, storage, dedup, or graph — all marked
  placeholders citing existing backend endpoints. Standalone Talk tab unchanged.

## After approval
Apply both diffs → build 0/0 → report honestly (verified by build; opening/scoping are
simulator-checkable). No git.

# Witness — Memory playback ("Listen") proposal

Status: **PROPOSED — nothing applied. Awaiting approval.** No git. Reuses existing AudioPlayer.

## Read-first findings
1. Listen affordance: inert chip in `actionsRow` (MemoryDetailView) —
   `actionChip("speaker.wave.2.fill", "Listen") { /* TODO: GET /memories/{id}/audio */ }`,
   in a 3-chip row (Listen · Add media · Create image). Best fit: keep the row, wire the
   Listen chip to real play/pause, reveal a compact player bar below actionsRow (before
   askCard) when audio exists — no disruption to cover/title/narrative/metadata/Ask.
2. Memory model `SampleMemory`: NO audio reference (only title, excerpt, date, kind,
   people, narrative, wordCount, texture). Identity is `let id = UUID()` — a client-side
   random UUID, NOT a backend id. Nothing points at per-memory audio yet; no stable server
   id to fetch with. Eventual GET /memories/{id}/audio needs a real id later.

## Design choice flagged
Listen chip becomes play/pause (disabled+dimmed when no audio); compact `listenPlayer` bar
(teal play/pause + progress + mm:ss, mirrors saved-screen) shows below when audio exists.
Wart: both chip and bar can toggle play/pause (harmless redundancy). Alternatives: drop the
chip's play role, or replace the chip with the bar. Say which you prefer.

## Diff — MemoryDetailView.swift

State (after line 6):
```diff
     @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName
+    @StateObject private var audioPlayer = AudioPlayer()
+    @State private var audioURL: URL?
```

Body insert (lines 30–31):
```diff
                         actionsRow.padding(.top, 8)
+                        if audioURL != nil { listenPlayer.padding(.top, 12) }
                         askCard.padding(.top, 4)
```

Lifecycle (after toolbar modifiers, line 44):
```diff
         .navigationBarBackButtonHidden(true)
         .toolbar(.hidden, for: .navigationBar)
+        .onAppear {
+            audioURL = resolveMemoryAudioURL(for: memory)
+            if let url = audioURL { audioPlayer.load(url) }
+        }
+        .onDisappear { audioPlayer.stop() }
```

Listen chip (lines 125–132):
```diff
     private var actionsRow: some View {
         HStack(spacing: 10) {
-            actionChip("speaker.wave.2.fill", "Listen") { /* TODO: GET /api/v1/memories/{id}/audio */ }
-                .witnessHint("Hear this memory read aloud in \(companion)'s voice.")
+            actionChip(audioPlayer.isPlaying ? "pause.fill" : "speaker.wave.2.fill",
+                       audioPlayer.isPlaying ? "Pause" : "Listen") { toggleListen() }
+                .disabled(audioURL == nil)
+                .opacity(audioURL == nil ? 0.45 : 1)
+                .witnessHint("Play this memory's audio recording.")
             actionChip("photo.badge.plus", "Add media") { /* TODO: POST /api/v1/memories/{id}/media */ }
             actionChip("wand.and.stars", "Create image") { /* TODO: POST /visualize/{id} */ }
         }
     }
```

New members:
```swift
    // Compact playback bar (mirrors the saved-screen player). Shown when audio exists.
    private var listenPlayer: some View {
        HStack(spacing: 14) {
            Button { toggleListen() } label: {
                ZStack {
                    Circle().fill(WV.teal)
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
            }
            .witnessPress()

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WT.ink.opacity(0.1))
                        Capsule().fill(WV.teal)
                            .frame(width: max(0, geo.size.width * audioPlayer.progress))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(mmss(audioPlayer.currentTime))
                    Spacer()
                    Text(mmss(audioPlayer.duration))
                }
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(WT.ink.opacity(0.5))
            }
        }
        .padding(16)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    private func toggleListen() {
        guard audioURL != nil else { return }
        if audioPlayer.isPlaying { audioPlayer.pause() } else { audioPlayer.play() }
    }

    private func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%01d:%02d", s / 60, s % 60)
    }

    /// Resolves the audio to play for a memory.
    /// PLACEHOLDER until GET /api/v1/memories/{id}/audio: the real implementation will
    /// download the memory's audio from the backend using the memory's server id
    /// (SampleMemory currently only has a client-side UUID, not a server id).
    /// For now, play the most-recent local recording in Documents/Recordings/, or nil.
    private func resolveMemoryAudioURL(for memory: SampleMemory) -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        return files
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }
```

Empty state: nil URL → Listen chip disabled + dimmed, no bar. (Can add an explicit
"No recording to play yet" line if you prefer a visible message.)

## After approval
Apply → build 0/0 → report honestly. Playback is device/simulator-checkable (plays a real
local .m4a). No networking implemented (placeholder comment only). No git.

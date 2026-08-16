# Witness iOS — Graph (Insights → Graph) diagnosis

**Date:** 2026-08-16. Report only — no code changed. **Cannot run the app/backend from this machine**, so "live
render" is reasoned from code + your device; the proposed DEBUG logging pins it in one launch.

## 1. What renders — three code-determined branches (GraphView switches on vm.state)
| State | Screen | Root cause |
|---|---|---|
| `.unavailable` | "Graph unavailable / try again later" | `GET /api/v1/graph` → **404** (flag/route) |
| `.failed` | "We couldn't load your graph. Check your connection…" + Try again | **decode mismatch** (witness-class) OR transport — generic catch masks both |
| `.empty` | "Not enough connections yet" | decoded OK but `nodes ≤ 1 || edges empty` |
| `.loaded` | header + force-directed canvas + filters | decoded OK → engine runs on real 95/56 |

The "broken" outcomes are `.failed` (looks like network, but with a live backend almost certainly a DECODE
mismatch) or a `.loaded` clump (decode fine, engine can't handle 95 nodes — §3).

## 2. Data layer
`GraphViewModel.fetch()` → `APIClient.get("/api/v1/graph", timeout:30, decoder: snake(convertFromSnakeCase),
as: GraphResponse.self)`. Structs (APIModels.swift:710–749):
- GraphResponse { narratorId?, narratorNodeId?, nodes[]?, edges[]?, stats? }
- GraphNode { id:String(REQ), label?, type?, isAnchor:Bool?, isNarrator:Bool?, memoryCount:Int?,
  aliases:[String]?, nameComplete?, anchorRelType?, birthDate?, deathDate?, color?, borderColor?, size:Double? }
- GraphEdge { id?, source:String(REQ), target:String(REQ), relationshipType?, strength:Double?, memoryCount?,
  lineStyle?, color?, width:Double?, label? }
- GraphStats { totalNodes?, totalEdges?, anchorCount? }

A mismatch on ANY declared field (even optional) throws typeMismatch and fails the WHOLE response → `.failed`
(the generic catch mislabels it "connection" — the context_summary trap). Highest-risk to check vs raw JSON:
- isAnchor / isNarrator as 0/1 ints (not bools) → Bool? still throws.
- id / source / target as numbers → required String throws.
- any String? field as object/number (color, label, type, anchorRelType, nameComplete) → throws.
- aliases as objects instead of [String] → throws.
- size/strength/width as ints → fine.

Cannot compare raw-vs-expected without the body (no backend here). Proposed DEBUG logging (NOT applied):
```swift
// APIClient.swift — request(), after the HTTPURLResponse guard
#if DEBUG
if url.absoluteString.contains("/api/v1/graph") {
    print("🩺[Graph] \(method) \(url.absoluteString) → \(http.statusCode)  bytes=\(data.count)  body=\(String(data: data, encoding: .utf8)?.prefix(800) ?? "")")
}
#endif
```
```swift
// GraphViewModel.swift — generic catch in fetch()
} catch {
    #if DEBUG
    print("🩺[Graph] caught: \(error)")
    #endif
    state = .failed("We couldn’t load your graph. Check your connection and try again.")
}
```
Prints status (200 vs 404 → §5), raw body (shape vs structs), and the exact DecodingError (key/type) if decode.

## 3. Render layer — hand-written engine at 95 nodes / 56 edges
GraphLayout = naive spring/repulsion on a 60fps Timer:
- Seeding: all non-narrator nodes on ONE circle radius 110 around center → 95 nodes start massively overlapped.
- Forces tuned for the 12-node sample: kRep 8500, rest 86, kSpring 0.025, pull 0.006, velocity clamp ±12,
  positions HARD-CLAMPED to screen ([30…width-30]×[30…height-70]). On a phone canvas ~390×600, 95 nodes
  (~28–52px each) can't fit without heavy overlap → dense unreadable clump piled at the bounds.
- Perf/settling: repulsion O(n²) (~4.5k pairs/frame — cheap) BUT `@Published nodes` is reassigned every frame,
  so SwiftUI re-diffs the entire ForEach(95 node views, each with DragGesture + Text) + Canvas redraw 60×/sec —
  the likely "frozen/janky" feel; with 95 jittering nodes it may NEVER hit calm (maxSpeed<0.4 ×40) → runs 60fps
  indefinitely.
- Styling: uses the APP PALETTE (RelGroup color, radius from memoryCount, edge width from strength). Backend
  precomputed color/border_color/size/width are decoded but IGNORED by design.
- Edges: plain Canvas lines by group color; no labels, no arrowheads.
- Default mode `.ego` (narrator + neighbors) reduces the clump; `.web` shows all 95 → worst overlap.
Even if decode succeeds, the engine is not tuned for this volume.

## 4. Gap vs web graph lib
Missing: zoom/pan, fit-to-viewport, edge labels, clustering/bundling, stabilization (cooling/alpha decay),
off-main/worker or GPU layout, incremental rendering. Web runs d3-force/WebGL in a worker on an infinite,
zoomable canvas; the Swift engine is main-thread, full-array republish per frame, fixed screen bounds.

## 5. Flag path / 404?
VM maps 404 → `.unavailable`. Flag is ON per you, so data should be 200 → decode path (flag likely NOT the
issue). The DEBUG `→ <status>` line resolves it: 404 = flag/route (.unavailable); 200 = data arriving → decode
(.failed) or engine (.loaded clump).

## Verdict — data or render or both?
Can't pin to one layer without the raw status/body; plausibly BOTH:
- Data (decode) is the first gate and prime suspect for a `.failed` screen (witness-class mismatch masked as
  "connection"). Logging confirms in one launch.
- Render (engine) is a KNOWN static problem at 95 nodes regardless of decode — untuned forces, single-ring
  seeding, screen-clamped bounds, 60fps full-array republish, no zoom → overlapping/frozen/unreadable.

If the log shows 200 + clean body → purely the engine (§3/§4), which realistically wants a rebuild
(zoom/pan + settling, or a real graph lib) over parameter tweaks. If it shows a DecodingError → data first
(quick DTO fix), then still the engine.

## Next step (not applied)
Approve the DEBUG logging and I'll apply it (build 0/0); open Graph and paste the `🩺[Graph]` line — then we
know decode vs engine and can scope the actual fix. No git.

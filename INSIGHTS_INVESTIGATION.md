# Witness — Insights tab map (pre-wiring investigation)

Date: 2026-08-12. Read-only. No build, no source changes, no git.

## Structure
`InsightsView` is a hub: a featured **Explain** card + a list of rows, each pushed via
`.navigationDestination(for: InsightItem.self)`. Seven destinations (below). `InsightSurfaceView` is a generic
"coming together" placeholder — only a fallback; all six non-anchor rows have real destinations.

## Per sub-section
| Section | Screen | State | Displays | Data today | Endpoint(s) noted |
| --- | --- | --- | --- | --- | --- |
| Explain Me (featured) | ExplainView | Shell + sample | 7 tabs: Overview/Forces/Breaking Points/Patterns/Contradictions/Identity/Beliefs — "synthesis of a life" | hardcoded `ExplainSample` structs | GET /api/v1/explain-me/overview\|active-forces\|patterns\|breaking-points\|contradictions\|identity\|beliefs; Read→TODO /tts/generate |
| Timeline | TimelineView | Shell + sample (mixed) | Narrative (year-grouped event cards, 6 filters, search, expand) + Pattern ("Life Anchor Rails") | Narrative = `TimelineEvent.samples`; Pattern rails read the OLD local `AnchorStore` (UserDefaults), NOT the backend registry | GET /api/v1/timeline/visual; GET /timeline/{category}; View memory→TODO |
| Memoir | MemoirView | Shell (faked generate) | Config form → generating → ready → Download PDF; AtmosphereModal enrich | local @State + hardcoded presets; generate = 2.2s asyncAfter; download TODO | POST /memoir/preview, /memoir/generate, /memoir/atmosphere |
| Learn | LearnView | Shell + sample | Whole-life Q&A: 5 modes, ask box, 8 lens presets, reflection cards (answer + confidence + cited memory/entity sources) | `LearnReflection.sample` (1.6s fake) | POST /api/v1/learn/chat {message,mode,session_id}→{answer,confidence,query_type,sources}; /tts/generate |
| Anchors | AnchorRegistryView | ✅ WIRED | Registry 7 categories → list → read/edit/create | real /timeline/{category} GET/PUT/POST | done this session |
| Graph | GraphView | Shell + sample | Native force-directed relationship map (custom engine, ego/web, group filters, node detail) | `GNode.samples`/`GEdge.samples` | GET /api/v1/graph → {nodes,edges,stats} |
| Media | MediaView | Shell + sample + local | Gallery photos/video/audio | `MediaGroup.samples` + local MediaStore | GET /api/v1/media/gallery, /media/{id}/file, DELETE /media/{id} |

## Existing wiring / DTOs
None beyond Anchors. No APIClient calls / DTOs / view models for Explain, Timeline, Memoir, Learn, Graph, or
Media — only TODO comments naming endpoints. Reusable patterns already exist: `APIClient.get/post`,
`nonisolated` DTOs, `AnchorRegistryViewModel` (fetch/state/401-refresh). 
⚠️ Inconsistency: Timeline Pattern rails still read the stale local `AnchorStore`, not the backend registry.

## Highest-value / lowest-risk to wire first (assessment)
1. **Explain Me** — featured centerpiece; read-only, 7 GET endpoints, no writes/no 500-footgun; high payoff. Best first.
2. **Graph** — one GET /api/v1/graph; layout engine already works → swap samples for real nodes/edges.
3. **Learn** — high value; single POST /learn/chat with cited sources; medium effort.
4. **Timeline** — central; wire /timeline/visual + move Pattern rails off the local store onto the real registry.
5. **Memoir** — biggest/most complex (long generation + PDF, word-cap coordination); lower priority.
6. **Media** — separate media concern (gallery + file streaming).

No build. No git.

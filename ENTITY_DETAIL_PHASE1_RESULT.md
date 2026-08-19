# Witness — Entity Detail Page, Phase 1 (gate + entry + scaffold) — Result

Date: 2026-08-19. **Build: 0 errors / 0 warnings.** No git.

## Applied
- **YouView.swift** — `Profile.enableDetailsKey` ("settings.enableDetails", Bool) local mirror.
- **APIModels.swift** — `ProfileDTO.enableGraphView` (`enable_graph_view`, read); `ProfileUpdateRequest.enableGraphView`
  (`var … = nil`, sent alone by the toggle, omitted by the editor); `EntityDetailDTO.attributes: JSONValue?`
  (opaque, decode-safe, never dumped).
- **AuthManager.swift** — `applyProfile` mirrors `enable_graph_view` into `Profile.enableDetailsKey` at launch.
- **SettingsView.swift** — new **Advanced** section: "Enable Details View" toggle → **optimistic** local mirror +
  background `PUT /settings/profile { enable_graph_view }`; **reverts + inline error** on failure; disabled while saving.
- **EntityDetailPage.swift (NEW)** — `EntityDetailViewModel` fetches `GET /api/v1/entities/{id}` (401→refresh),
  states idle/loading/loaded/failed. Renders: **Header** (kicker pills Entity Detail/type/Anchor/relationship,
  name, meta pills incl. linked-count, Read Aloud via `Speaker`), **Summary cards** (Entity type · Anchor · Linked
  memories · **Populated sections** = non-empty top-level attribute keys, counted opaquely), and **Linked
  Memories** (open by default; title/date/role; tap → `MemoryDetailView`). `EntitySeed` gives an instant header
  while loading.
- **Entry points ("Show more" / "See everything"), gated on Enable Details:**
  - **Graph — `NodeDetailSheet`**: "Show more" → `EntityDetailPage(entityId: node.id, …)`.
  - **People anchor — `RelationshipDetailView`** (RelationshipEditor.swift): "See everything" → `EntityDetailPage(
    entityId: row.personEntityId, …)`, shown only when `personEntityId` is present.

## Refinement vs. the proposal (reported honestly)
- The proposal targeted `AnchorRecordDetailView` + a new `AnchorRow.entityIdForDetail`. On closer read, that
  generic detail is used **only for non-people categories** (location/job/education/pet — which have no entity id),
  while the **people** read-detail is a separate view, **`RelationshipDetailView`**, which already holds the
  `RelationshipRow` (with `personEntityId`) **and** `auth`. So I wired "See everything" there and used
  `row.personEntityId` **directly** — no protocol change, no `auth` threading through the generic list. Same
  approved behavior (people anchors only), less surface area.
- **`EntityDetailPage` linked-memory taps use destination-closure `NavigationLink`s** (not value-based) and it does
  NOT register its own `navigationDestination(for: MemoryDTO.self)` — so pushing it inside the graph sheet's stack
  (which already registers that destination) can't create a duplicate-destination conflict, and it still works from
  the anchor path (Insights stack).

## Verified
- **BuildProject → 0 errors**; **0 warnings** across all touched/new files (EntityDetailPage, APIModels,
  SettingsView, NodeDetailSheet, RelationshipEditor, AuthManager, YouView).
- Two build fixes en route to 0/0: added `import Combine` to the new VM file (ObservableObject), and replaced a
  heterogeneous `[String, String?]` array literal with an explicit build for `joined`.

## Honest caveats (device/backend — not runnable here)
- **Spec file still absent** (`Witness_Entity_Detail_Page_Spec.md`); built to the prompt. The header pills derived
  from `attributes` (`relationship_type`, `significance`, `date`/`first_seen`) and the exact "Populated sections"
  semantics are **provisional** and will be reconciled with the real `attributes` shape in later phases.
- The live `/entities/{id}` payload, the toggle's `PUT` round-trip, and the gate flow are device checks. The gate
  only reflects the backend value after a profile fetch (`applyProfile`); the toggle also mirrors instantly.

## Next (Phases 2–5, not started)
dialogue_spoken, people_details, romantic/arcs, remaining sections — each reading specific `attributes` keys.

## No git.

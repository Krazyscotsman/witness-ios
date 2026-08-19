# Witness iOS — impact of backend API-surface changes (investigation)

Date: 2026-08-19. Report-only except item 1 (fix only if breaking). **No code changed** — nothing was breaking.
Build re-confirmed **0 errors / 0 warnings**. No git.

---

## 🔴 1. `propagation_count` removed from GET /api/v1/explain-me/active-forces — NOT BREAKING (no fix needed)
- **Grep `propagation_count` / `propagationCount` across the repo → 0 matches.** iOS never declared or read it.
- The Active Forces tab decodes into **`ExForceDTO`** (APIModels.swift), whose fields are:
  `forceId, title, originEventTitle, originDate, activeToday, activeStrength, affectedDomains,
  downstreamEffects, beforeSelf, afterSelf, identityImpact, decisionWeight` — **all `Optional`**, decoded with
  `.convertFromSnakeCase` (no `CodingKeys`). No `propagation_count`/`propagationCount` anywhere.
- **Verdict:** removing the field cannot fail decoding — every field is optional and a *missing* key on an
  optional just yields `nil`. **No struct declares it non-optional. Nothing to fix.** Active Forces keeps working.

## 2. GET /api/v1/explain-me/memory/{id} + a `downstream_effects` section — iOS does NOT call it
- **Grep `explain-me/memory` → 0 matches.** `ExplainViewModel` only calls the whole-life endpoints:
  `/overview, /active-forces, /patterns, /breaking-points, /contradictions, /identity, /beliefs`. There is **no
  memory-scoped explain call** and **no section rendered from it**.
- **Verdict: NO.** The now-permanently-`[]` `downstream_effects` on `/explain-me/memory/{id}` has **zero iOS
  surface** — nothing to display, nothing empty. (No backend decision needed for iOS.)
- Confirmed the two real `downstreamEffects` usages are the **different, populated** fields you called out and
  were told not to touch: `ExForceDTO.downstreamEffects` (rendered at `ExplainView.swift:158` for Active Forces)
  and `ExBreakingDTO.downstreamEffects` (breaking-points). **Untouched.**

## 3. GET /api/v1/entities/{id} — iOS reads it, but reads NONE of the renamed keys (no gap)
- **YES, iOS calls it:** `NodeDetailSheet.swift:22` (graph node tap-through / anchor detail) →
  `EntityDetailDTO`. (`EntityAtlasView` only references the paths in comments; its data is still sample/TODO.)
- **`EntityDetailDTO` reads only:** `id, name, type, is_anchor, linked_memories[]` — and each `LinkedMemory`
  reads `id, title, date, role` (its `narrative` is intentionally omitted). The whole **`attributes` dict is
  intentionally NOT decoded**, and **`people_details_by_memory` is not read at all** (grep → 0 matches).
- **The renamed keys** (`age_at_time→age_in_memory`, `appearance→physical_description`,
  `emotional_state→emotional_state_in_memory`, `role_in_memory→role_in_scene`,
  `relationship_to_narrator→relationship_type`, `dialogue_summary→removed`) all live **inside
  `people_details_by_memory`**, which iOS never touches. **Verdict: no gap, no stale alias keys in use.**
  (Note: `LinkedMemory.role` maps to the `role` key of `linked_memories`, a *different* structure — not one of
  the renamed `people_details_by_memory` keys. Unaffected.)

## 4. STORAGE_BACKEND → r2: GET /media/{id}/file will 302 → presigned URL (note for later)
- **Redirects followed?** **Yes.** `APIClient` is built on `URLSession.shared` (`init(session: .shared …)`) with
  **no `URLSessionDelegate`/`URLSessionTaskDelegate` anywhere** → the system default follows 3xx automatically.
  The three media consumers all inherit this:
  - Gallery thumbnails/lightbox → **`AsyncImage`** (URLSession.shared; follows redirects; **never sends any auth
    header**).
  - AI hero image → `CachedRemoteImage` (`URLSession.shared.data(for:req)`; follows redirects).
  - Memoir PDF → `MemoirViewModel.preparePDF` (`URLSession.shared.data(for:req)`; follows redirects).
- **Auth headers across redirects?** No custom delegate, so it's **system default**. Our two `data(for:req)`
  loaders only attach `Authorization` when `url.host == APIClient.baseURL.host` (the `/media/{id}/file` origin);
  on a 302 to a different R2 host, URLSession's default carries the original request headers to the new request
  (iOS does **not** strip `Authorization` by default). This is **practically harmless** — R2/S3 presigned URLs
  are self-authenticating via query signature and ignore a stray bearer; and `AsyncImage` carries no auth at all.
- **Recommendation (before the switch):** likely **no change needed**, but this is a runtime behavior I can't
  verify from here. When STORAGE_BACKEND flips, do a device check that images/PDF still load. If a stray
  `Authorization` on the R2 request ever causes a 400/403, add a tiny `URLSessionTaskDelegate` implementing
  `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` to **drop `Authorization` on a
  cross-host redirect** (and give `APIClient` a session that uses it). Keeping this as a noted follow-up, not a
  fix.

---

## Summary
| # | Item | iOS impact | Action |
|---|------|-----------|--------|
| 1 | `propagation_count` removed | None — field never used; `ExForceDTO` all-optional | **No fix (not breaking)** |
| 2 | `/explain-me/memory/{id}` `downstream_effects` = [] | None — endpoint not called | Report only |
| 3 | `/entities/{id}` `people_details_by_memory` renames | None — keys not read (attributes undecoded) | Report only |
| 4 | `/media/{id}/file` → 302 (r2) | Redirects followed; auth default-carried (harmless) | Device-check at switch; delegate only if needed |

Build **0/0**. No git.

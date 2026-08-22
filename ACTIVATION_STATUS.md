# Witness — Home Activation Prompts: Build Status

_Date: 2026-08-21_

## What was built

A calm, single-invitation Home screen driven by a data-model of "activation prompts"
that slowly cross-fade. Home no longer diagnoses (no stage machine, no forces, no recent
list, no `/explain-me/overview` call) — it invites.

### Files

| File | Status | Purpose |
|------|--------|---------|
| `Witness/ActivationPrompts.swift` | **new** | Prompt model (`PromptForm` + `ActivationPrompt`) and the prompt list. |
| `Witness/HomeActivationViewModel.swift` | **new** | Cycle / retire / evolve logic, slow cross-fade cadence, local persistence. |
| `Witness/HomeView.swift` | **rebuilt** | Greeting (3-variant) + floating cycling prompt. Premium/minimal, no card chrome. |
| `Witness/RecordView.swift` | **edited** | New `initialSuggestion` param → opens in Type mode w/ disappearing placeholder. |
| `Witness/MemoriesView.swift` | **edited** | Added `MemoryFormat.keyLine(_:)` helper (the confirmed key-line rule). |
| `Witness/HomeViewModel.swift` | **deleted** | Old overview/stage-machine VM — no longer referenced. |

## Decisions implemented

- **Prompt schema:** `id`, `kind`, `form` (`.singular` / `.repeatable` / `.parent`), `text`,
  `repeatVariant`. Model is small and data-driven so the list edits freely without touching logic.
- **"You decide what to share…" always present:** modeled as a `.parent` prompt — evergreen, never
  retired, never counts toward retirement, so the cycle is never empty.
- **Retire-after-2 (local):** per-`kind` recorded counts in `UserDefaults`; a kind's prompts drop
  out of the cycle once it reaches 2. Parents never count toward retirement.
- **Singular → repeatVariant:** a singular is shown once with `text`; after its first use it evolves
  to `repeatVariant` and keeps recurring (as the variant) until its kind hits 2. **Confirmed.**
- **Key line:** `narrativeSnippet → first sentence of narrative → title`. **Confirmed**, encoded in
  `MemoryFormat.keyLine(_:)`.
- **No global "+":** Home's prompt tap opens Record; Memories keeps its own entry. No global add.
- **Media v1:** title + key line + date only — no media/gallery cross-ref this phase (helper is ready).
- **RecordView:** `initialSuggestion` opens Type mode and shows the prompt as a disappearing
  placeholder (never prefilled into the body); one-shot so a later manual mode switch sticks.
- **Home interaction/animation:** slow (~8s) cross-fade between prompts, subtle grow-in transition.
  All motion suppressed under **Reduce Motion**.
- **Haptics:** auto-cycle haptic removed. The **only** haptic on Home is the press haptic from
  `witnessPress` when the user taps the prompt.

## Final prompt list (`ActivationPrompts.all`)

### Singular — evolve to repeatVariant after first use

| id | kind | text | repeatVariant |
|----|------|------|---------------|
| `love-of-life` | people | Tell me about the love of your life. | Tell me about another person you've loved. |
| `best-friend` | friends | Tell me about the best friend of your life. | Tell me about another friend who mattered. |
| `proudest-moment` | pride | What's the proudest moment of your life? | Tell me about another moment you were proud. |
| `happiest-day` | joy | What was the happiest day of your life? | Tell me about another day full of joy. |
| `saddest-day` | loss | What was the saddest day of your life? | Tell me about another time of loss. |
| `life-changed` | turning_point | Tell me about the day your life changed forever. | Tell me about another turning point. |

### Repeatable — recur as-is until the kind hits 2

| id | kind | text |
|----|------|------|
| `fear` | fear | Tell me about a time you were truly afraid. |
| `influence` | influence | Who shaped who you are today? |
| `moment` | moment | Tell me about a moment you'll never forget. |
| `laughter` | laughter | What's a memory that still makes you laugh? |
| `place` | place | Tell me about a place that means something to you. |
| `missed` | missed | Tell me about someone you miss. |
| `resilience` | resilience | What's something you overcame? |

### Parenthood — kind `child` (retires after 2 like any other kind)

| id | kind | form | text | repeatVariant |
|----|------|------|------|---------------|
| `child-born` | child | singular | Tell me about the day your child was born. | Tell me about another of your children's beginnings. |
| `child-unforgettable` | child | repeatable | What's something your child did that you never want to forget? | — |
| `child-first-laugh` | child | repeatable | Tell me about the first time your child made you laugh. | — |

_All three share `kind: child`, so recording 2 `child` memories retires the whole group together._

### Evergreen — always present, never retires

| id | kind | form | text |
|----|------|------|------|
| `you-decide` | open | parent | You decide what to share… |

## Build status — reported honestly

- Requested a clean **0 errors / 0 warnings** build.
- `BuildProject` **ran to completion** after each change, but the tool **could not locate the
  resulting build log** in this environment, and `GetBuildLog` returns "Could not find a recent
  build log." So I **cannot show a confirmed 0/0 log**.
- Best available signal: Xcode's **Issue Navigator reports 0 issues at warning severity or higher**
  (`XcodeListNavigatorIssues` → `totalFound: 0`) after the edits.
- The final change was **list-data only** (no schema or logic touched), so compile risk is low.

**Bottom line:** no errors or warnings are currently surfaced, but I could not retrieve a build log to
prove a green 0/0 build. Recommend opening the changed files in Xcode and doing a ⌘B to confirm locally.

## Not done (out of scope this phase)

- Media gallery cross-reference (deferred by decision).
- Server-side persistence of activation state (local `UserDefaults` only in v1).
- No git actions taken (per instruction).

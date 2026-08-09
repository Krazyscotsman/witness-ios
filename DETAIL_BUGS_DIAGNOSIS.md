# Witness — On-device detail bugs — Diagnosis (3 issues)

Status: **DIAGNOSIS ONLY — no fixes applied, nothing changed.** No git.

## 1. Mystery vertical bars — it's MemoryDetailView.peopleChips
- Confirmed screen: MemoryDetailView. The bars are `peopleChips` (MemoryDetailView.swift:122–133),
  shown when `memory.people` is non-empty.
- It's a SINGLE non-wrapping HStack of person capsules:
  `HStack { Image("person.fill"); Text(name) }.padding(.horizontal,13).padding(.vertical,8).background(Capsule())`
  with NO lineLimit on the name and no wrap/scroll.
- Why tall/empty with ~8 people: each capsule's FIXED width (icon ~12 + h-padding 26 + spacing)
  ≈ 44pt BEFORE text; 8 capsules + spacing ≈ 400pt, exceeding the ~327–345pt content width. The row
  can't fit, so each capsule's Text is squeezed toward 0 width and — with no lineLimit — WRAPS one
  character per line, turning each capsule into a tall narrow vertical bar with the person icon.
- NOT the adapter's fault: SampleMemory(dto) faithfully passes people; fabricated kind/wordCount/
  texture don't touch peopleChips. peopleChips was written for the sample data's 0–2 short names and
  never handled many/long people. Real many-people memory exposed it.

## 2. Title/narrative cut off both edges — SAME root cause as #1
- NOT a missing-padding bug: the content column has .padding(.horizontal, 24) and renders correctly
  for sample memories (≤2 people). It broke only on this many-people real memory.
- Mechanism: the overflowing peopleChips row (~400pt, wider than screen) sits in
  `VStack(alignment:.leading){…}.frame(maxWidth:.infinity, alignment:.leading)`. A child wider than
  the screen forces that content VStack wider than the screen, so siblings (title serif(30),
  narrative) are laid out in an over-wide column and run past the viewport edge(s).
- Honest caveat: exact both-edges vs trailing-edge is a layout-resolution detail best confirmed on
  device, but the CAUSE is unambiguous (over-wide non-wrapping people row), corroborated by the
  screen rendering fine with sample data. Also considered and RULED OUT the
  .padding-before-.frame(maxWidth:.infinity) modifier order (resolves correctly; fine with few people).
- Fixing peopleChips (wrap/scroll/cap + lineLimit(1)) should resolve BOTH #1 and #2.

## 3. Tab bar doesn't pop-to-root — no reset mechanism
- MainTabView renders `switch tab { case .memories: MemoriesView(...) }`; each tab view owns its OWN
  NavigationStack internally, using an IMPLICIT path (NavigationLink(value:) + .navigationDestination)
  — NO explicit NavigationPath/binding, so nothing can reset it.
- Tab button: `if t != selection { Haptics.tap() }; selection = t`. Tapping the already-selected tab
  sets selection to the SAME value → no state change → nothing happens; the pushed MemoryDetailView
  persists (switch case unchanged, so the view isn't recreated).
- Why "Home then Memories" works: switching to a different tab changes the switch case → MemoriesView
  is destroyed + recreated → fresh NavigationStack → root.
- To wire pop-to-root (later): give the Memories NavigationStack an EXPLICIT path binding owned where
  it survives tab switches (NavigationPath / [MemoryDTO] in MainTabView or the VM), detect a tap on the
  already-selected tab in WitnessTabBar, and clear that path on re-tap. (Because MemoriesView is
  recreated on switch, the path must live above it to persist.)

## Summary
- #1 & #2 = ONE bug: peopleChips non-wrapping HStack, no lineLimit; ~8 people overflow into tall bars
  AND push title/narrative past the screen. Real-data trigger; adapter not at fault.
- #3 = tabs own implicit-path NavigationStacks; re-tapping the active tab is a no-op and nothing resets
  the stack — needs explicit path + re-tap→clear.

No fixes applied. Awaiting go-ahead to propose fixes.

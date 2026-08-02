# Swiping the Milestones carousel flips tabs instead of scrolling it

Status: resolved
Type: bug (2026-08-01)

In glass-tab-bar mode, horizontally swiping the Milestones badges on the
dashboard changed tabs instead of scrolling through the badges.

## Cause

Glass mode uses `ContinuousPager`, which drives tab changes from a
`simultaneousGesture` horizontal `DragGesture` on the page stack. Its
direction lock only distinguishes horizontal from vertical, so it happily
engages on a horizontal swipe that started inside the Milestones
`ScrollView(.horizontal)` — a nested horizontal-scroll conflict. Vertical
scrolling was fine (the lock left it to the inner scroller); horizontal was
stolen by the pager.

## Fix

A lightweight coordination channel: `pagerHScrollLock` environment binding
(a `Binding<Bool>`) injected by `ContinuousPager` into its content. A new
`.claimsHorizontalDrag()` modifier puts a `minimumDistance: 2` drag on an
inner horizontal scroller that raises the lock on drag start and lowers it
on end. The pager reads the lock at engage time — if it's up, it sets its
own direction to non-horizontal for that drag and yields, so the finger
scrolls the inner content. The 2 pt inner threshold beats the pager's 15 pt,
so the lock is set before the pager decides.

Applied to the Milestones carousel and, for the same reason, the day-detail
photo strip (also a horizontal scroller that can live inside a tab's
NavigationStack). The lock is nil in classic-TabView mode, so the modifier
is a no-op there.

Build succeeded (app scheme).

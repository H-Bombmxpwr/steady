# Glass bar drag smoothness + %+.1f format crash-log fix

Status: resolved
Type: bug fix (2026-07-12)

User report: console errors while moving the glass bar; dragging the
pill "feels crunchy", not smooth. Console showed repeated
`String(format '%+.1f' does not match '%lld')` and "Invalid frame
dimension (negative or non-finite)".

## Root causes

1. `String(format: "%+.1f", count >= 2 ? weightDelta : 0)` in StatsView
   bodyTiles — in the CVarArg vararg context the ternary's bare `0`
   literal resolves as Int, so any range with <2 trend points (e.g. the
   new Today range) passed an Int to a float specifier. Fixed by
   computing an explicitly-typed `let weightDelta: Double` first.
2. GlassTabBar's GeometryReader math went negative on zero-width layout
   passes → "Invalid frame dimension". Now clamped (`max(1, …)`).
3. Crunchy drag: every midpoint crossing ran
   `withAnimation(spring) { selection = nearest }`, animating the whole
   page TabView while the pill was also being dragged. Now: the pill
   tracks the finger with animations explicitly disabled
   (`Transaction.disablesAnimations`), page switches snap without
   animation mid-drag (with a selection haptic per crossing), and the
   spring only fires on release to seat the pill. Pill scales to 1.07×
   with a stronger glow while held for grab feedback.

Remaining console lines (NSMapGet NULL, unsafeForcedSync, "Reading from
public effective user settings") are iOS framework noise, not app code.

Build: ** BUILD SUCCEEDED **.

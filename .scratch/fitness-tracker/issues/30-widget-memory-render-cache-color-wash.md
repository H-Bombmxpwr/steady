# Widget killed for memory; missing accent flair

Status: resolved
Type: bug (2026-07-26)

The widget extension (`com.hunter.seventyfivehard.widgets`) was
intermittently killed on-device by jetsam ("using too much memory"),
and the home-screen widget wasn't showing the themed accent color.

## Diagnosis

Not a leak — no retain cycle, no unbounded per-process growth, and the
widget target only compiles `Shared/` + `Widgets/` (the exercise/food
DBs and their images live in the app target, never the widget). It was
a *peak-memory* event: `TodaySnapshot.load()` opened the full SwiftData
`ModelContainer` on every render to read today's three numbers.
Opening the store — especially replaying a grown SQLite `-wal`, which
the app's frequent writes plus the widget's own `LogWaterIntent` writes
inflate while the app is closed — spiked past the ~30 MB widget cap.
Intermittent because it depends on WAL/store state at that render.
(Debugging the widget attached to Xcode/LLDB inflates it further, which
is why the repro showed up during long attached runs.)

The earlier fix stopped `load()` from walking `plan.days`, but left the
container-open in the render path.

## Resolution

Render path no longer touches SwiftData. `WidgetSnapshot` gained
today's live totals (`caloriesEaten`, `protein`, `waterOz`, `dayDate`);
new `WidgetSnapshot.build(plan:profile:today:)` composes the full cache
(targets + streak + today) in the APP. The app writes it on launch
(`RootRouterView.task`) and every background (`refreshStreakGuard`),
replacing the two hand-rolled snapshot builds. `TodaySnapshot.load()`
now reads only the cache (a few hundred bytes of UserDefaults JSON), and
trusts today's numbers only when `dayDate` is today — otherwise shows
targets with zero progress rather than yesterday's data. `LogWaterIntent`
still writes the DB (a user tap, more headroom) but now refreshes all
three of today's numbers into the cache from the row after saving, so
the widget reflects the tap without a fetch and a post-midnight first
tap can't leave yesterday's calories showing.

Accent flair: the flat near-black `widgetBG` is replaced by
`widgetBackground` — the same deep base under an accent→accent2 corner
gradient wash — on all three home families, so the themed color reads
even on a fresh day when the ring/stat fills are empty. (Theme mirroring
into the App Group was already correct; the widget just looked grey with
no data. Lock-screen/accessory families stay monochrome by OS design.)

# Quick Log, Week in Review, Siri, milestones, alt icons, Live Activity

Status: resolved
Type: feature batch (2026-07-12)

User picked six additions from a suggestions menu: favorites & recents,
weekly coach report, Siri shortcuts, milestones & badges, matching app
icons, Live Activity. (Also: Today range in stats — shipped separately
as issue 21.)

## Resolution

Quick Log (favorites & recents) — `FoodLog.favorite` (additive);
Add Food shows a "Quick Log" section: starred foods first, then most
recent distinct foods (8 total, fetched via FetchDescriptor, dedup by
name). Star toggles all instances by name; ⊕ re-logs a fresh copy into
the selected meal and dismisses.

Week in Review — `AIFoodEstimator.reviewWeek(days:targets:labs:)`
prompts for repeating patterns (daily soda, low-protein breakfasts)
with per-day summary lines + each day's 3 biggest foods; lab-aware when
the Blood Work toggle is on. `DaySummarySheet` generalized into
`CoachReviewSheet(title:run:)` shared by day + week. Entry point: a
gradient "Week in Review" button atop the Food stats tab.

Siri shortcuts — `75/App/AppShortcuts.swift`: `QuickLogWaterIntent`
("log water in 75"), `LogMealIntent` (asks "What did you eat?", runs
mealBreakdown, logs to the suggested meal, speaks totals back),
`OpenTodayIntent` (deep-links seventyfive://today via OpenURLIntent),
registered in an `AppShortcutsProvider`.

Milestones — `MilestonesCard` on the dashboard: streak (3/7/14/30/50/75),
pounds down (5–25), days tracked (7/30/75/100); earned badges in their
domain color, next three locked as motivation. `ConfettiView` (42
falling pieces + success haptic) fires once per newly earned badge
(celebrated ids in UserDefaults; first launch seeds history quietly if
more than 2 badges are already earned).

Matching app icons — five palette PNGs (gradient + "75" plate, 120/180
px) generated via CoreGraphics into `75/Resources/AltIcons/`,
registered under `CFBundleAlternateIcons` in `-5-Info.plist` (emerald =
primary, nil). Settings → Appearance has a dot-per-palette icon picker
(choice remembered in `ui.appIcon`).

Live Activity — `Shared/FitnessActivity.swift` attributes; widget
bundle gains `FitnessLiveActivity` (Lock Screen banner: streak +
cal/protein/water; Dynamic Island expanded/compact/minimal).
`LiveActivityManager.sync` starts/updates it (stale at midnight),
called from the scenePhase-background hook and the Settings →
Appearance toggle (`liveactivity.enabled`, off by default since it's
app-driven — no push updates). `NSSupportsLiveActivities` added to the
plist.

Build: ** BUILD SUCCEEDED ** (app + WidgetsExtension); alt-icon PNGs
and CFBundleAlternateIcons verified present in the built bundle.

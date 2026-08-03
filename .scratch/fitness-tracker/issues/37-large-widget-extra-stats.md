# Large widget: fill the empty space with 3 more stats

Status: resolved
Type: feedback (2026-08-02)

The systemLarge widget showed only Calories/Protein/Water (three RatioRows)
with empty space below — room for more. Keep those three, add three more.

## Resolution

Added Weight, Carbs, and Workout beneath the existing three (separated by a
faint divider). New neutral `InfoRow` (no goal red/green, optional trailing
note) renders them:
- Weight — latest logged weight in lb, with a green "↓X.X lb" note for
  pounds lost since the start.
- Carbs — today's carbs (g).
- Workout — today's logged minutes, or "Rest".

Data flows through the existing cache-only render path: `WidgetSnapshot`
gained `currentWeight`, `startingWeight`, `carbs`, `workoutMinutes`, filled
by `WidgetSnapshot.build` in the app; `TodaySnapshot.load()` maps them,
gating carbs/workout behind the same "is the cache for today?" check as the
other live totals (weight is the latest logged value, so it maps
unconditionally). The widget never opens SwiftData. Row spacing tightened
10→8 so all six fit above the action buttons.

Build succeeded (app scheme; widget embedded/validated).

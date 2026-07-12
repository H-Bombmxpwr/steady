# Adaptive TDEE, workout import, meal ideas, fasting, Wrapped, patterns

Status: resolved
Type: feature batch (2026-07-12)

User picked six additions from a "next level" suggestions menu: adaptive
TDEE, Apple Health/Garmin workout imports, "What should I eat?", fasting
window, Monthly Wrapped, correlation insights.

## Resolution

Adaptive TDEE — `CalorieEngine.adaptiveTDEE(profile:plan:)`: over the
last 28 full days (today excluded as partial), observed TDEE =
avg logged intake − (EWMA trend slope × 3500). Requires 14+ food-logged
days and weigh-ins spanning 14+ days; observed clamped to 0.6–1.5× the
formula; blend weight = min(0.8, loggedDays/28) so the formula keeps a
20% anchor. `Plan.adaptiveBudget` (default true, additive) gates it in
`targets()`; manual override still wins. Settings → Daily Targets shows
the toggle plus "Learned burn rate: N cal/day (formula says M)" or a
"learning…" hint.

Workout import — `WorkoutLog.healthKitID` (additive dedupe key).
`HealthKitService.importExternalWorkouts(into:)` reads 90 days of
HKWorkouts from other sources (own writes excluded via source
predicate), maps activity types to the app's categories, names logs
"Running · Garmin Connect", flags outdoor via
`HKMetadataKeyIndoorWorkout == false`, imports each UUID once into
`ensureDay`. Workout type added to the HealthKit read set. Runs on
dashboard appear (`.task`) and Stats `loadHealth`; manual "Import
Workouts Now" button in Settings → Apple Health.

What should I eat? — `AIFoodEstimator.suggestMeals(meal:remaining…)`:
3 options fitting the remaining calories, steered at the protein gap,
skipping foods already eaten today, lab-aware; each returns the full
nutrition schema. `MealIdeasView` (Food/) shows remaining cal/protein +
next meal, one-tap "Log to Dinner" writes a normal `FoodLog`
(source "ai"). Entry: "What Should I Eat?" row in the day view's Food
section. Listed in Settings → About Estimates.

Fasting window — `Shared/Fasting.swift`: status derives from
`FoodLog.createdAt` (last food in last 3 days anchors the fast; first
food today opens the window); `eatingWindows(days:)` charts history.
Opt-in via `fasting.enabled` + `fasting.targetHours` (12–23, default
16) in a new Settings → Fasting section. `FastingCard` on the dashboard
(TimelineView, minute ticks): elapsed vs target bar, last-food time,
goal ETA. Eating-window chart on Stats → Food when enabled.

Monthly Wrapped — `MonthlyWrapView` (Stats/): month-picker chevrons,
gradient poster (trend delta, days showed up, best streak, workouts,
water gallons, avg cal vs budget, most-logged food needing 2+ repeats,
photos, drinks), shared as an image via `ImageRenderer` (3×) +
ActivityView. Entry: "Month in Review" gradient button atop the Body
stats tab.

Correlation insights — `Services/InsightsEngine.swift`, all on-device,
last 90 days, each split needs 4+ days per side and a meaningful gap:
alcohol vs next-morning weight (≥0.25 lb), short sleep (<6.5 h) vs
same-day calories (≥100), 2,300+ mg sodium vs next-morning weight,
workout-day vs rest-day intake (±150), weekend vs weekday calories
(≥150). `patternsCard` on the Body stats tab (uses the sleep dict
already loaded from Health); friendly empty state until data shows a
pattern.

Build: ** BUILD SUCCEEDED ** (app + WidgetsExtension).

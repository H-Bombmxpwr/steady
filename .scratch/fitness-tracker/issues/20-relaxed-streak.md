# Relaxed vs strict streak, configurable, relaxed by default

Status: resolved
Type: feature (2026-07-12)

User request: the streak should count any day something is marked, not
only days when ALL goals are met. Choose strict vs not-strict when the
session starts; not-strict is the default.

## Resolution

- `Plan.strictStreak: Bool = false` (additive migration; default is the
  relaxed style).
- `DayLog.hasActivity`: weight, water, any food/calories, workout,
  photo, supplement check-off, drinks, or a note — anything logged.
- `CalorieEngine.dayCounts(day:plan:targets:)`: strict → existing
  `dayMet` (≥75% of the day's checks); relaxed → `hasActivity`.
  `streakStats` (current streak + consistency) now uses it, so the
  dashboard flame, widget streak, and streak-at-risk notification all
  follow the chosen style. Weekly insight's "days on target" stays
  goals-based on purpose — that's a goals metric, not the streak.
- Onboarding "Your Goal" step: segmented "Streak counts when — I log
  anything / I hit my goals" (relaxed preselected), saved to the plan.
- Settings → Goal: same picker, changeable anytime.

Build: ** BUILD SUCCEEDED ** (app + WidgetsExtension).

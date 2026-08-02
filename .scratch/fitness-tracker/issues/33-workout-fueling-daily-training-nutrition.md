# Workout fueling: carbs/hr, and training-day nutrition

Status: resolved (v1)
Type: feature (2026-08-01)

User idea: recommend nutrition for a workout — "if you're going to do a
3 hr bike ride, how many grams of carbs per hour depending on intensity" —
and, like the paid app they trialed, let the training calendar drive the
day's nutrition. Chosen scope: full daily training-nutrition (budget
auto-adjusts), built on a deterministic engine first.

## What shipped

**FuelingEngine (Shared/FuelingEngine.swift)** — pure, local, free (no AI).
`FuelingEngine.plan(category:intensity:minutes:bodyweightLbs:)` → a
`FuelingPlan`: carbs/hr during (0 unless it's endurance running long),
total during-carbs, fluid oz/hr, sodium mg/hr, a pre-load, recovery carbs +
protein, and an estimated session burn (MET × kg × hours × intensity).
Numbers follow mainstream endurance guidance (≈30–60 g carb/hr for 1–2.5 h,
up to ~90 beyond; 0.4–0.8 L/hr fluid; ~300–700 mg/hr sodium; 1 g/kg carb +
~0.3 g/kg protein to recover), bucketed by duration and nudged by intensity.
Cardio/sports get in-workout carbs; strength/mobility get pre/post only.

**Intensity model.** New `WorkoutIntensity` (easy/moderate/hard, each with a
conversational cue + burn factor). Added `categoryRaw` + `intensityRaw` to
`WorkoutScheduleEntry` (additive defaults → clean migration) so a scheduled
slot knows enough to be fueled. The schedule editor (WorkoutsView) now has
Type + Intensity pickers; the row shows the intensity.

**Daily training-nutrition.** `Plan.fuelTrainingDays` (default on, Settings →
Daily Targets). `CalorieEngine.fuelingPlans(plan:on:)` /
`trainingBurn(plan:on:)` aggregate a date's scheduled workouts, and a new
`targets(profile:plan:on:)` adds that day's burn back to the calorie budget
so eating the fuel doesn't read as "over." The dashboard's TodayCard uses
this day-aware target; history cards (streak/milestones/insight) stay on the
base budget — see caveat.

**Surfaces.** `FuelCard` on the dashboard appears only on days with a
scheduled workout: per-session carbs/hr at a glance, the "+N cal added to
today's budget" note, tap-through to the full during/before/after breakdown.
`FuelCalculatorView` (Workouts tab → Fuel Calculator) is the on-demand
version — pick type/intensity/duration, plan updates live, sized to current
weight. Both reuse `FuelPlanBreakdown`.

## Caveats / follow-ups

- The budget bump applies to today's dashboard card, not to historical
  streak scoring. Deliberate v1 scope (streak scoring iterates all days);
  a scheduled workout eaten "to plan" could still read as over-budget in the
  streak check. Wire per-day adjusted targets into scoring next.
- Potential double-count with the adaptive budget, which already learns real
  burn over time — the bump is a today-only proactive add on top. Acceptable
  for a planned big day; revisit if it overshoots for heavy trainers.
- Engine numbers are guidance, not per-athlete prescription (no sweat-rate,
  heat, or fitness personalization yet).

Build succeeded (app scheme; widget embedded/validated — Shared/ compiles
for both targets, FuelingEngine is Foundation-only).

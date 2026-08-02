# PRD: "75" — General Fitness & Weight-Loss Tracker

Status: agreed scope (2026-07-07); all phases 1–8 shipped, including the
exercise DB + templates (issue 09) and the 2026-07-10 polish pass (issue 10).
App keeps the name **75** for now. Latest: 2026-08-01 — recipe-from-a-link
food entry (issue 34: paste a web/YouTube URL → itemized nutrition, per
serving) and workout fueling / training-day nutrition (issue 33: a local
carbs-per-hour + before/after engine, intensity on scheduled workouts, a
dashboard fuel card, and a budget that grows on training days). Prior
2026-08-01 (issue 32) — de-biased the AI nutrition guidance so estimates
stop coming back high, and moved AI into its own Settings screen that shows
how it's used plus every prompt sent (user input rendered as ‹placeholders›).
Earlier: 2026-07-26 batch (issue 29) — portion steppers on every food path,
grounded-lookup badge on AI estimates, photo meals itemized like described
meals, higher-accuracy model toggle.

## Vision

Evolve the 75 Hard tracker into a complete start-to-finish weight-loss app built on
proven methods: an adaptive calorie budget, high-protein targets, real workout
programming, and consistency mechanics — while keeping the things that already work:
**Face ID lock** and **private local progress photos** (stored in the app's Documents,
invisible to the Photos app unless explicitly saved).

## What changes vs. today

- No more hardcoded 75 Hard rules. On first open, the user is prompted to **set up a
  plan**: profile (age, height, weight, activity) → TDEE (Mifflin-St Jeor) → goal
  weight + pace (0.5–2 lb/week) → daily calorie budget → workout plan.
- `ChallengeState`/fixed `isComplete` logic replaced by user-defined goals.

## Feature set

### Calorie & weight engine
- **Adaptive calorie engine**: TDEE at onboarding; budget self-corrects over time by
  comparing logged intake against actual weight trend.
- **Trend weight**: exponentially smoothed trend line is the headline number; raw
  daily weigh-ins de-emphasized. **Goal-date projection** chart.
- **Macro targets**: protein/carb/fat rings on dashboard (protein emphasized).
- **Weekly insight review**: average deficit, trend delta, consistency, one
  actionable suggestion.

### Logging
- **Food**: bundled trimmed **USDA FoodData Central** database (offline, private,
  instant search) + **Open Food Facts** online lookup for barcode scans. Custom
  foods, recents, favorites.
- **Water** (configurable step), **alcohol**, **weight**, **body measurements**
  (waist, hips, chest, …).
- **Supplements**: user defines their own list (e.g. creatine, magnesium) with
  scheduled reminders and a daily check-off.

### Workouts
- Bundled public-domain **exercise database** (yuhonas/free-exercise-db, 800+
  exercises with images).
- **Custom workout builder** — users can always build their own from scratch.
- **Templates** as starting points: 5×5, push/pull/legs, Couch-to-5K.
- Sets/reps/weight logging for strength, duration for cardio; progressive-overload
  history per exercise.

### Habit layer
- **Streaks + consistency score**: forgiving (not all-or-nothing), calendar heat
  map, streak-at-risk notifications.
- **Daily progress photos** stay; add **auto-generated timelapse** and side-by-side
  compare from the private photo library.

### System integration
- **HealthKit two-way**: weight, water, dietary energy, workouts. **Read** steps /
  active energy and **sleep**; surface both in trends and weekly insights.
- **Widgets**: home screen + lock screen (WidgetKit, App Group shared store).
- **Notifications**: morning weigh-in, hydration nudges, workout time, supplement
  reminders, streak-at-risk, weekly review. Helpful, not spammy; all configurable.
- **Calendar**: planned workouts written into the user's calendar via **EventKit**
  (no server; auto-syncs wherever their calendar does).

### Stretch (later phase)
- **Photo-of-food logging** — shipped, but not as the on-device CoreML classifier
  planned here: Gemini vision reads the plate and (since issue 29) itemizes it
  into components like Describe Meal. Photos are downscaled and sent to Google;
  only food photos, never progress photos.

## Explicitly out of scope (for now)
Social features, AI chat coaching, meal planning/recipes, Apple Watch app,
fasting timer, hosted webcal subscribe feed.

## Data sources (all free)
- USDA FoodData Central — API + full CSV download for bundling: https://fdc.nal.usda.gov/download-datasets/
- Open Food Facts — barcode/product API: https://openfoodfacts.github.io/openfoodfacts-server/api/
- free-exercise-db — public domain, JSON + images: https://github.com/yuhonas/free-exercise-db

## Build phases
1. **Repo restructure** — move `.git` from `75/` to repo root so `75.xcodeproj` is
   tracked; baseline commit. (Recommended; awaiting go-ahead.)
2. **Core generalization** — new SwiftData model (Plan/Goals/DayLog), onboarding
   flow with TDEE + plan setup. Face ID and photos untouched.
3. **Tracking + engine** — weight trend/projection, calories/macros, water, alcohol,
   supplements + reminders, measurements, Swift Charts dashboard, streaks, weekly
   insights.
4. **Food database** — bundle trimmed USDA, search UI, barcode scanning.
5. **Workouts** — bundle exercise DB, builder, templates, set logging, overload
   charts.
6. **System surfaces** — HealthKit, widgets (home + lock), notification engine.
7. **Calendar (EventKit) + photo timelapse.**
8. **Stretch** — on-device food photo recognition.

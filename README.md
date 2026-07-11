# 75 — Personal Fitness & Weight-Loss Tracker (SwiftUI + SwiftData)

A private, local-first iOS app for losing weight through proven methods. Originally
a 75 Hard tracker, now a general fitness tracker built around an adaptive calorie
budget. Product scope and work log live in `.scratch/fitness-tracker/`.

## Features

### Plan & engine
- **Plan setup onboarding**: profile → TDEE (Mifflin-St Jeor) → goal weight + pace →
  calorie budget preview → training days → hydration. Sex options include
  "prefer not to say" (uses the male/female midpoint in the BMR math).
- **Adaptive budget**: recomputes from your latest weight; goals (weight, pace,
  protein, water) are editable anytime in Settings without breaking history.
- **Weight trend**: EWMA-smoothed trend line, goal line, projected goal date.

### Logging
- **Food** — logged into **meals** (breakfast, morning snack, lunch, afternoon
  snack, dinner, dessert; time-of-day default) with whole-day totals. The day
  screen shows one row per meal — tap in for the foods, tap a food for its
  full panel. Five ways in, **Gemini-first**: **describe your meal** is the
  big gradient button (type or **dictate** plain text — Gemini itemizes every
  component separately, never merging ingredients, with a per-item portion
  assumption; every number is editable before logging), then **photo of food**
  (Gemini vision), **barcode scan** (crosshair reticle, only reads inside the
  frame), **database search** (live Open Food Facts, ~3M products, US-market
  first, re-ranked by relevance, outages retried + cached), and manual custom
  entry. Every logged food carries a **full nutrition panel** — carbs, fats
  (sat/trans), cholesterol, sodium, fiber, sugars (incl. added), potassium,
  calcium, iron — from Gemini or OFF. A **Nutrition Report** grades the day
  Noom-style: macro split, FDA "keep under" limits (bars go red when blown),
  "get enough" goals, calorie-density mix, per-meal breakdown; **Summarize My
  Day** has Gemini review everything eaten and suggest concrete substitutions.
  **Calorie-density colors** (green < 1 cal/g · orange 1–2.4 · red > 2.4) are
  computed locally from kcal ÷ grams (not trusted from the model) and tag
  foods everywhere. Gemini also fills gaps: missing protein on OFF results is
  auto-estimated, "Not listed?" estimates a whole food from the search text,
  and every estimate echoes what it assumed. Food names/photos go to AI;
  progress photos never leave the device. Gemini key loads from a git-ignored
  `Secrets.plist` (a key pasted in Settings → AI Assist overrides it).
- **Workouts**: bundled **exercise database** (873 exercises with instructions,
  free-exercise-db), workout builder with per-exercise sets × reps × weight
  targets, **set-by-set logging** with progressive-overload history charts,
  starter templates (StrongLifts 5×5, Push/Pull/Legs, Couch-to-5K); as many
  workouts per day as you want, scheduled or not; categorized; weekly schedule
  built from your presets with **EventKit calendar sync** (local, no server).
- **Water** (bottle-size step), **weight**, **alcohol in standard drinks**
  (~98 cal each, counted), **supplements** (daily or weekly, with reminders),
  **body measurements** (waist/hips/chest/arm/thigh).

### Stats
- Dedicated **Stats tab**: 7D / 30D / 90D / YTD / All / custom range.
- Charts: weight + trend + goal, calories vs budget, protein, water, workout
  minutes stacked by type, alcohol, steps (Health), sleep (Health), measurements.

### Integrations
- **Apple Health two-way**: writes weight/water/nutrition/workouts, reads steps,
  sleep, and external weigh-ins (Garmin/Watch/smart scales flow in via Health —
  that's the Garmin link).
- **Widgets**: small/medium/large home screen + lock screen (circular, rectangular,
  inline). Streak is front and center; medium/large have one-tap water logging
  plus Food and Today shortcuts (Today deep-links into the current day's log).
  Weight is deliberately never shown on widgets.
- **Notifications**: morning weigh-in, hydration nudges (times configurable, with
  a log-water action), workout reminders (lead time configurable), smart
  streak-at-risk guard (fires only when the streak is actually in danger;
  time configurable), supplement reminders (daily/weekly).

### Privacy & style
- **Face ID protects progress photos** (app entry is open), with an optional
  **backup PIN** (set during onboarding or in Settings; salted hash in the
  Keychain) for when Face ID fails or isn't wanted; photos live in the
  app's Documents, invisible to the Photos app unless you save/share them.
- **Photo timelapse**: builds an MP4 from your progress photos on-device.
- **Themes**: five accent palettes + dark/light/system mode — applies live,
  everywhere, no restart. Floating **glass tab bar** with swipe-between-tabs
  (Settings → Appearance toggles back to the classic bar).
- **Backup export** as a single JSON (embedded photos). All data persists across
  rebuilds/redeploys (same bundle ID) in the App Group container.

## Tech

- iOS 18.5+, SwiftUI, SwiftData, WidgetKit, HealthKit, EventKit, Vision, AVFoundation
- No required external dependencies
- Store: App Group container `Fitness.store` (shared with widgets); photos in
  `Documents/Photos`

## Project Structure

```
Shared/        SwiftData models, CalorieEngine, Persistence — compiled into app + widget
Widgets/       WidgetKit extension (home + lock screen, interactive logging)
75/
  App/         App entry, photo lock (Face ID + PIN), privacy shield, Theme
  Resources/   Exercises.json (free-exercise-db extract),
               Secrets.plist (API keys — git-ignored, create locally)
  Services/    Backup, FoodDatabase (Open Food Facts), ExerciseDatabase,
               AIFoodEstimator (Gemini text + vision), HealthKit,
               Notifications, CalendarSync, Timelapse
  Views/
    Onboarding/  Multi-step plan setup
    Dashboard/   Rings, trend chart, streak, weekly insight (+ Settings sheet)
    Stats/       Time-range charts for every tracked series
    Day/         Day detail logging + workout form
    Food/        Food search, portion picker, barcode + photo recognition
    Calendar/    Day-by-day history
    Photos/      Gallery, viewer, compare, timelapse (Face ID gated)
    Workouts/    Workout builder, exercise picker + history, templates,
                 weekly schedule, calendar sync
    Settings/    Goals, targets, supplements, notifications, Health,
                 appearance, backup, erase
docs/agents/   Agent config (issue tracker, triage labels, domain docs)
.scratch/      Local issue tracker: PRD + implementation issues
```

## Getting Started

1. Open `75.xcodeproj` in Xcode 16+.
2. Create `75/Resources/Secrets.plist` (git-ignored) with a `GeminiAPIKey`
   string entry — free key from aistudio.google.com. Without it, AI estimates
   are unavailable until a key is pasted in Settings → AI Assist.
3. First device build: let Xcode register the App Group + HealthKit capabilities
   (automatic signing).
4. Run on device (free provisioning = 7-day installs; paid Dev Program ≈ 12 months).

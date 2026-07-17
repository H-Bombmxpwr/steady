# Steady — Personal Fitness & Weight-Loss Tracker (SwiftUI + SwiftData)

A private, local-first iOS app for losing weight through proven methods. Originally
a 75 Hard tracker (the repo/project is still named `75`; bundle ID and App Group
are unchanged so data persists), now **Steady**: a general fitness tracker built
around an adaptive calorie budget, branded with a descending-trendline mark.
Product scope and work log live in `.scratch/fitness-tracker/`.

## Features

### Plan & engine
- **Plan setup onboarding**: profile → TDEE (Mifflin-St Jeor) → goal weight + pace →
  calorie budget preview → training days → hydration. Sex options include
  "prefer not to say" (uses the male/female midpoint in the BMR math).
- **Adaptive budget**: recomputes from your latest weight; goals (weight, pace,
  protein, water) are editable anytime in Settings without breaking history.
- **Adaptive TDEE** (on by default, Settings → Daily Targets): once there are
  14+ food-logged days and weigh-ins spanning 14+ days in the last four weeks,
  the engine compares what you actually ate against how the weight trend
  actually moved (3,500 kcal/lb) and learns your real burn rate — blended with
  the formula (trust grows with logging consistency, formula keeps a 20%
  anchor, observed value clamped to sane bounds). Settings shows the learned
  number vs the formula so the budget never changes silently.
- **Weight trend**: EWMA-smoothed trend line, goal line, projected goal date.

### Logging
- **Food** — logged into **meals** (breakfast, morning snack, lunch, afternoon
  snack, dinner, dessert; time-of-day default) with whole-day totals. The day
  screen shows one row per meal — tap in for the foods, tap a food for its
  full panel. Five ways in, **Gemini-first**: **describe your meal** is the
  big gradient button (type or **dictate** plain text — Gemini itemizes every
  component separately, never merging ingredients, with a per-item portion
  assumption; every number is editable before logging), with **photo of food**
  (Gemini vision) right below it at equal billing, then **Saved Meals** (name
  any meal from its screen — "my usual breakfast" — and re-log the whole
  thing in one tap), a **Quick Log** shelf of starred and recent foods,
  **barcode scan** (crosshair reticle, only reads inside the frame),
  **database search** (live Open Food Facts, ~3M products, US-market first,
  re-ranked by relevance, outages retried + cached), and manual custom entry. Every logged food carries a **full nutrition panel** — carbs, fats
  (sat/trans), cholesterol, sodium, fiber, sugars (incl. added), potassium,
  calcium, iron — from Gemini or OFF. A **Nutrition Report** grades the day
  Noom-style: macro split, FDA "keep under" limits (bars go red when blown),
  "get enough" goals, calorie-density mix, per-meal breakdown; **Summarize My
  Day** has Gemini review everything eaten and suggest concrete substitutions.
  **Calorie-density colors** (green < 1 cal/g · orange 1–2.4 · red > 2.4) are
  computed locally from kcal ÷ grams (not trusted from the model) and tag
  foods everywhere. Gemini also fills gaps: missing protein on OFF results is
  auto-estimated, "Not listed?" estimates a whole food from the search text,
  and every estimate echoes what it assumed. Estimates run **grounded with
  Google Search**: named restaurants, chains, and brands are looked up against
  their published nutrition (say "Chipotle chicken bowl…" and it checks
  Chipotle's numbers), falling back to a plain estimate if search is
  unavailable. Meals delete cleanly: swipe a meal row, or use the Delete Meal
  button inside the meal; every add/remove saves immediately.
  Logged foods stay editable —
  tap any food in a meal to fix its name, meal, portion, or any nutrient in
  place. In-app copy stays AI-silent; Settings → **About Estimates** is the
  one place that explains where Gemini is used (food names/photos go to
  Google; progress photos never leave the device). The key loads from a
  git-ignored `Secrets.plist` (a key pasted in Settings overrides it).
- **Workouts**: bundled **exercise database** (873 exercises with instructions,
  free-exercise-db), workout builder with per-exercise sets × reps × weight
  targets, **set-by-set logging** with progressive-overload history charts,
  starter templates (StrongLifts 5×5, Push/Pull/Legs, Couch-to-5K); as many
  workouts per day as you want, scheduled or not; categorized; weekly schedule
  built from your presets with **EventKit calendar sync** (local, no server).
- **What Should I Eat?** (day view → Food): Gemini suggests three realistic
  options that fit what's *left* of today's calories and steer at the protein
  gap (lab-aware when Blood Work is on, skips what you already ate); each idea
  carries a full nutrition panel and logs with one tap as a normal editable
  food.
- **Water** (bottle-size step), **weight**, **alcohol in standard drinks**
  (~98 cal each, counted), **supplements** (daily or weekly, with reminders),
  **body measurements** (waist/hips/chest/arm/thigh).
- **Fasting window** (opt-in, Settings → Fasting): no extra logging — the last
  logged food starts the clock, the first food of the day ends it. Dashboard
  card with live elapsed time, target (12–23 h, default 16:8), and when the
  goal lands; eating-window history charts under Stats → Food.

### Streak
- The dashboard flame counts **any day you log something** by default (food,
  water, weight, a workout, a photo…). Prefer accountability? Switch to a
  **strict streak** (requires meeting the day's goals) at onboarding or in
  Settings → Goal. The widget streak and streak-at-risk reminder follow the
  same style. The streak is recomputed from the data every time, so
  **backfilling a missed day** (Calendar → that day → log anything)
  reconnects it retroactively.

### Stats
- Dedicated **Stats tab**, split into **Body** and **Food** sections, each with
  Today / 7D / 30D / 90D / YTD / All / custom range.
- **Body**: weight + trend + goal, water, workout minutes stacked by type,
  steps (Health), sleep (Health), measurements.
- **Food**: calories vs budget, protein, **calorie-density mix** (stacked
  green/orange/red per day), fiber vs 28 g goal, sodium vs 2,300 mg limit,
  alcohol, eating window (when fasting is on); tiles for avg
  calories/protein/fiber/sodium. A **Week in Review** button has the coach
  find repeating patterns across the last 7 days (lab-aware when Blood Work
  is on).
- **Patterns** (Body tab): on-device correlation mining over the last 90
  days — drinks vs the next morning's scale, short sleep vs appetite, salty
  days vs water weight, workout-day eating, weekends vs weekdays. Each
  pattern only appears with 4+ days on both sides of the comparison and a
  meaningful gap; nothing leaves the device.
- **Month in Review** (Body tab): a Wrapped-style poster for any month —
  trend change, days showed up, best streak, workouts, water, most-logged
  food, average calories, photos, drinks — private by default, shareable as
  an image.

### Blood work (opt-in)
- Log a few numbers from a recent lab panel (LDL, HDL, triglycerides, fasting
  glucose, A1C) at onboarding or anytime in Settings → Blood Work. With the
  toggle on, day summaries weight their food swaps toward improving those
  markers and the nutrition report tightens the relevant limits (sat fat,
  cholesterol, fiber, added sugar) — always framed as prep for the doctor
  conversation, never medical advice. Values stay on-device; only the bare
  numbers (nothing identifying) steer the summary request. Panels chart over
  time on the Food stats tab.

### Milestones
- Dashboard badges for streaks (3–75 days), pounds down (5–25), and days
  tracked (7–100) — earned ones in color, the next few locked as motivation,
  with a one-time confetti moment when a new badge lands.

### Integrations
- **Apple Health two-way**: writes weight/water/nutrition/workouts, reads steps,
  sleep, and external weigh-ins (Garmin/Watch/smart scales flow in via Health —
  that's the Garmin link).
- **Workout import**: workouts recorded on an Apple Watch or in Garmin
  Connect (or Strava, etc. — anything that writes to Health) import into the
  day log automatically whenever the dashboard or Stats loads, mapped to the
  app's categories with source in the name ("Running · Garmin Connect").
  Each Health workout imports exactly once (UUID remembered) and counts
  toward workout minutes and the streak.
- **Widgets**: small/medium/large home screen + lock screen (circular, rectangular,
  inline). Streak is front and center; medium/large have Food and Today
  shortcuts plus one-tap water logging, in that order (Today deep-links into
  the current day's log). Weight is deliberately never shown on widgets.
- **Siri shortcuts**: "log water in 75", "log a meal in 75" (speak the meal,
  it's itemized and logged with totals read back), "open today in 75".
- **Live Activity** (optional, Settings → Appearance): remaining calories,
  protein, and water on the Lock Screen / Dynamic Island, refreshed whenever
  the app runs.
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
- **Themes & brand**: five accent palettes + dark/light/system mode — applies
  live, everywhere, no restart. The dashboard opens with the Steady trendline
  mark, a time-of-day greeting, and a daily-rotating encouragement line built
  from your actual numbers; every screen carries a subtle accent wash; cards
  have per-domain icon chips and tints (water sky, food tangerine, weight
  violet, alcohol amber…). **Matching app icons**: the descending-trendline
  mark on each accent gradient (primary has dark + tinted variants), switchable
  in Settings — alternates live in the asset catalog
  (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`), which generates the
  iPhone *and* iPad plist entries the old loose-PNG setup was missing.
  Floating **glass tab bar** (on by default) with a gradient pill you can tap,
  swipe pages under, or grab and slide across the tabs — pages follow live
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
               InsightsEngine (on-device pattern mining), Notifications,
               CalendarSync, Timelapse
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

# Steady

**A private, local-first iOS weight-loss & fitness tracker built around an adaptive calorie budget and AI food logging.**

`iOS 18.0+` · `SwiftUI` · `SwiftData` · `WidgetKit` · `HealthKit` · `Local-first` · `No external dependencies`

Steady started life as a 75 Hard tracker and grew into a general weight-loss app built on proven methods: an adaptive calorie budget, high-protein targets, real workout programming, and consistency mechanics — all on-device.

📖 **[Full documentation →](https://h-bombmxpwr.github.io/steady/)** — feature guides, how the adaptive budget works, AI setup, and support.

> The Xcode project is still named `75`, and the bundle ID / App Group are unchanged so existing data persists. Product scope and the work log live in [`.scratch/fitness-tracker/`](.scratch/fitness-tracker/).

---

## Contents

- [Highlights](#highlights)
- [Features](#features)
  - [Plan & adaptive budget](#plan--adaptive-budget)
  - [Food logging](#food-logging)
  - [AI (Gemini)](#ai-gemini)
  - [Workouts & fueling](#workouts--fueling)
  - [Coaching & insights](#coaching--insights)
  - [Other tracking](#other-tracking)
  - [Streak](#streak)
  - [Stats](#stats)
  - [Blood work (opt-in)](#blood-work-opt-in)
  - [Integrations](#integrations)
  - [Privacy, security & design](#privacy-security--design)
- [Tech stack](#tech-stack)
- [Architecture](#architecture)
- [Getting started](#getting-started)

---

## Highlights

- 🍽️ **AI food logging** — describe a meal, photograph a plate, or **paste a recipe link** and Gemini itemizes every ingredient with a full nutrition panel.
- 📉 **Adaptive budget** — learns your real burn rate from intake vs. your weight trend, instead of trusting a textbook formula.
- 🏋️ **Workout fueling** — carbs-per-hour, pre/post, and fluids for a session; training days add their burn back to the budget.
- 🔒 **Local-first & private** — data lives in an App Group container; progress photos sit behind Face ID and never touch the Photos app unless you export them.
- 🎨 **Themed everywhere** — five accent palettes, matching app icons, and widgets that follow your palette.

---

## Features

### Plan & adaptive budget

- **Onboarding**: profile → TDEE (Mifflin-St Jeor) → goal weight + pace → budget preview → training days → hydration → optional AI key → photo privacy. ("Prefer not to say" uses the male/female midpoint in the BMR math.)
- **Adaptive budget**: recomputes from your latest weight; goals (weight, pace, protein, water) are editable anytime without breaking history.
- **Adaptive TDEE** *(on by default)*: after 14+ logged days and 14+ days of weigh-ins, it compares what you actually ate against how your weight trend moved (3,500 kcal/lb) and learns your real burn rate — blended with the formula (trust grows with logging; formula keeps a 20% anchor; observed value clamped to sane bounds). Settings shows learned vs. formula so the budget never changes silently.
- **Weight trend**: EWMA-smoothed line over daily weigh-ins (each day a dot), goal line + label, projected goal date, and a *Hide goal line* toggle that re-fits the axis to your data.

### Food logging

Logged into **meals** (breakfast, snacks, lunch, dinner, dessert; time-of-day default) with whole-day totals. Six ways in — **Gemini-first**:

| Path | What it does |
|---|---|
| **Describe Your Meal** | Type or **dictate**; Gemini itemizes every component separately, with a per-item portion assumption. |
| **Photo of Food** | Reads a plate into separate items via Gemini vision. |
| **Recipe from a Link** | Paste a recipe website or YouTube URL; reads the ingredients (and video description/comments) into items, with a **servings** stepper. |
| **Barcode scan** | Crosshair reticle, reads only inside the frame. |
| **Database search** | Live Open Food Facts (~3M products, US-first, relevance-ranked, retried + cached). |
| **Saved Meals / Quick Log / Custom** | Re-log a whole saved combo, a starred/recent food, or enter numbers by hand. |

- **Full nutrition panel** on every food — carbs, fats (sat/trans), cholesterol, sodium, fiber, sugars (incl. added), potassium, calcium, iron.
- **Portion steppers** everywhere — scale a portion and every stat follows; no rebuilding the meal.
- **Grounding badge** — estimates run with Google Search, so named restaurants/brands are checked against published nutrition; a green *Looked up* vs. orange *Best guess* badge shows which answered.
- **Calorie-density colors** (🟢 <1 cal/g · 🟠 1–2.4 · 🔴 >2.4), computed locally from kcal ÷ grams — tag foods everywhere.
- **Nutrition Report** grades the day Noom-style: macro split, FDA "keep under" limits, "get enough" goals, density mix, per-meal breakdown.
- **Fully editable** — tap any logged food to fix its name, meal, portion, or any nutrient in place; swipe to delete; every change saves immediately.

### AI (Gemini)

- Powers Describe / Photo / Recipe logging, "Estimate Nutrition," missing-protein fill-in, *What Should I Eat?*, and *Summarize My Day*.
- **Bring your own key (optional)** — a shared key is bundled so it works out of the box; add your own free key during onboarding or in **Settings → AI & Estimates**. A built-in guide links straight to Google AI Studio and walks through creating, formatting, and pasting a key.
- **Transparent** — the AI settings screen lists exactly what's sent, and shows the verbatim prompt for every feature with your input rendered as `‹placeholders›`.
- **Private** — only food text/photos and pasted links leave the device (to Google). Weight, progress photos, and everything else stay local.

### Workouts & fueling

- **Exercise database** (873 exercises with instructions, free-exercise-db), a workout builder with per-exercise sets × reps × weight targets, **set-by-set logging** with progressive-overload history, and starter templates (StrongLifts 5×5, PPL, Couch-to-5K).
- **Weekly schedule** built from your presets, with **EventKit calendar sync** (local, no server). *All Workouts* keeps a searchable, alphabetized list one tap away.
- **Fueling engine** *(local, no AI)* — from a workout's type, intensity, duration, and your weight it computes carbs/hr during, a pre-load, recovery carbs + protein, and fluids/sodium. Use the **Fuel Calculator** on demand, or let a **Today's Fuel** card surface it for scheduled workouts.
- **Training-day nutrition** — a scheduled workout's estimated burn is added back to that day's calorie budget, and the sessions' fluid guidance is added to the water target, so eating and drinking the fuel doesn't read as "over."
- **Week's Fuel** — a day-by-day map of the next seven days from the training schedule: what's planned, carbs during long sessions, recovery protein, and each day's budget adjustments. The same guidance appears on any day's detail page, so eating can be planned from the calendar.

### Coaching & insights

- **What Should I Eat?** — Gemini suggests three realistic options that fit what's *left* of today's calories and target the protein gap (lab-aware; skips what you already ate); each logs in one tap.
- **Summarize My Day / Week in Review** — the coach reviews what you ate and suggests concrete substitutions (weekly version finds repeating patterns).
- **Patterns** *(on-device)* — correlation mining over 90 days: drinks vs. next-morning scale, short sleep vs. appetite, salty days vs. water weight, workout-day eating, weekends vs. weekdays. Nothing leaves the device.
- **Month in Review** — a Wrapped-style poster for any month, shareable as an image.

### Other tracking

- **Water** (bottle-size step), **weight**, **alcohol** in standard drinks (~98 cal each), **supplements** (daily/weekly with reminders), **body measurements** (waist/hips/chest/arm/thigh).
- **Fasting window** *(opt-in)* — no extra logging; your last food starts the clock, the first food of the day ends it. Dashboard card + eating-window history.

### Streak

- The dashboard flame counts **any day you log something** by default (food, water, weight, workout, photo). Switch to a **strict streak** (must meet the day's goals) at onboarding or in Settings.
- Recomputed from data every time, so **backfilling a missed day** (Calendar → that day → log anything) reconnects it retroactively.

### Stats

- **Body**: weight + trend + goal, water, workout minutes by type, steps & sleep (Health), measurements.
- **Food**: calories vs. budget, protein, calorie-density mix, fiber vs. 28 g, sodium vs. 2,300 mg, alcohol, eating window.
- Every series across **Today / 7D / 30D / 90D / YTD / All / custom range**.

### Blood work (opt-in)

- Log LDL, HDL, triglycerides, fasting glucose, A1C. With the toggle on, day summaries weight swaps toward improving those markers and the nutrition report tightens the relevant limits — framed as prep for the doctor, **never medical advice**. Only the bare numbers (nothing identifying) steer requests; panels chart over time.

### Integrations

- **Apple Health (two-way)** — writes weight/water/nutrition/workouts; reads steps, sleep, and external weigh-ins (Garmin / Watch / smart scales flow in via Health).
- **Workout import** — anything written to Health (Watch, Garmin Connect, Strava…) imports into the day log once (UUID remembered), mapped to categories, counting toward minutes and the streak.
- **Widgets** — small / medium / large home screen + lock-screen (circular, rectangular, inline). The large widget shows calories, protein, water, **weight, carbs, and workout**. Widgets follow the in-app accent palette and offer one-tap water logging.
- **Siri shortcuts** — "log water," "log a meal" (spoken, itemized, totals read back), "open today."
- **Live Activity** *(optional)* — remaining calories, protein, and water on the Lock Screen / Dynamic Island.
- **Notifications** — morning weigh-in, hydration nudges (with a log-water action), workout reminders, a smart streak-at-risk guard, supplement reminders.

### Privacy, security & design

- **Face ID protects progress photos** (app entry is open) with an optional **backup PIN** (salted hash in the Keychain). Photos live in the app's Documents, invisible to the Photos app unless you export them.
- **Themed launch & app-switcher cover** — branded Steady screens, not a lock screen.
- **Photo timelapse** — builds an MP4 from progress photos on-device.
- **Themes & brand** — five accent palettes + light/dark/system, applied live; matching app icons (light & dark per palette); per-domain card tints; the native Liquid Glass tab bar on iOS 26.
- **Micro-interactions** — colored shadows, spring-settling rings/bars, and haptics on key taps and confirmations.
- **Backup export** — a single JSON with embedded photos. All data persists across rebuilds (same bundle ID) in the App Group container.

---

## Tech stack

| Area | Choice |
|---|---|
| Min OS / UI | iOS 18.0+, SwiftUI |
| Persistence | SwiftData in an App Group container (shared with widgets) |
| Frameworks | WidgetKit, HealthKit, EventKit, AVFoundation, Vision, LocalAuthentication, AppIntents |
| AI | Google Gemini (text + vision + `url_context`), Google Search grounding |
| Dependencies | None required |
| Photos | `Documents/Photos` (local, Face ID-gated) |

---

## Architecture

```
Shared/        SwiftData models, CalorieEngine, FuelingEngine, Persistence,
               WidgetSnapshot — compiled into BOTH app + widget
Widgets/       WidgetKit extension (home + lock screen, interactive logging)
75/
  App/         Entry point, photo lock (Face ID + PIN), launch/privacy
               screens, Theme (colors, cards, haptics, button styles)
  Resources/   Exercises.json (free-exercise-db), Secrets.plist (git-ignored)
  Services/    Backup, FoodDatabase (Open Food Facts), ExerciseDatabase,
               AIFoodEstimator (Gemini), HealthKit, InsightsEngine
               (on-device patterns), Notifications, CalendarSync, Timelapse
  Views/
    Onboarding/  Multi-step plan setup (incl. optional AI key step)
    Dashboard/   Rings, trend chart, streak, fuel card, tab bar (+ Settings)
    Stats/       Time-range charts for every tracked series
    Day/         Day detail logging + workout form
    Food/        Search, portion picker, describe/photo/recipe, barcode
    Calendar/    Custom month grid history
    Photos/      Gallery, viewer, compare, timelapse (Face ID gated)
    Workouts/    Builder, exercise picker + history, templates, schedule, fuel
    Settings/    Goals, targets, AI & estimates, supplements, notifications,
                 Health, appearance, backup, erase
.scratch/      Local issue tracker: PRD + implementation issues
```

> **Widget memory:** the widget target only compiles `Shared/` + `Widgets/` and never opens SwiftData at render — it reads a small precomputed `WidgetSnapshot` from the App Group, so it stays under the ~30 MB widget memory cap.

---

## Getting started

1. **Open** `75.xcodeproj` in Xcode 16+.
2. **Gemini key** *(optional)* — a shared key is bundled. To use your own, either paste one in **Settings → AI & Estimates** at runtime, or create `75/Resources/Secrets.plist` (git-ignored) with a `GeminiAPIKey` string. Free keys: [aistudio.google.com/apikey](https://aistudio.google.com/apikey).
3. **First device build** — let Xcode register the App Group + HealthKit capabilities (automatic signing).
4. **Run on device.** Free provisioning = 7-day installs; the paid Apple Developer Program ≈ 12-month installs and unlocks TestFlight.

### TestFlight

Set the destination to **Any iOS Device**, then **Product → Archive → Distribute → App Store Connect**. Testers install via the **TestFlight** app (email invite or a public link). See [`.scratch/fitness-tracker/testflight-what-to-test.md`](.scratch/fitness-tracker/testflight-what-to-test.md) for ready-to-paste beta notes.

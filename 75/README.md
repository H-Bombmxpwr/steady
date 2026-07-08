# 75 — Personal Fitness & Weight-Loss Tracker (SwiftUI + SwiftData)

A private, local-only iOS app for losing weight through proven methods. Originally a
75 Hard tracker, now a general fitness tracker built around an adaptive calorie
budget. Full product scope lives in `.scratch/fitness-tracker/PRD.md`.

## Features (current)

- **Plan setup onboarding**: profile → TDEE (Mifflin-St Jeor) → goal weight + pace →
  daily calorie budget that adjusts as your weight changes
- **Face ID lock** on launch/resume, privacy shield in the app switcher
- **Daily logging**: calories + protein (manual quick-log until the food database
  lands), water (configurable bottle-size step), weight, alcohol, named workouts
- **Dashboard** with today's targets, weight change, and projected goal date
- **Calendar** showing per-day goal completion
- **Progress photos** (camera or library), stored locally in the app's Documents —
  invisible to the Photos app unless you explicitly save them; gallery, full-screen
  viewer, and compare mode
- **Workout presets** for one-tap logging
- **Backup export** as a single JSON (embedded photos)

## Tech

- iOS 18.5+, SwiftUI, SwiftData
- No required external dependencies
- Data lives in `Documents/Fitness.store`; photos in `Documents/Photos`

## Project Structure

```
75/
  App/         App entry, Face ID lock, privacy shield
  Models/      SwiftData models (UserProfile, Plan, DayLog, WorkoutLog, PhotoEntry, WorkoutPreset)
  Engine/      CalorieEngine — BMR/TDEE, calorie budget, daily-goal scoring
  Services/    Persistence, BackupService
  Utilities/   Date/file helpers
  Views/
    Onboarding/  Multi-step plan setup
    Dashboard/   Main tab view + today's targets
    Day/         Day detail logging + workout form
    Calendar/    Day-by-day history
    Photos/      Gallery, viewer, compare
    Workouts/    Presets
    Settings/    Plan/profile editing, backup, erase
```

## Getting Started

1. Open `75.xcodeproj` in Xcode 16+.
2. Run on device (free provisioning = 7-day installs; paid Dev Program ≈ 12 months).

## Roadmap

See `.scratch/fitness-tracker/PRD.md` — food database with search + barcode,
exercise database with real workout building, widgets, notifications, HealthKit,
EventKit calendar, streaks, weekly insights, supplements, photo-of-food (stretch).

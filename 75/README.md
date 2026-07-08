# 75 — Personal Fitness & Weight-Loss Tracker (SwiftUI + SwiftData)

A private, local-only iOS app for losing weight through proven methods. Originally a
75 Hard tracker, now a general fitness tracker built around an adaptive calorie
budget. Full product scope lives in `.scratch/fitness-tracker/PRD.md`.

## Features (current)

- **Plan setup onboarding**: profile → TDEE (Mifflin-St Jeor) → goal weight + pace →
  daily calorie budget that adjusts as your weight changes → workout days → hydration
- **Food logging**: bundled USDA database (7,793 foods, offline search), barcode
  scanning via Open Food Facts, custom foods, portion picker, quick-add
- **Weight trend**: EWMA-smoothed trend line with Swift Charts, goal line,
  projected goal date
- **Workout schedule**: pick training days/times; workouts only count on scheduled
  days; **EventKit sync** writes the schedule into your iPhone calendar (local,
  no server)
- **Streaks + consistency** scoring and a weekly insight summary
- **Supplements**: your own list with daily check-off and reminders
- **Alcohol** in standard drinks (0.5 steps), ~98 cal each counted toward budget
- **Notifications**: morning weigh-in, hydration nudges (with log-water action),
  workout reminders, evening streak guard — all configurable
- **Widgets**: home screen (small/medium with tap-to-log water) and lock screen
  (circular water gauge, rectangular summary, inline)
- **Face ID** protects progress photos (app entry is open); privacy shield in the
  app switcher
- **Progress photos** (camera or library, incl. from the Photos tab), stored locally
  in the app's Documents — invisible to the Photos app unless you explicitly save
  them; gallery, viewer, compare mode
- **Dark theme**: slate surfaces, emerald-cyan gradient, rings and cards
- **Backup export** as a single JSON (embedded photos)

## Tech

- iOS 18.5+, SwiftUI, SwiftData, WidgetKit, EventKit, AVFoundation
- No required external dependencies
- Data lives in the App Group container (`Fitness.store`, shared with widgets);
  photos in `Documents/Photos`

## Project Structure

```
Shared/        SwiftData models, CalorieEngine, Persistence — compiled into app + widget
Widgets/       WidgetKit extension (home + lock screen, interactive water logging)
75/
  App/         App entry, photo Face ID lock, privacy shield, Theme
  Resources/   Foods.json (bundled USDA SR Legacy extract)
  Services/    BackupService, FoodDatabase, NotificationManager, CalendarSync
  Views/
    Onboarding/  Multi-step plan setup
    Dashboard/   Rings, trend chart, streak, weekly insight
    Day/         Day detail logging + workout form
    Food/        Food search, portion picker, barcode scanner
    Calendar/    Day-by-day history
    Photos/      Gallery, viewer, compare (Face ID gated)
    Workouts/    Weekly schedule, presets, calendar sync
    Settings/    Plan/profile/notifications/supplements, backup, erase
```

## Getting Started

1. Open `75.xcodeproj` in Xcode 16+.
2. Run on device (free provisioning = 7-day installs; paid Dev Program ≈ 12 months).

## Roadmap

See `.scratch/fitness-tracker/PRD.md` — food database with search + barcode,
exercise database with real workout building, widgets, notifications, HealthKit,
EventKit calendar, streaks, weekly insights, supplements, photo-of-food (stretch).

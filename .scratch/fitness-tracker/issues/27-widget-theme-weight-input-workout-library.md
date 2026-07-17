# Themed widgets, weight decimal fix, workout library + searchable pickers

Status: resolved
Type: feedback batch (2026-07-16)

User feedback: widgets should carry the theme accent; daily weight input
mangled decimals (224.9 → 2249); workout presets will clog the Workouts
page as they grow — wants a click-into alphabetized list with timestamps
delineating same-named workouts; the preset Picker in Log Workout is a
giant Apple menu — should use the same searchable list.

## Resolution

Themed widgets — widgets run in their own process, so
`ThemeStore.mirrorToWidgets` writes the palette raw value into App Group
defaults (and on init, migrating existing users) and calls
`WidgetCenter.reloadAllTimelines()` on every change. The widget target's
`accent/accent2/gradient` became computed vars that read the shared
palette and map to the same hex pairs as `ThemePalette`. Applies to home
screen widgets, action buttons, calorie ring, and the Live Activity
accent. `good`/`bad`/background stay fixed for legibility.

Weight decimal input — the `TextField(value:format:)` +
`.precision(.fractionLength(0...1))` combo mangled live typing. Replaced
with a text-backed field + `sanitizeWeight`: digits and one decimal
point only, max 3 integer digits (nobody weighs 1,000 lb), max 1
fraction digit; parses to `day.weight` on every keystroke, empty clears.

Workout library — `WorkoutPreset.createdAt` (additive default). New
`75/Views/Workouts/WorkoutLibrary.swift`: `WorkoutLibrary.sorted`
(case-insensitive alpha, ties oldest-first) + `duplicateNames`;
`PresetRow` shows "built Jul 12, 2:36 PM" on rows whose name repeats;
`WorkoutLibraryView` (searchable, swipe-delete, links into the existing
editor) behind an "All Workouts (N)" row on the Workouts tab —
the inline ForEach of every preset is gone. `PresetPickerSheet` (same
list, tap to pick) replaces the giant Picker menus in BOTH Log Workout
(pre-fills the form, with a "Clear preset" row) and Add to Schedule
(with a "use a custom name" escape hatch).

Build: ** BUILD SUCCEEDED ** (app + WidgetsExtension).

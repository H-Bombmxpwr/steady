# Exercise database + plan templates

Status: resolved
Type: task

Bundle yuhonas/free-exercise-db (800+ exercises, public domain) for a real
workout builder with sets/reps/weight logging and progressive-overload history.
Starter templates: 5x5, push/pull/legs, Couch-to-5K.

Blocked by: none — next major chunk from the PRD.

## Resolution (2026-07-10)

- Bundled `75/Resources/Exercises.json` — trimmed free-exercise-db extract
  (873 exercises, 668 KB: name, category, primary muscles, equipment, level,
  instructions; images dropped to keep the app small).
- `ExerciseDatabase` service: lazy load, name search with exact-word ranking,
  muscle-group filter, `byName` lookup.
- Models: `PresetExercise` (targets: sets × reps × weight, ordered) cascaded
  from `WorkoutPreset`; `SetLog` (performed sets) cascaded from `WorkoutLog`.
  Both added to the shared schema with inline defaults (lightweight migration).
- Workouts tab rebuilt around the build-first flow: 1 · Your Workouts
  (builder + templates) → 2 · Weekly Schedule (picker over presets, or custom)
  → calendar sync. Preset editor adds exercises from the DB, edits targets,
  shows step-by-step instructions, and can push the preset straight onto the
  weekly schedule.
- `WorkoutFormView` pre-fills sets/reps/weight from the chosen preset; each
  set is editable, sets/exercises can be added or removed ad hoc, and logged
  sets persist as `SetLog`s.
- Progressive overload: `ExerciseHistorySection` charts top-set weight over
  time (rep volume for bodyweight moves) inside each exercise editor.
- Templates: StrongLifts 5×5 (A/B), Push/Pull/Legs, Couch-to-5K week-1 — all
  seeded as editable presets; every exercise name verified against the DB.

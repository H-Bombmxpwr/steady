# Polish pass: widget layout, live theme, schedule flow, PIN, AI estimate, online food search

Status: resolved
Type: bug + feature batch (user feedback round, 2026-07-10)

User feedback after living with the app:
1. Medium (2×1) widget: three action buttons cut off; wanted them in one row
   and the x/total stats closer to their sections.
2. Theme change applied behind the Settings sheet but not to Settings itself;
   needed an app restart to apply everywhere.
3. Should be able to add preset workouts to the schedule — and the UI should
   encourage "build the workout, then schedule it" in that order.
4. Workout text fields need an always-available close-keyboard button.
5. Onboarding should ask for a PIN in case Face ID fails for photos (or the
   user doesn't want Face ID).
6. Googling protein counts gets old — wanted an AI estimate (e.g. free Gemini).
7. Bundled food DB not good enough vs. MyFitnessPal/Noom — wanted a better
   free source.

## Resolution

1. Medium widget rebuilt: streak + trend up top, three stat columns with the
   red/green x/total directly under each label, all three action buttons in
   one bottom row (`statColumn`, horizontal `actionLabel`).
2. Root cause: `Theme` read UserDefaults statically, so no view invalidation.
   Added `@Observable ThemeStore` (same UserDefaults keys) behind
   `Theme.palette/mode`; Settings binds via `@Bindable`. Sheets don't inherit
   `preferredColorScheme`, so `.themedRoot()` now applied to every sheet root.
   Theme changes apply instantly, everywhere, no restart.
3. Workouts tab reordered: 1 · Your Workouts (builder + templates) →
   2 · Weekly Schedule with a preset picker (or custom); preset editor has its
   own "Add to Weekly Schedule" section. (See issue 09 for the exercise DB.)
4. `keyboardDoneButton()` modifier (Done above keyboard) on workout forms,
   preset/exercise editors, portion + custom-food sheets.
5. Onboarding step 6 "Photo Privacy": optional 4+ digit backup PIN (skippable).
   Stored as salted SHA-256 in the Keychain (this-device-only). PhotoLockGate
   offers Face ID and/or PIN; Settings → Security can set/change/remove
   (change requires current PIN).
6. `AIFoodEstimator`: optional Gemini API key (Settings → AI Assist,
   free tier ≈ 1,500 req/day), "Estimate with AI" button in Custom Food fills
   calories + protein from the name. JSON-mode call to gemini-flash-latest;
   only the food name is sent.
7. Kept offline USDA for instant/private search; added on-demand
   **Open Food Facts text search** (~3M crowd-sourced products — the same
   crowd-sourced model as MFP, but open/free) as a "Search online" section
   under local results. Barcode scan already used OFF.

Build: `** BUILD SUCCEEDED **` (scheme 75, iOS Simulator); Exercises.json
verified in the app bundle.

Not done / watch for: runtime verification on device (widgets, HealthKit,
notifications, SwiftData migration with new PresetExercise/SetLog models);
BackupService export doesn't yet include preset exercises or set logs.

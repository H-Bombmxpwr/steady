# UI character pass, Body/Food stats split, AI-silent copy, editable logs

Status: resolved
Type: feature batch (2026-07-11)

User requests:
1. App is "a lot of dark and the theme color" — another UI sweep for
   character without changing flow or functionality.
2. Stats: keep weight stats where they are, move all food stats to a
   separate tab, add a food stats section.
3. Remove every mention of AI from the app, except one About in Settings
   explaining where AI is used. No "Build my meal with AI" branding.
4. Logged meals: click into a food afterwards and change values (the
   estimates bring back a lot of numbers).
5. What's the quota on the Gemini API? (answered in chat: Google now
   shows per-key limits only at aistudio.google.com/rate-limit; free
   tier flash-lite has historically been ~15 RPM / ~1,000 req-day.)
6. Weight field on today pre-fills "0" that has to be deleted first.
7. "Logging to" meal picker shouldn't horizontally scroll — wrap chips
   onto one screen.

## Resolution

Character (`Theme.swift` + call sites):
- Fixed per-domain hues so screens aren't wall-to-wall accent:
  `waterTint` sky, `foodTint` tangerine, `weightTint` violet,
  `alcoholTint` amber, `supplementTint` teal, `workoutTint` raspberry,
  `photoTint` pink, `sleepTint` periwinkle. `SectionIcon`/`SectionHeader`
  take an optional tint (theme gradient stays the fallback).
- `Meal.color`: each meal has its own hue (breakfast gold → dessert
  pink), used in day-screen meal rows, meal detail header, and the
  picker chips.
- Day screen headers all tinted per domain; meal rows use 30 pt color
  chips; stat tiles got tinted values + hairline borders.

Stats (`StatsView.swift`):
- Segmented **Body | Food** tabs above the range picker.
- Body: lb-trend/exercise/water tiles, weight, water, workouts, steps,
  sleep, measurements.
- Food: avg cal/protein/fiber/sodium/drinks/days-logged tiles, calories
  vs budget, protein, **new calorie-density mix** (stacked
  green/orange/red/unrated per day), **new fiber chart** (28 g goal,
  green when met), **new sodium chart** (2,300 mg rule, red when over),
  alcohol.

AI-silent copy:
- All user-facing strings scrubbed: "Estimate with AI" → "Estimate
  Nutrition", "AI assumed:" → "Assumed:", "AI will estimate" →
  "auto-estimated", "AI" badge → "est.", "Full Nutrition (AI)" → "Full
  Nutrition", list/footer copy reworded. Grep confirms the only AI
  strings left are in Settings.
- Settings "AI Assist" → **About Estimates**: explains exactly where
  Gemini is used (describe / photo / custom estimates / protein
  fill-ins / day summary), what's sent (food text + food photos only),
  and hosts the API key field.

Editable logs (`NutritionViews.swift`):
- `FoodNutritionSheet` is now fully editable via `@Bindable` — name,
  meal (moves the food between meals), portion grams, calories,
  protein, and all 12 nutrients edit in place and autosave; density
  re-buckets from the edited numbers on dismiss.

Fixes:
- Weight field binds `Double?` so it shows the placeholder instead of a
  "0" to delete; quick-add cal/protein fields same treatment.
- "Logging to" picker: horizontal scroll → 3-column grid of meal chips
  (2 rows, all six visible, each in its meal color).

Build: `** BUILD SUCCEEDED **`.

# Meals, full micronutrient tracking, day coach, food UX overhaul

Status: resolved
Type: feature batch (2026-07-11)

User requests (two rounds):

Round 1:
1. Log food into meals: breakfast / morning snack / lunch / afternoon
   snack / dinner / dessert. Day stats stay whole-day across meals.
2. Gemini is the primary path — "Describe" should be highlighted and big
   at the top of Add Food; database/photo/barcode smaller but present.
3. Barcode scanner needs a crosshair so you know where to point.
4. Progress photo buttons on the day look bad side by side — redo.
5. Add Food entry point at the TOP of the day, not below the food list,
   and a bigger/better button.
6. Track a lot more than calories/protein (cholesterol, LDL-adjacent
   panel, "anything else that makes sense") since Gemini can supply it.
7. Density colors wrong — large pancakes came up green.
8. In-depth, Noom-level food stats; cater the Gemini ask to that.

Round 2:
9. AI meal items must be editable after Gemini builds them (fix wrong
   stats), and removable.
10. Per-item assumptions, not just one overall line (overall can stay).
11. Stop combining components (olive oil+tomatoes merged; cream
    cheese+feta merged). Every assumed component separate.
12. Day screen shows meals, not individual foods; click a meal to see
    foods; click a food for its stats.
13. "Summarize meals of the day" button under Food → Gemini reviews the
    day and suggests substitutions into what was actually eaten.
14. Live-test meal builds and make sure returned data makes sense.
15. Camera button on today was missing its camera icon.
16. General aesthetics pass — more character, same flow/functionality.

## Resolution

Model (`Shared/DayLog.swift`):
- `Meal` enum (6 meals, labels, SF icons, `suggested(at:)` time-of-day
  default). `FoodLog.mealRaw` ("" for pre-meal logs → "Other" group).
- `NutritionFacts` struct: carbs, fat, sat fat, trans fat, cholesterol,
  sodium, fiber, total sugar, added sugar, potassium, calcium, iron —
  stored as 12 defaulted columns on `FoodLog` (lightweight migration),
  exposed via a `facts` computed property; `DayLog.totalFacts` sums the
  day; `DayLog.foods(for:)` groups by meal.

Data sources:
- OFF (`FoodDatabase.swift`): shared `Nutriments` decoder now pulls the
  full per-100g panel (cholesterol/sodium/potassium/calcium/iron come in
  grams → converted to mg); barcode lookup returns a `FoodItem` (
  `ScannedProduct` removed); `FoodItem.facts(grams:)` scales the panel.
- Gemini (`AIFoodEstimator.swift`): one `nutritionSchema` + coaching
  guidance shared by describe/photo/custom prompts — every estimate
  returns the full panel + `portion_grams` + per-item `assumed`.
  Describe prompt now hard-forbids merging components ("feta and cream
  cheese are two items; olive oil is never folded into the vegetables").
  **Density is computed locally** from kcal ÷ portion grams (model was
  unreliable: large pancakes came back green; now 1.75 cal/g → orange).
  New `reviewDay(day:targets:)` → headline / wins / substitution
  suggestions tied to specific foods eaten.

UI:
- `FoodSearchView`: meal chip picker ("Logging to") on top, always
  visible; big gradient "Describe Your Meal" hero; smaller "Other ways
  to log" (photo/barcode/database/custom); every add path stamps the
  selected meal; portion + custom sheets show the compact nutrient rows
  and "Add to <Meal>".
- `DescribeMealView`: items show per-item assumption lines; tap opens
  `MealItemEditSheet` (name, portion g, calories, protein + all 12
  nutrients editable; density re-buckets from edited numbers); swipe
  still removes; logs carry grams/facts/density.
- `DayDetailView`: Food section = gradient Add Food hero (suggests the
  current meal) → per-meal rows (icon, item count, protein, cal) →
  Nutrition Report link → "Summarize My Day" → quick add. Foods no
  longer listed inline; `MealDetailView` (new) lists one meal's foods,
  swipe-delete, tap → `FoodNutritionSheet`. Photo buttons redone as two
  equal-width buttons w/ explicit icons (Label icons were being
  swallowed → explicit HStack). `DaySummarySheet` (new) runs the Gemini
  day review.
- `NutritionViews.swift` (new): `NutritionFactsRows`,
  `FoodNutritionSheet`, `DayNutritionView` — Noom-level report: energy
  vs budget, macro split %, Keep Under (sat fat 20g / trans / chol
  300mg / sodium 2300mg / added sugar 50g) with red-when-over bars, Get
  Enough (fiber/potassium/calcium/iron FDA DVs), calorie-density mix,
  by-meal breakdown.
- `BarcodeScannerView`: dimmed mask + corner-bracket reticle + red
  laser line + hint text; `rectOfInterest` restricted to the window
  (set after `AVCaptureSessionDidStartRunning`).
- Aesthetics (`Theme.swift`): `SectionIcon` gradient chips +
  `SectionHeader` (natural-case, icon) applied across the day screen,
  Add Food, and the nutrition report. No flow changes.

Live prompt tests (curl, gemini-flash-lite-latest, temp 0):
- Salmon pasta w/ 1/2 box pasta, feta, cream cheese, tomatoes, olive
  oil → 6 separate items, each with its own assumption ("2 tbsp, used
  for cooking and finishing"), sane USDA-ish numbers (1725 cal total).
- Chipotle bowl → 8 items incl. cooking oil as its own line.
- 3 large pancakes + butter + syrup + milk → pancakes now **orange**
  (525 cal / 300 g), butter/syrup red, syrup 48 g added sugar.
- Day review → specific swaps ("swap the cream cheese and half the
  olive oil for mashed avocado; ~8 g less sat fat"), no generic advice.

Build: `** BUILD SUCCEEDED **` (app + WidgetsExtension).

Known limits: quick-add cal/protein carries no micro panel (noted in
report footers); OFF entries often omit micros — AI-logged meals are the
richest; editing a custom food's calories after an AI estimate doesn't
rescale the stored panel.

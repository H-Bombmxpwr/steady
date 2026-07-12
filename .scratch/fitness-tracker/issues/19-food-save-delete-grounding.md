# Food save/delete overhaul, delete-meal button, Search-grounded estimates

Status: resolved
Type: bug fix + feature batch (2026-07-12)

User reports/requests:
1. Deleting items in a meal doesn't save; can't delete meals; changes
   only show after relaunch, and inconsistently. "Overhaul the saving
   and deleting system for food — deleting like never works."
2. Dedicated delete-meal button.
3. Food logging accuracy: Gemini should check what Google has
   (MyNetDiary-style lookups) instead of estimating from memory.
4. Describe-meal should handle restaurants ("say the meal and the
   restaurant and it knows").

## Root cause (deletes)

`MealDetailView.onDelete` called `context.delete(food)` with **no save**
and **without removing the item from `day.foods`** — SwiftData keeps the
tombstoned object in the relationship array until a save happens, so the
list kept showing it. The only food save was `DayDetailView.onDisappear`,
which doesn't run when you go deeper into the stack (day → meal →
delete → back) — hence "works after relaunch, sometimes".

## Resolution

Persistence (`Shared/DayLog.swift`, `Shared/Utilities.swift`):
- All food mutations now go through three DayLog methods that mutate the
  relationship array (immediate UI refresh) AND save immediately:
  `addFood(_:meal:)`, `removeFood(_:)`, `removeMeal(_:)`.
- Call sites rewired: FoodSearchView add path, MealDetailView swipe
  delete, day-screen meal rows. `FoodNutritionSheet` saves on Done.
- `ensureDay` saves right after creating a day so a widget's separate
  ModelContext can't race it into duplicate day rows.

Delete meal:
- `MealDetailView`: destructive "Delete <Meal>" button (own section) +
  trash toolbar icon, behind a confirmation dialog showing the item
  count; deletes everything in the meal and pops back.
- Day screen: meal rows are also swipe-to-delete (whole meal).

Accuracy (`AIFoodEstimator.swift`):
- Describe / photo / custom estimates now run **grounded with Google
  Search** (`tools: google_search`): the model looks up real nutrition
  sources (restaurant pages, USDA, brand data) instead of answering
  from memory. Search grounding is incompatible with JSON response
  mode, so grounded calls return text and the outermost `{…}` is
  extracted. Grounded timeout 35 s. **Any grounded failure falls back
  to the plain JSON-mode call**, so logging keeps working if the
  grounding quota (free tier ~500/day) runs out.
- Restaurant awareness: guidance now says to search for and use the
  named restaurant/chain/brand's published nutrition and to say so in
  "assumed". Describe screen placeholder/footer prompt users to name
  the restaurant.
- NOT live-verified: the bundled key was at its daily free-tier quota
  during this change (429 RESOURCE_EXHAUSTED all attempts). The
  fallback path is the previously-tested behavior. Verify grounding
  fires (check "assumed" mentions sources) after the quota resets
  (midnight Pacific).

Build: `** BUILD SUCCEEDED **` (app + WidgetsExtension).

# Portion steppers everywhere, grounding badge, itemized photo meals, accuracy dial

Status: resolved
Type: feedback batch (2026-07-26)

User feedback: adding an AI-estimated food should assume a sensible
portion but then offer quick +/- selectors to scale it — no rebuilding
the meal to fix a portion — and every stat should follow the change.
Also asked whether Gemini estimates are trustworthy and whether meals
are really broken into component parts (they are; the trust question
turned into the grounding badge and the accuracy toggle below).

## Resolution

Portion steppers — new `MealItem.scaled(by:)` (linear scale of
calories/protein/grams/full facts; density is per-gram, so invariant).
Describe Meal: each reviewed item now carries a `0.25×–5×` stepper
(`multipliers: [UUID: Double]` beside the base items); row numbers, the
Log-N-items total, and the logged FoodLogs all use the scaled values.
Hand-editing an item in its sheet makes those numbers the new 1×
baseline. Custom-food/AI-estimate sheet: "Portion" stepper (0.25×–10×)
rescales calories, protein, grams, and the panel by ratio so it
composes with manual edits; resets to 1× on re-estimate. Logged foods:
`FoodNutritionSheet` got the same ratio stepper ("× logged"), so a
portion fix after logging is two taps. Database/OFF foods already had
servings steppers — now every food path scales.

Grounding badge — `generateGrounded` (replacing the silent
grounded-then-fallback `generate(grounded:)`) reports whether the
Google-Search-grounded attempt actually answered. `Estimate` and
`MealBreakdown` carry `grounded: Bool`; shared `GroundingBadge` (green
"Looked up" seal vs orange "Best guess" wand) shows in the Describe
Meal "Your Meal" header and next to the custom-food "Assumed:" line.
Settings "Where AI is used" copy explains the badge.

Itemized photo meals — the Photo of Food camera no longer produces one
lump `Estimate` (that path + `CustomFoodRequest(estimate:)` are
deleted). New `AIFoodEstimator.mealBreakdown(photo:notes:)` runs the
same every-component-its-own-item prompt with the downscaled JPEG
inline; `DescribeMealView` gained a photo mode (thumbnail header,
auto-reads on open, text field becomes optional notes, "Re-read with
Notes" rebuild) so plates get the full item review: steppers, edit
sheets, per-item assumed portions.

Accuracy dial — Settings → About Estimates "Higher accuracy (slower)"
toggle (`ai.model.accurate`): switches every estimator call from
`gemini-flash-lite-latest` to full `gemini-flash-latest` and raises the
request timeout to 60 s (full Flash thinks before answering). Default
stays Flash-Lite for the ~1 s responses.

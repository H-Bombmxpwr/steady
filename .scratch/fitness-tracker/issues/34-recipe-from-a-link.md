# Recipe from a link: URL/video → itemized nutrition

Status: resolved
Type: feature (2026-08-01)

User idea: paste a website link or video and have it translate the recipe
to calories — reading the description/comments for accuracy where needed.
Built as the warm-up before workout fueling (issue 33).

## What shipped

A third headline path on Add Food — "Recipe from a Link" — beside Describe
Your Meal and Photo of Food. `RecipeImportView` takes a pasted URL
(auto-fills from the clipboard), and `AIFoodEstimator.recipeBreakdown(url:)`
reads it: web pages via Gemini's `url_context` tool, YouTube via native
video understanding (the URL is passed as a `file_data` part and the prompt
tells the model to lean on the description + top comments for exact
quantities). Also enables `google_search` so branded/packaged ingredients
cross-check against real nutrition. Forces the fuller `gemini-flash-latest`
model on a 90 s timeout — recipe import is an occasional get-it-right action.

Reuses the whole existing itemized pipeline: `MealItem` list, the per-item
`MealItemEditSheet` (made non-private), the grounding badge, and `FoodLog`
logging. The one recipe-specific twist is servings: `recipeBreakdown`
returns whole-recipe nutrition + a servings count, and the view divides down
to the servings you actually log (default one, steppable up to the whole
batch) — reusing `MealItem.scaled(by:)`.

Short-form video (TikTok/Instagram) is best-effort — not natively fetchable.
When a link can't be read, the model returns `{"items": [], "note": …}` and
the view shows a clear fallback (`EstimatorError.linkUnread`) pointing at a
recipe site/YouTube or Describe Your Meal.

Added to the AI settings transparency catalog (new "Recipe from a Link"
prompt) and the "how AI is used" list.

## Caveat

The url_context / YouTube reading follows Gemini's documented API but wasn't
exercised against the live endpoint here — needs on-device testing with a
key. If `gemini-flash-latest` ever rejects `url_context`, that's the first
thing to check.

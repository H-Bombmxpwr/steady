# Food goes online-first: Open Food Facts + Gemini fallback, bundled key

Status: resolved
Type: feature / rework (user request, 2026-07-10)

User decisions:
- Open Food Facts becomes THE food database — internet is fine for food
  (photos must stay local). Live dropdown/autofill while typing, sorted by
  relevance (OFF doesn't return relevance order on its own).
- Drop the bundled offline USDA database; offline users enter food manually.
- Gemini API key provided by user; bundle it so the app always has it, but
  keep it out of git.
- If OFF has the food but no protein → AI auto-fills protein.
- If OFF doesn't have the food at all → AI fills in everything.

## Resolution

- **Removed** `75/Resources/Foods.json` (~1 MB USDA extract) and the
  `FoodDatabase` class. `FoodItem` + `OpenFoodFacts` (barcode + search) live on
  in `FoodDatabase.swift`.
- **Live search**: 400 ms debounced task on every keystroke (≥3 chars) against
  `us.openfoodfacts.org` (US subdomain — the world index surfaced French
  products first). `sort_by=unique_scans_n` then client-side re-rank:
  exact word −10k, prefix −4k, substring −1k per token, name-length penalty,
  OFF popularity as tiebreak.
- **Protein gap → AI**: `FoodItem.pu` flags a missing protein value (optional
  field, so decoding older payloads is unaffected). PortionSheet auto-calls
  `AIFoodEstimator.proteinPer100g(food:)` on appear, shows a spinner then an
  "AI" badge; the estimated value is used in the logged FoodLog. Barcode scans
  with no protein get the same treatment.
- **No match → AI**: "Not listed? AI estimates “query”" row opens Custom Food
  pre-filled with the query and auto-runs the full calories+protein estimate
  (editable before adding).
- **Key handling**: `75/Resources/Secrets.plist` (GeminiAPIKey) — git-ignored,
  auto-bundled by the synchronized group. `AIFoodEstimator.apiKey` prefers a
  Settings-entered key, falls back to the bundled one. Verified ignored by
  git and present in the built .app. Key tested live (chicken breast → 31 g
  protein/100 g). README documents recreating the file on a fresh clone.
- **Photo-of-food**: classification still fully on-device; candidate labels
  are now matched against OFF online (label text only — the photo never
  leaves the device).
- Offline behavior: search shows a "couldn't reach OFF" note; Custom Food
  manual entry always works.

Build: `** BUILD SUCCEEDED **`. OFF search + Gemini endpoints tested with curl.

# Describe-your-meal (typed + dictated), Noom density colors, photo re-lock

Status: resolved
Type: feature batch (2026-07-11)

User requests:
1. Gemini works better than search — promote it: food menu should offer
   add-by-database / scan barcode / photo of food / **describe your meal**
   (plaintext → Gemini builds calories + protein).
2. Speech-to-text so a meal can be spoken, not typed.
3. Noom-style red/orange/green food groups "if easily implemented" — as a
   stat on food.
4. Define the color rules somewhere visible (settings or food menu).
5. Photos tab: top-left lock button to re-lock behind Face ID.

## Resolution

1. Add Food empty state now lists five entries: Search the Database (focuses
   the search field via `searchable(isPresented:)`), Scan Barcode, Photo of
   Food, **Describe Your Meal**, Custom Food.
2. `DescribeMealView`: TextEditor + live dictation (`SpeechTranscriber` —
   SFSpeechRecognizer + AVAudioEngine, partial results streamed into the
   field; mic/speech usage strings added to -5-Info.plist). "Build My Meal"
   calls `AIFoodEstimator.mealBreakdown` → itemized list (name, cal, protein,
   density dot), swipe-to-remove, "AI assumed" footer, one-tap log of all
   items as individual FoodLogs (source "ai"). Live-tested the JSON contract
   (eggs/toast/butter/OJ → 4 items, sane densities).
3. Easy — it's just calorie density, which per-100g data already gives us.
   `FoodDensity` enum: green < 1 kcal/g, orange 1–2.4, red > 2.4 (Noom's
   solid-food cutoffs). Dots shown in search results, the portion sheet
   (with full label), the described-meal list, and the day log's food rows.
   `FoodLog.density` (optional string, lightweight migration) persists it;
   AI supplies the bucket for described meals.
4. Legend lives in the Add Food menu footer, right under the five options.
5. PhotosGalleryView: lock.fill button top-left calls `appLock.lockPhotos()`.

Build: `** BUILD SUCCEEDED **`.

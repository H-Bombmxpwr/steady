# Connectivity fixes + photo-of-food replaced with Gemini vision

Status: resolved
Type: bug batch + feature swap (2026-07-11, device testing feedback)

User reports (all about the Open Food Facts API + AI paths):
1. App feels like it has connectivity issues overall.
2. "Estimate with AI" takes forever.
3. The "Not listed? AI estimates …" button didn't carry the search text /
   didn't start estimating.
4. Typing a food fails on the FIRST search nearly every time; "Try Again"
   sometimes works.
5. Photo-of-food (Vision classifier) "sucks — not even close; a MUCH better
   model is needed" → remove/replace.

## Diagnosis

- (2) The default `gemini-flash-latest` resolves to a thinking model — the
  curl response even contained `thoughtSignature`. It reasons for many
  seconds before emitting 20 tokens of JSON.
- (3) Classic SwiftUI bug: `sheet(isPresented:)` content captured stale
  `customPrefill`/`customAutoEstimate` state → sheet opened empty with
  auto-estimate off.
- (4) Measured with curl: OFF's cgi search returns 503 on the first (cold)
  request for a query and 200 on retry — their cache warms up. Their newer
  search-a-licious endpoint was straight-up 502 during testing. It's OFF's
  infrastructure, not the app or the phone.

## Resolution

1/2. Model switched to `gemini-flash-lite-latest` (no thinking pass) —
   measured 0.8 s for a full estimate vs 10+ s. 20 s request timeout added.
3. Replaced with `sheet(item:)` + `CustomFoodRequest` (Identifiable), which
   always constructs the sheet from fresh values. Same mechanism now feeds
   photo results into the editable sheet.
4. `OpenFoodFacts.search` now: session-scoped per-query cache; up to 3
   attempts with 1.5 s/3 s backoff on any failure (silently — the user only
   sees an error if all three fail); honors task cancellation between
   attempts; debounce raised 400→550 ms to respect OFF's 10 req/min limit.
5. Deleted `FoodPhotoRecognizer.swift` (Vision's ~1300 generic classes were
   never going to cut it). "Photo of Food" now downscales the shot to 768 px
   JPEG and sends it to Gemini vision → `{name, calories, protein, assumed}`
   → opens the editable Custom Food sheet pre-filled. Food photos go to
   Google; progress photos still never leave the device (Settings footer +
   README updated to say exactly that).

Build: `** BUILD SUCCEEDED **`.

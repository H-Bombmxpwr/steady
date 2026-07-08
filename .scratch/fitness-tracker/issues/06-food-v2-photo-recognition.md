# Food v2: search ranking, optional protein, photo-of-food

Status: resolved
Type: task

"apple" must rank the fruit above APPLEBEE'S (exact-word + branded penalty).
Custom food: protein-unknown toggle. Photo-of-food: on-device Vision classifier
matched to USDA DB, user confirms dish + portion. No uploads.

## Answer
Done in the phase-5 commit. Recognition quality is bounded by Apple's built-in
classifier; revisit with a dedicated food CoreML model if it disappoints.

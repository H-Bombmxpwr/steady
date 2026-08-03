# Onboarding: offer your own Gemini key (or skip to the bundled one)

Status: resolved
Type: feedback (2026-08-02)

Users should learn about the AI key during first-run setup: the app ships a
shared key so estimates work immediately, but offer to add a personal key
and walk them through how — or skip and use the bundled one.

## Resolution

New "AI Assist" step in `OnboardingView`, inserted after Blood Work and
before Photo Privacy (steps renumbered: labs → AI → privacy). It explains
what Gemini powers, offers an optional paste-a-key field bound to the same
`AIFoodEstimator.apiKeyKey`, and links to the reusable `GeminiKeyGuideView`
(the step-by-step "get a free key" screen). The primary button reads "Use
Built-in Key & Continue" when the field is empty and "Save Key & Continue"
when a key is pasted, so skipping is a clear one-tap path. The footer notes
it's changeable later in Settings → AI & Estimates.

Build succeeded (app scheme).

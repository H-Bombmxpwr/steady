# Dial back estimate over-bias; AI settings screen with prompt transparency

Status: resolved
Type: feedback (2026-08-01)

Two pieces of user feedback:

1. Food estimates come back "a little too far" — consistently over. The
   shared `nutritionGuidance` told the model to "err large, people
   underestimate," which biased every calorie/portion number upward.
2. Surface how AI is used and the actual prompts. Move the "Where AI is
   used" blurb out of the main Settings list into its own submenu, show a
   menu of how AI is used, and add a spot that details every prompt being
   sent — with the user's own input shown as placeholders.

## Resolution

**Estimate bias.** Rewrote `nutritionGuidance` (AIFoodEstimator.swift) to
push for the accurate middle of the plausible range instead of the high
end: "do NOT inflate," "assume an average adult serving," "round toward
the honest number rather than padding for safety." Kept the
restaurant/brand-lookup instruction and the include-cooking-fats note.
Because this constant is shared by Describe Meal, Photo, Estimate, and
Suggest Meals, all four paths get the same de-biasing. (Temperature was
already 0.)

**Prompt transparency.** Added `AIFoodEstimator.PromptInfo` and a
`promptCatalog` computed in the same file as the private guidance/schema
constants, so the previews are built from the exact same strings the live
calls use and can't drift. Each entry carries title, when-it-fires,
what-leaves-the-device, a grounded flag, and the full template with user
input rendered as ‹placeholders›. Six entries: Describe Your Meal, Photo
of Food, Estimate Nutrition, Fill in Missing Protein, What Should I Eat?,
Summarize My Day.

New `AISettingsView` (Views/Settings/AISettingsView.swift) holds the
"How AI is used" text, the Gemini key field, the Higher-accuracy toggle,
and a list of the prompts; each row pushes a `PromptDetailView` showing
when/sends/grounding plus the verbatim monospaced, selectable prompt. The
main SettingsView "About Estimates" section is now a single
`NavigationLink → AISettingsView` row (sparkles icon) with a one-line
privacy footer; the inline blurb, key field, and toggle moved into the
new screen, and the two now-unused `@AppStorage` bindings were removed
from SettingsView.

Build succeeded (app scheme, generic iOS device).

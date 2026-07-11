# Blood work: opt-in lab panel steering summaries and targets

Status: resolved
Type: feature batch (2026-07-11)

User request: add a Labs section — a toggle at onboarding and toggleable
anytime in Settings — framed as doctor-visit prep, not medical advice.
Prompt for just a couple of lab results, then lean day summaries (and
similar) toward those goals, sending NO identifying information.

## Resolution

Model (`Shared/Plan.swift`, registered in `Persistence.swift` schema):
- `LabResult` @Model: date + optional LDL, HDL, triglycerides, fasting
  glucose (mg/dL) and A1C (%). `Plan.labs` cascade relationship with a
  default (lightweight migration); `Plan.latestLabs` helper.

Opt-in plumbing:
- One flag: `@AppStorage("labs.enabled")`. Values are stored on device
  regardless; the flag controls whether the bare numbers are used to
  steer anything (including the Gemini summary request).

Onboarding (`OnboardingView.swift`):
- New step 6 "Blood Work" between Hydration and Photo Privacy: the
  toggle + five optional fields. Footer states the framing: prep for
  the doctor, not medical advice; numbers only; changeable anytime in
  Settings → Blood Work. `createPlan` saves a first panel if any value
  was entered.

Settings (`SettingsView.swift`):
- "Blood Work" section above About Estimates: the same toggle, a recap
  of the latest panel (values + date), and "Log a New Panel" →
  `LabEntrySheet` (date + five optional fields, saves to `plan.labs`).

Coaching (`AIFoodEstimator.swift`):
- `LabSnapshot` — bare numbers only, built from `LabResult`; its
  `promptLine` renders e.g. "LDL 162 mg/dL, HDL 41 mg/dL, …".
- `reviewDay(day:targets:labs:)`: when a snapshot is passed, the prompt
  weights swaps toward the markers (sat/trans fat + soluble fiber for
  lipids; added sugar + refined carbs for glucose/A1C), requires
  doctor-visit framing, and forbids diagnosis/medication advice.
  Live-tested: bacon+toast → oatmeal+flaxseed "to help manage LDL …
  discuss with your doctor"; soda → sparkling water tied to glucose.

Targets (`NutritionViews.swift`):
- `NutrientGoals` replaces the hard-coded FDA limits in the day report.
  With labs on: LDL ≥ 130 or trig ≥ 150 tightens sat fat to 13 g,
  cholesterol to 200 mg, raises fiber goal to 35 g; glucose ≥ 100 or
  A1C ≥ 5.7 halves the added-sugar limit to 25 g. Footer explains the
  tightening and points at the doctor conversation.

Stats (`StatsView.swift`):
- Food tab gains a "Lab Panels" line chart (LDL/HDL/triglycerides/
  glucose over time) once any panel is logged.

Privacy: the summary request includes only the marker names and values
— no name, age, sex, weight, or anything else; everything else stays on
device as before.

Build: `** BUILD SUCCEEDED **` (app + WidgetsExtension — schema change
is additive with defaults, so existing stores migrate in place).

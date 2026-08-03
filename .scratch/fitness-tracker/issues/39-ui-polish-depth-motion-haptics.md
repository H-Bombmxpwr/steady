# UI polish: depth, motion, and haptics (less "stock native")

Status: resolved
Type: feedback (2026-08-03)

The app felt a bit robotic/standard-native. Applied common polish techniques
(colored shadows, spring micro-interactions, haptics, tinted gradients,
material) mostly at the shared-component level so it lifts the whole app.

## Changes

Shared components (Theme.swift), so every screen benefits:
- **Card** — replaced the flat black shadow with a layered pair: a soft
  ambient shadow plus a colored glow in the card's own tint, for a premium
  floating feel. Added a faint lit-from-above gradient wash in the tint.
- **StatRing / GradientBar** — value changes now settle with a spring
  instead of a linear ease, so rings and bars feel physical.
- **Haptics** — a small wrapper (tap / soft / success / selection).
- **PressableButtonStyle** (`.buttonStyle(.pressable)`) — subtle spring
  scale-down + light haptic on press; keeps the button's own look.
- **PrimaryActionButtonStyle** (`.buttonStyle(.primaryAction)`) — a
  prominent gradient CTA with a colored shadow that tightens on press.

Applied:
- The three food-entry headline buttons (Describe / Photo / Recipe) are now
  `.pressable`.
- A success haptic fires when a meal is logged (Describe + Recipe paths).
- Onboarding ends on a gradient `.primaryAction` "Start Tracking" CTA, and
  plan creation fires a success haptic.

The glass tab bar already used `.ultraThinMaterial`, a colored pill shadow,
and selection haptics — left as-is. The new button styles are available to
sprinkle onto any other button later.

Build succeeded (app scheme).

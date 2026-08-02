# Themed launch screen; branded (not "locked") privacy cover

Status: resolved
Type: bug / feedback (2026-08-01)

On first open (especially right after re-installing to the device) the app
flashed a black "Locked" screen with a lock symbol — a leftover-looking
whole-app lock — and the same lock screen showed in the app switcher. The
app doesn't actually lock as a whole (only the Photos section does, via
Face ID / PIN); the "lock" was the privacy shield overlay.

## Cause

`SeventyFiveHardApp` started with `showPrivacyShield = true`, so before the
scene reached `.active` the `PrivacyShieldView` (a black screen with
`lock.fill` + "Locked") was visible at launch. That same view is what
covers the app in the multitasking preview, so the app switcher also looked
like the whole app was locked.

## Fix

- New themed **launch screen** (`LaunchLoadingView`): the brand backdrop
  (`BrandSplashView`) — adaptive background, the app-icon motif (`BrandMark`:
  gradient tile + diagonal line), the "Steady" wordmark — plus a gradient
  progress bar that fills (~1s) then fades into the app.
- **Privacy cover** re-themed: `PrivacyShieldView` now renders the same
  branded backdrop with NO lock symbol or "Locked" text, so the app switcher
  shows a clean Steady cover, not a lock screen. Content is still hidden in
  the multitasking preview.
- **No launch flash**: `showPrivacyShield` now starts false and only turns on
  after the app has been active once (`hasBecomeActive`), and a `launching`
  overlay covers the very first frames. The Photos section remains the only
  thing that actually locks (`AppLockManager`, unchanged).

Also fixed the recurring `ForEach ID "T"/"S" occurs multiple times` console
warning: the calendar's weekday-initials row keyed on `\.self`, and the
initials repeat (S,M,T,W,T,F,S) — now index-keyed.

Build succeeded (app scheme).

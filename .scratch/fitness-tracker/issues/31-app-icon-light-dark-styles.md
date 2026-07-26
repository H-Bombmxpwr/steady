# App icon: light + dark style for every palette, all selectable

Status: resolved
Type: feedback (2026-07-26)

User feedback: the app icon should come in two consistent styles — a dark
style (black background, colored line) and a light style (colored
background, white line) — for every accent palette, and all of them
should be selectable at any time (not tied to the in-app theme mode).
Before this, only emerald shipped both styles (via the primary icon's
iOS 18 light/dark appearance variants); the four alternates
(Ocean/Sunset/Violet/Rose) shipped only the light style, so they always
looked like "color background, white line."

## Resolution

Generated the four missing dark variants (`Icon-{Ocean,Sunset,Violet,
Rose}-Dark.png`) from the emerald `Steady-Dark.png` with a Python/PIL
script (scratchpad `gen_dark_icons.py`): the line art, gray accent dots,
glow, and vignette are identical across every icon, so it re-maps only
the colorful line region to each palette's accent0→accent1 diagonal
gradient, keeping the line's brightness shading (tube look) and leaving
the desaturated background/dots untouched. Verified each output visually.

Restructured the asset catalog into ten single-appearance alternate
icons — `Icon-<Palette>-Light` and `Icon-<Palette>-Dark` for all five
palettes — reusing the existing art for the light sets and emerald dark,
and the generated PNGs for the other darks. Because each is a fixed
single-image set (no light/dark appearance children), the chosen icon
looks the same regardless of the system's appearance — "available all
the time." The old `Icon-Ocean/Sunset/Violet/Rose` sets were removed
(their art moved into the `-Light` sets); the primary `AppIcon` stays
emerald with automatic light/dark/tinted appearances as the "Match
appearance" default. `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
updated (both configs) to the ten names.

New `AppIconOption` model (Theme.swift) enumerates palette × style.
Settings → Appearance replaces the single row of five palette dots with
a "Match appearance" row plus a per-palette Light/Dark swatch grid
(`IconSwatch` previews approximate the real look); `ui.appIcon` now
stores the alternate icon's asset name ("" = primary). Verified the ten
names register in the built app's CFBundleAlternateIcons.

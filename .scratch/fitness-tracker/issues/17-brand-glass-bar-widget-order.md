# Brand identity pass, draggable glass tab bar, widget button order

Status: resolved
Type: feature batch (2026-07-11)

User requests:
1. Widget action buttons left-to-right: Food → Today → Water (was
   Water → Food → Today).
2. UI overhaul with character and "a brand of some kind"; more colors
   but not too busy; think like a professional UI/UX designer.
3. Liquid glass tab bar on by default; slide the indicator pill across
   tabs as well as swiping between pages; make tab switching more fluid.

## Resolution

Widgets (`FitnessWidgets.swift`):
- Medium + large action rows reordered to Food → Today → +Water.

Glass tab bar (`DashboardView.swift` / `MainTabView`):
- Already defaulted on (`ui.glassBar = true` both call sites) — verified.
- Rebuilt `GlassTabBar`: a single gradient pill indicator (with soft
  accent glow) slides between tabs on a spring
  (response 0.34 / damping 0.82). A `simultaneousGesture` drag lets you
  grab and slide the pill anywhere along the bar — the fractional
  position follows the finger, pages switch live when the pill crosses
  a tab midpoint, and it snaps on release. Taps and page swipes keep
  working; selected tab renders white on the pill.

Brand (`Theme.swift` + Dashboard/Stats):
- **"75" monogram wordmark**: heavy rounded gradient tile leading the
  dashboard (with "Day N" + full date beside it); nav title moved to
  inline-empty so the header owns the top. Toolbar (Today/gear) intact.
- **Brand wash backdrop**: `themedForm()` and new `brandBackground()`
  layer a subtle accent gradient (13% → clear by mid-screen) over the
  base background — every form and scroll screen carries the accent
  breath without busyness.
- `Card` upgraded: optional icon chip + tint (border picks up 22% of
  the tint), soft drop shadow. Dashboard cards branded: Weight/violet
  scalemass, Today/tangerine sun, Streak/orange flame, Goal/accent
  target, This Week/periwinkle calendar, Measurements/violet ruler.
- `StatRing` takes a per-metric tint: calories tangerine, protein
  raspberry, water sky (falls back to theme gradient).
- "Open Today" is a gradient capsule hero with accent glow.

Build: `** BUILD SUCCEEDED **` (app + WidgetsExtension).

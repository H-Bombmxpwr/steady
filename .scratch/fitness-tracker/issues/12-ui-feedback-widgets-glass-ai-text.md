# UI feedback round 2: widget weight/Today, dashboard Today, glass tab bar, AI transparency

Status: resolved
Type: feedback batch (2026-07-10, second device pass)

User feedback:
1. Weight should not be on the widget (otherwise medium layout looks good).
2. "Open Today" should be more visible — also top-left of the Dashboard,
   opposite the settings gear.
3. Widget "Workout" button → "Today", opening the current day.
4. "Estimate with AI" should carry the search-bar text over (already shipped
   in the online-first commit — the reported build predated it).
5. "Open Food was unreachable" once.
6. AI estimates should echo what food the model assumed.
7. "Apple glass" style floating bottom bar + swipe between screens, with a
   Settings toggle to restore the standard bar.

## Resolution

1. Trend weight removed from the medium widget header and the large widget
   (large keeps the projected goal date only); `trendWeight`/`goalWeight`
   dropped from `TodaySnapshot`.
2. Dashboard toolbar: "✎ Today" NavigationLink top-left, gear stays top-right;
   the bottom "Open Today" button remains.
3. Both medium and large widgets: third button is now "Today"
   (`seventyfive://today` deep link → sheet with today's DayDetailView).
4. Confirmed shipped: "Not listed? AI estimates “query”" pre-fills Custom Food
   from the search bar and auto-runs the estimate.
5. OFF search hardening: 10 s timeout, HTTP status check with a specific
   429 rate-limit message (OFF allows 10 searches/min), and a "Try Again"
   button that re-runs the search immediately.
6. Gemini prompts now return an `assumed` string ("what food and serving I
   based this on"), shown as "AI assumed: …" in Custom Food and under the
   auto-filled protein row in the portion sheet.
7. `GlassTabBar`: floating ultra-thin-material capsule with accent highlight;
   glass mode uses a page-style TabView so tabs swipe left/right. True iOS 26
   Liquid Glass APIs need a newer SDK than this project builds against, so
   the look is recreated with materials (works on iOS 18+).
   `@AppStorage "ui.glassBar"` (default on) + Settings → Appearance toggle
   falls back to the classic TabView.

Build: `** BUILD SUCCEEDED **`.

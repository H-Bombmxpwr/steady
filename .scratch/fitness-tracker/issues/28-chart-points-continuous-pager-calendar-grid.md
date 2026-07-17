# Weight chart points + goal toggle, continuous pager, calendar month grid

Status: resolved
Type: feedback batch (2026-07-16)

User feedback: weight chart should show each day's discrete weigh-in as
a point with connecting lines; glass-bead tab movement still felt
discrete (pages snapped between slots during bead drags); the goal-line
label collided with the x-axis labels; wanted a goal-line toggle that
re-zooms the y-axis; calendar tab shouldn't list every day below the
month, and logged days need their own indicator distinct from today's.

## Resolution

Weight chart (dashboard + Stats) — each raw weigh-in is now a visible
weightTint PointMark threaded by a thin 1.5pt monotone line (series
"daily"), under the bold gradient EWMA trend (series "trend"); replaced
the old faint white dots (also fixed their light-mode invisibility).
Goal RuleMark annotation moved to `.top` so it sits above the line and
clear of the axis labels. New `chart.showGoal` AppStorage (default on):
"Hide goal line" button under the dashboard chart removes the rule and
drops the goal from the y-domain so the chart re-fits to the data;
Stats weight chart honors the same flag (its `.automatic` domain
re-fits on its own).

Continuous pager — glass mode no longer uses TabView paging at all.
`ContinuousPager` lays the five screens in an HStack offset by a single
continuous `pagePosition: CGFloat` (0…4); `GlassTabBar` now takes the
same binding, so bead drags, content swipes, and taps all move pages
and pill together fractionally — zero snapping until release, then one
spring settle. Content swipes: simultaneous DragGesture with direction
lock (vertical left to inner scroll views), left-edge starts ignored
for the nav back-swipe, rubber-banding past the ends, flicks capped at
one page via predictedEndTranslation. The old barDragging/stale-write-
back machinery is gone. Classic-bar mode still uses the standard
TabView; positions sync when toggling styles.

Calendar — the all-days list under the picker is gone. The system
graphical DatePicker (which can't decorate days) was replaced by a
custom MonthGrid card: chevron month nav (clamped plan start ↔ current
month), weekday header honoring firstWeekday, and per-day cells where a
5pt accent dot marks logged (hasActivity) days, today wears an outlined
accent ring, and the selected day is a filled gradient circle (dot goes
white on it). Out-of-plan days are dimmed/disabled. Below: a summary
card for the selected day (date, day number, % of goals, weight,
GradientBar, Open Day) and a two-item legend.

Build: ** BUILD SUCCEEDED ** (fixed one "static stored properties not
supported in generic types" on the pager's settle animation).

## Follow-up (device feedback, same day)

- Bead snapped back when slid one tab: the absolute finger-location
  mapping (`location.x / tabWidth - 0.5`) left the tracked position half
  a tab behind where the pill looked. Bead drags are now RELATIVE —
  `startPosition + translation.width / tabWidth` — so one tab-width of
  finger travel is exactly one slot.
- Bottom rows hid under the floating bar: TabView used to convert the
  safeAreaInset bar into page safe-area; the custom pager doesn't. Each
  page now gets an explicit 66pt bottom `safeAreaInset` spacer and the
  bar moved to an `overlay(alignment: .bottom)`.
- CFPrefs "kCFPreferencesAnyUser with a container" console lines on
  device install: benign cfprefsd probe noise from group UserDefaults
  (the widget theme mirror); per-user reads work fine. No action.

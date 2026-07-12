# Glass bead: live page follow + sticky release

Status: resolved
Type: bug fix (2026-07-12)

User report: dragging the bead from Dashboard to Stats and releasing
shot it back to Dashboard; only sticking at Calendar worked; couldn't
stop on Photos (odd tabs bounced). Requirements: the page must move
WITH the finger as the bead crosses each tab, and just stay put on
release.

## Root cause

The paged TabView (UIPageViewController-backed) writes stale selection
values back through its binding asynchronously while transitions are in
flight. Mid-drag selection changes raced those write-backs: after one
crossing (odd tabs) the stale write-back landed last and reverted the
selection; after two crossings (even tabs) the interleaving happened to
leave the right value.

## Resolution

The bar owns the truth while the finger is down:
- `MainTabView.barDragging` — the TabView gets a filtered binding whose
  setter drops writes while `barDragging` is true, so the pager can no
  longer clobber the user's position. Normal page swipes still write
  through when not dragging.
- `GlassTabBar` sets `dragging` on first movement, moves `selection`
  live at every midpoint crossing (animations disabled — page snaps
  under the pill, haptic tick per crossing), and on release just seats
  the pill into the slot it's on. The guard lifts 0.5 s after release
  so any still-in-flight pager transition can't undo the landing tab.

Build: ** BUILD SUCCEEDED **.

---
title: Integrations
summary: Apple Health, widgets, Siri shortcuts, Live Activity, notifications, and calendar sync.
---

# Integrations

<p class="lede">How Steady connects to the rest of your phone — Apple Health, the home screen, Siri, and your calendar.</p>

## Apple Health

The connection runs **both directions**.

**Steady writes** the weight, water, nutrition, and workouts you log, so the rest of your Health ecosystem stays current.

**Steady reads** steps, sleep, and body-weight entries — which is what makes third-party hardware work without any special integration. A **Garmin**, an **Apple Watch**, a **Withings scale**, or anything else that syncs into Apple Health shows up in Steady automatically.

You control every category individually in **iOS Settings → Privacy & Security → Health → Steady**, and you can revoke any of it at any time. Health data is used only to show you your own statistics — never for advertising, never sold, never shared.

### Workout import

Any workout written to Health imports into your day log — Apple Watch sessions, Garmin activities, Strava rides, whatever writes there.

Each one imports **exactly once** (Steady remembers the identifier), gets mapped to one of its workout categories, and counts toward your minutes and your streak. Track your runs wherever you like; they'll be here.

## Widgets

**Home screen** — small, medium, and large. The large widget shows calories, protein, water, weight, carbs, and your workout.

**Lock screen** — circular, rectangular, and inline.

Widgets follow whichever accent palette you've picked in the app, and support **one-tap water logging** without opening Steady at all.

Widgets refresh on a schedule iOS controls, not one Steady picks. Opening the app always forces an update. If a widget goes stale or blank, remove it and add it back — that's the standard fix and it works.

## Siri shortcuts

Three built in:

- *"Log water in Steady"*
- *"Log a meal in Steady"* — speak the meal, it gets itemized, and the totals are read back to you
- *"Open today in Steady"*

The meal one is genuinely useful hands-free: describe dinner while you're cleaning up and it lands in the right meal with a full breakdown.

## Live Activity

Optional, off by default. Turn it on in **Settings → Appearance** and your remaining calories, protein, and water live on the **Lock Screen and Dynamic Island**.

It refreshes whenever the app runs. There's no push server behind it — everything is scheduled locally on your device.

## Notifications

All local. Nothing is sent from any server, because there isn't one.

| Notification | When |
|---|---|
| **Morning weigh-in** | A time you pick |
| **Hydration nudges** | Through the day, with a *log water* action right in the notification |
| **Workout reminders** | Before scheduled sessions |
| **Streak at risk** | Late in the day, only if you haven't logged anything yet |
| **Supplements** | On your daily or weekly schedule |

Each one is individually switchable in **Settings → Notifications**. The streak guard is deliberately quiet — it only fires when the streak is genuinely at risk, not as a daily nag.

## Calendar sync

One tap writes your weekly workout schedule into your iPhone calendar as **repeating events**, through EventKit. It's local to your device and your calendar; nothing is uploaded.

Steady asks only for **write** access — it can add your workouts, but it cannot read anything else on your calendar.

Re-run it after changing your schedule, and use **Remove from Calendar** to pull the events back out.

<p class="next">Next: <a href="photos-and-data">Photos & your data →</a></p>

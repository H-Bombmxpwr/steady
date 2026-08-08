---
title: Integrations
summary: Apple Health, TrainingPeaks, weather, widgets, Siri shortcuts, Live Activity, notifications, and calendar sync.
---

# Integrations

<p class="lede">How Steady connects to the rest of your phone — Apple Health, your training plan, the home screen, Siri, and your calendar.</p>

## TrainingPeaks

*Athlete mode.* If you train from a plan, Steady can read it, so today's session is the first thing on your dashboard and the fuelling is built around it.

### Connecting

TrainingPeaks publishes a private calendar link for every athlete account:

1. Open **app.trainingpeaks.com** on the web — the link lives in the web app, not the phone app.
2. Go to **Account Settings → Calendar Sync**.
3. Copy the whole URL. It starts with `webcal://` or `https://` and ends in `.ics`.
4. Paste it into **Settings → TrainingPeaks** (or during setup).

No OAuth, no password, no account linking. Treat the link like a password — anyone holding it can read your training calendar — and if you ever want to cut Steady off, regenerate it in TrainingPeaks and the old one dies.

Not on TrainingPeaks, or would rather stay offline? **Import a `.ics` file** instead. Same reader, no network.

### What comes across

Each planned session brings its name, date, start time, duration, and TSS when your plan publishes one. From those Steady works out:

- **Type** — bike, run, swim, and rows map to cardio; gym and lifting to strength; yoga and mobility work to mobility. Type is what decides whether you need carbs *during* the session or only around it.
- **Intensity** — from TSS per hour where it exists (100 TSS is an hour at threshold, by definition), and from the coach's own vocabulary otherwise: *recovery* and *z2* read as easy, *threshold* and *intervals* read as hard.

Rest days are recognised and skipped rather than imported as empty sessions.

### How it syncs

Steady refreshes at most once an hour while you're using it, plus whenever you tap **Sync**. It's a **read in one direction only** — nothing you log is ever sent to TrainingPeaks.

Re-syncing reconciles rather than piles up: moved sessions update in place, and sessions your coach deleted are removed, so a cancelled Thursday stops adding calories to Thursday's budget. Sessions you added by hand are never touched.

An imported plan **overrides your weekly workout days** for any day it covers, so the two can't double-count.

## Weather

*Athlete mode.* Heat and humidity drive sweat loss harder than anything except how hard you're going, so Steady scales your fluid and sodium targets to the conditions you're actually training in.

It uses **Apple's WeatherKit** — no API key ships in the app, and the only thing that leaves your phone is a coarse coordinate, only while athlete mode is asking. Your location is never stored, never attached to anything you log, and never sent to us.

Steady doesn't ask for location until you switch weather on, and never asks for background access. Prefer not to share it at all? Turn it off and type the temperature and humidity yourself — the maths is identical.

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

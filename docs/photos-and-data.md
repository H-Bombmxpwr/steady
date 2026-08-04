---
title: Photos & your data
summary: Face ID-protected progress photos, timelapse, themes, backup, and erasing everything.
---

# Photos & your data

<p class="lede">Progress photos are the most personal thing in the app, so they get the most protection. This page covers how they're stored, plus themes, backup, and how to delete everything.</p>

## Progress photos

Photos you take in Steady are stored **inside the app's own container** — not in your Photos library. They don't appear in your camera roll, they don't sync to iCloud Photos, and they aren't visible to any other app. The only way one leaves is if you explicitly export it.

**Face ID protects them.** With photo privacy on (recommended, and offered during onboarding), viewing the gallery requires Face ID. There's an optional **backup PIN** for when Face ID fails — stored as a salted hash in the iOS Keychain, never as the PIN itself.

Worth being precise about what's protected: **the photos are gated, not the whole app.** Opening Steady doesn't require authentication — you can log lunch without a Face ID prompt. The gate sits in front of the gallery.

**The app-switcher cover** is a branded Steady screen rather than a screenshot of whatever you were looking at, so your last screen doesn't sit exposed in the multitasking view.

## Compare and timelapse

**Compare** puts any two photos side by side — useful when the scale has stalled but your shape hasn't.

**Timelapse** builds an MP4 from your progress photos, **entirely on your device**. No upload, no processing service. The video is yours to keep or share, and nothing about it leaves your phone unless you send it somewhere yourself.

## Where your data actually lives

Everything — weight, food, water, workouts, fasting, supplements, notes, photos, and settings — lives in a **private App Group container** on your iPhone. That container is shared between the app and its widgets, which is how the widgets show live data without needing a server.

There is no Steady account and no Steady server. Nothing to sign into, nothing to breach, nothing held about you anywhere else.

Your data is included in your **normal iPhone backup** (iCloud or Finder) if you have that enabled — under Apple's control and Apple's privacy terms, not Steady's.

## Backup and export

**Export a backup** from Settings and you get a **single JSON file with your photos embedded**. iOS hands you the share sheet and you choose where it goes — Files, AirDrop, email, anywhere.

Once that file leaves the app it's governed by wherever you sent it, not by Steady. Treat it like what it is: a complete copy of your health log in one file. AirDrop to your own Mac is a good habit; email is a worse one.

Because everything persists in the App Group container, your data survives app updates and rebuilds.

## Erasing everything

Two options:

- **Erase from Settings** — wipes your log while leaving the app installed.
- **Delete the app** — removes the container and everything in it.

Either way it's gone, and there's nothing on any server for anyone to recover, because it was never anywhere else.

## Themes

Five accent palettes — **emerald, ocean, sunset, violet, rose** — in light, dark, or matching your system setting, applied live.

Each palette ships with **matching app icons** in light and dark variants, so your home screen matches what's inside. There's also *Match appearance*, which follows the system.

Themes carry through the whole app: per-domain card tints (water is sky blue, food tangerine, weight violet, workouts raspberry), the charts, and the widgets.

On iOS 26 the tab bar uses Apple's native **Liquid Glass**, so it looks and behaves like the rest of the system rather than a custom imitation of it.

## What leaves your phone, in one list

**Only these, and only when you trigger them:**

1. **AI food logging** — the meal text, photo, or link you send for an estimate goes to Google Gemini. See [AI features](ai-features).
2. **Barcode lookup** — the barcode number, and only the number, goes to the Open Food Facts public database.
3. **Anything you export yourself** — a backup file, a timelapse video, a Month in Review poster.

**Never:** your weight, progress photos, Health data, location, or any identifier. There's no analytics SDK, no advertising SDK, no crash reporter phoning home, and no account tying any of it to you.

The full legal version is the [privacy policy](privacy-policy).

<p class="next">Next: <a href="support">Support & FAQ →</a></p>

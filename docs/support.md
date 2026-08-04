---
title: Support & FAQ
summary: Common questions, troubleshooting, and how to send feedback.
---

# Support & FAQ

<p class="lede">Common questions, fixes for the things that go wrong most often, and how to get in touch.</p>

**Email:** [hunter.baisden@gmail.com](mailto:hunter.baisden@gmail.com)

If you're on the TestFlight beta, the fastest route is the TestFlight app itself — or take a screenshot, tap **Share → TestFlight**, and annotate what went wrong. That sends the screenshot along with your device model and iOS version, which usually saves a round trip.

## Getting started

**Do I need an account?**
No. There's no sign-up, no login, and no server. Open the app and start logging.

**Does it cost anything?**
No, and there's no subscription, no ads, and no upsell.

**Is my data backed up anywhere?**
Not to any server — but your log is included in your normal iPhone iCloud or Finder backup. You can also export a complete backup file from Settings whenever you like. See [Photos & your data](photos-and-data).

**Can I use it on iPad?**
Not currently. Steady is iPhone-only, requiring iOS 18 or later.

## Food and AI

**The AI food logging isn't doing anything.**
Check **Settings → AI & Estimates**. If you've pasted your own key, make sure it copied cleanly — a trailing space or a partial paste is the usual culprit. If you'd rather not use your own key, clear the field and the built-in one takes over.

**Estimates feel slow.**
Turn off *Higher accuracy* in **Settings → AI & Estimates**. The default lighter model answers in about a second. Adding your own free Gemini key also helps, since you get your own rate limits instead of a shared pool.

**The calories look wrong.**
Usually portion size. Tap the item and check its assumption — it'll say something like "assumed 2 cups, ~250 g." Edit the portion and every number rescales. Also check the grounding badge: *Best guess* deserves more scrutiny than *Looked up*.

Worth knowing: consistent logging matters more than perfect logging. The [adaptive budget](calorie-budget) learns from the relationship between your intake and your weight trend, so a steady 10% under-estimate gets absorbed into your learned burn rate.

**A recipe link didn't work.**
Recipe websites and YouTube work best. Short-form video — TikTok, Instagram Reels — is genuinely hit-or-miss, because the ingredients often only exist in a caption or in speech. Paste the ingredients into **Describe Your Meal** instead; it handles a pasted list well.

**A barcode won't scan.**
Steady only reads inside the crosshair frame, so line the barcode up within it. If the product genuinely isn't in Open Food Facts, use **Describe Your Meal** or enter it by hand — and consider adding it to Open Food Facts, which is a community database.

## Health and devices

**My steps or weigh-ins aren't showing up.**
Check **iOS Settings → Privacy & Security → Health → Steady** and confirm the categories you want are switched on. It's easy to tap through that permission screen too quickly on first launch.

**My Garmin/Fitbit/Withings data isn't appearing.**
Steady reads from Apple Health rather than connecting to each service directly. Confirm your device's own app is syncing into Apple Health first — once it's in Health, Steady picks it up.

**My workouts import twice.**
They shouldn't; each import is remembered by its identifier. If you're seeing genuine duplicates, that's a bug worth reporting.

## Widgets and notifications

**The widget is blank or out of date.**
Widgets refresh on a schedule iOS controls. Opening the app forces an update. If it stays blank, remove the widget and add it back.

**I'm not getting notifications.**
Check **iOS Settings → Notifications → Steady** is allowed, then **Settings → Notifications** inside Steady for the individual toggles.

**Live Activity isn't showing.**
It's off by default — turn it on in **Settings → Appearance**. It refreshes when the app runs.

## Progress and streaks

**I missed a day — is my streak gone?**
Not necessarily. The streak is recomputed from your data every time rather than stored as a counter, so **backfilling works**: open the Calendar tab, tap the day you missed, log anything, and the streak reconnects.

**My weight went up but I stuck to my budget.**
Almost always water. Sodium, carbohydrates, hormones, and hydration move the scale several pounds in either direction, independent of fat. That's exactly why Steady shows a smoothed trend line instead of your raw weigh-ins — watch the trend, not the mornings.

**The scale hasn't moved in two weeks.**
Check the trend line rather than individual readings, and check your measurements — weight can hold flat while your shape changes. If the trend is genuinely flat over 2–3 weeks and you're logging consistently, the adaptive budget will already be adjusting your burn rate. You can also lower your target pace in Settings.

## Privacy

**What leaves my phone?**
Only three things, and only when you trigger them: meal text/photos/links you send for an AI estimate, barcode numbers sent to Open Food Facts, and anything you export yourself. Never your weight, photos, Health data, or location. See [Photos & your data](photos-and-data) and the [privacy policy](privacy-policy).

**Can anyone see my progress photos?**
They're stored inside the app's private container, gated behind Face ID, and never written to your Photos library unless you export one yourself.

**How do I delete everything?**
Erase from Settings, or delete the app — which removes the container and everything in it. There's nothing held anywhere else.

## Reporting a bug

Useful bug reports usually have three things: what you did, what you expected, and what happened instead. A screenshot beats a description. If it involves specific data — a meal that estimated strangely, a workout that imported wrong — say which one.

Send it via TestFlight feedback or to [hunter.baisden@gmail.com](mailto:hunter.baisden@gmail.com).

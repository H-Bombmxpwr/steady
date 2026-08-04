---
title: Getting started
summary: Installing Steady, setting up your plan, and what each permission is for.
---

# Getting started

<p class="lede">Installing Steady, walking through onboarding, and understanding what each permission is actually used for.</p>

## Installing

Steady is currently in **TestFlight** beta. You'll get an email invite or a public link; either way:

1. Install **TestFlight** from the App Store (free, made by Apple).
2. Open the invite link on your iPhone and tap **Accept**, then **Install**.
3. Steady appears on your home screen like any other app.

You need **iOS 18 or later** on an iPhone. TestFlight builds expire after 90 days, so you'll get a new one periodically.

## Onboarding

The first launch walks through a short setup. Nothing here is permanent — every value can be changed later in **Settings**, and changing a goal never breaks your logged history.

**1 · About you.** Age, height, current weight, and biological sex. These feed the Mifflin-St Jeor equation that estimates your starting metabolic rate. Choosing *Prefer not to say* uses the midpoint between the male and female formulas.

**2 · Activity level.** Roughly how much you move outside of workouts. This multiplies your BMR into a starting daily burn estimate. Don't agonize over it — the app corrects this number itself once you've logged for a couple of weeks.

**3 · Your goal.** Target weight and how fast you want to get there, in pounds per week. Steady shows the resulting daily calorie budget immediately, so you can see the trade-off between pace and how much you get to eat before committing.

**4 · Training days.** Which days you plan to work out. This seeds your weekly schedule — you can build real workouts later in the [Workouts tab](workouts-and-fueling).

**5 · Hydration.** Your daily water goal and the size of the bottle or glass you usually drink from, so logging water is one tap rather than typing an amount.

**6 · AI key** *(optional)*. Steady's AI food logging works out of the box. If you'd rather use your own free Google Gemini key, you can add it here or later. See [AI features](ai-features).

**7 · Photo privacy.** Whether progress photos require Face ID to view. Recommended on — see [Photos & your data](photos-and-data).

## Permissions

Steady asks for these as you first use the feature that needs them, not all at once on launch. Every one is optional; declining disables that feature and nothing else.

| Permission | What it's for |
|---|---|
| **Apple Health** | Reads steps, sleep, and weigh-ins from your devices; writes back the weight, water, nutrition, and workouts you log |
| **Camera** | Progress photos, photographing food for AI estimates, and barcode scanning |
| **Microphone & Speech** | Dictating a meal description instead of typing it |
| **Face ID** | Unlocking your private progress photos |
| **Photos (add only)** | Saving a progress photo to your library when you explicitly export one |
| **Calendar (write only)** | Adding your planned workouts as repeating calendar events |
| **Notifications** | Reminders you schedule yourself — weigh-in, hydration, workouts, supplements |

Steady never asks for permission to *read* your photo library, and it can't see photos you haven't handed it.

## Your first few days

The app is most useful once it has data to reason about, so the first week looks a little different from the rest:

- **Weigh in daily if you can.** Daily weight is noisy — water, salt, and timing move it pounds at a time — so Steady charts a smoothed trend line rather than reacting to any single morning. It needs a handful of readings before that trend means anything.
- **Log food even when it's ugly.** A rough estimate beats a blank day. The adaptive budget needs about two weeks of logs before it starts correcting your burn rate, and it only counts days you actually logged.
- **Don't chase the daily number.** One day over budget changes almost nothing. The weekly average is what moves the scale.

After roughly two weeks of consistent logging, Steady switches from *estimating* your metabolism to *measuring* it. That's when the budget starts getting personal — see [Your calorie budget](calorie-budget).

<p class="next">Next: <a href="calorie-budget">Your calorie budget →</a></p>

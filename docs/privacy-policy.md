---
title: Privacy policy
summary: Steady collects nothing. Here is exactly what that means, in detail.
---

# Privacy Policy — Steady

**Effective 8 August 2026**

Steady ("the app") is a personal health and fitness tracker for iPhone. It is built to be local-first: your data lives on your device, and there is no Steady account, server, or backend to sign in to.

---

## The short version

- **We do not collect your data.** There is no Steady server. Nothing you log is transmitted to the developer.
- **No accounts, no analytics, no advertising, no tracking**, and no third-party analytics or ad SDKs are embedded in the app.
- A handful of optional features talk to outside services, and **only when you turn them on** — see [Optional network features](#optional-network-features).
- Your Health data is never used for advertising and is never sold or shared.
- **Cycle tracking never leaves your device at all** — not to us, not to Apple Health, not to any AI feature. See [Cycle tracking](#cycle-tracking).

---

## What the app stores, and where

Everything you log — weight, food, water, workouts, fasting windows, supplements, notes, progress photos, and settings — is written to a private container on your device (an iOS App Group shared between the app and its widgets). It is included in your device's normal iCloud or Finder backup if you have that turned on, under Apple's control and Apple's privacy terms, not ours.

**Progress photos** are stored inside that private container and are protected by Face ID. They are not written to your Photos library unless you explicitly export one.

**Your Gemini API key**, if you choose to add one, is stored in the app's own preferences on the device and is sent only to Google, only as the authentication header for your own requests.

To delete everything, delete the app. That removes the container and all of its contents. There is nothing held anywhere else for us to delete.

---

## Apple Health

With your permission, Steady:

- **Reads** steps, sleep, and body-weight entries so your stats and trends reflect data from your devices — including third-party devices such as Garmin that sync into Apple Health.
- **Writes** the weight, water, nutrition, and workouts you log, so the rest of your Health ecosystem stays in sync.

Health data is read and written only on your device, for the purpose of showing you your own statistics. **It is never used for advertising or marketing, never sold, and never disclosed to any third party.** You can revoke access at any time in the Health app under Sources, or in iOS Settings under Privacy & Security → Health.

---

## Optional network features

The app makes no network requests at all unless you use one of the following:

### AI food logging (Google Gemini)

If — and only if — you supply your own Google Gemini API key in Settings, describing a meal, photographing a plate, or pasting a recipe link sends that text, image, or link to Google's Gemini API to be turned into a nutrition estimate.

- Requests go directly from your device to Google, using **your** key. They do not pass through any server of ours, and we never see the contents.
- Google's handling of that data is governed by the [Google APIs Terms of Service](https://developers.google.com/terms) and the [Google Privacy Policy](https://policies.google.com/privacy), under the terms attached to your own API key.
- If you never add a key, this feature is inert and nothing is ever sent.

### Barcode lookup (Open Food Facts)

Scanning a barcode sends the numeric barcode — and nothing else — to the [Open Food Facts](https://world.openfoodfacts.org/) public database to retrieve nutrition information for that product. No personal information, device identifier, or account is attached to the request.

### Training plan import (TrainingPeaks)

If you connect a TrainingPeaks calendar in athlete mode, Steady fetches that URL over HTTPS to read your planned sessions.

- The link is the private iCalendar feed **you** generate in TrainingPeaks (Account Settings → Calendar Sync). It is stored on your device and sent only to TrainingPeaks, as the address of the request.
- The request is a plain read. **Nothing you log in Steady is ever uploaded to TrainingPeaks**, and there is no account linking, no OAuth, and no token held by us.
- Steady refreshes at most once an hour while you're using it, plus whenever you tap Sync.
- Revoking access is entirely in your hands: disconnect it in Steady, or regenerate the link in TrainingPeaks so the old one stops working.
- You can skip the network path entirely by importing a downloaded `.ics` file instead.

### Weather (Apple WeatherKit)

In athlete mode, if you leave weather-aware fueling on, Steady looks up the current temperature and humidity so your fluid and sodium targets match the conditions you're actually training in.

- The lookup goes to **Apple's** WeatherKit using a coarse (kilometre-accuracy) coordinate. Apple's handling of it is governed by the [Apple Privacy Policy](https://www.apple.com/legal/privacy/).
- Your location is used for that request and nothing else. It is **not stored** by the app, not attached to anything you log, and never sent to us or to any other party.
- Steady never asks for location in the background, and never asks at all until you switch weather on.
- Turn it off and you can type the temperature and humidity yourself — the sweat and hydration maths is identical.

---

## Cycle tracking

If you turn cycle tracking on, everything it records — the dates, flow, symptoms, and notes — is held to a stricter standard than the rest of the app:

- It is stored **only in the on-device container**. It is never transmitted anywhere, by any feature, for any reason.
- It is **not written to Apple Health**, even when Health sync is switched on.
- It is **never included** in anything sent to Google Gemini for a nutrition estimate, and never appears in a day summary sent off-device.
- It is **locked behind Face ID** (with your backup PIN as the fallback), alongside your progress photos, and re-locks every time the app leaves the foreground. Locked means locked: the dashboard card shows nothing but the word "Locked" until you unlock it.
- You can switch tracking off at any time in Settings, and erase every logged cycle permanently with one action.

Steady only offers cycle tracking when your profile makes it relevant, and asks rather than assumes when your profile says "prefer not to say".

---

## Permissions the app asks for, and why

| Permission | Why |
| --- | --- |
| Apple Health | Read steps, sleep, and weigh-ins; write your logged weight, water, nutrition, and workouts |
| Camera | Progress photos, food photos for AI estimates, and barcode scanning |
| Microphone & Speech Recognition | Dictating a meal description so it can be turned into text for an AI estimate |
| Face ID | Unlocking your private progress photos and, if you use it, your cycle log |
| Photos (add only) | Saving a progress photo to your library when you choose to export one |
| Calendar (write only) | Adding your planned workouts to your calendar as repeating events |
| Location (while using the app) | Looking up local temperature and humidity for athlete-mode hydration targets. Never in the background, never stored |
| Notifications | Local reminders you schedule yourself; no push notifications are sent from any server |

Every one of these is optional. Denying any of them disables that feature and nothing else.

---

## Exports and backups

You can export your data as a file from within the app. When you do, iOS hands you the share sheet and **you** choose where it goes — Files, AirDrop, email, or anywhere else. Once the file leaves the app, it is governed by whatever service you sent it to, not by this policy.

---

## Children

Steady is not directed to children under 13, and we do not knowingly collect information from them. Since the app collects nothing at all, there is nothing held about any user of any age.

---

## Changes to this policy

If this policy changes, the revised version will be posted at this URL with an updated effective date. Because the app collects no data, changes will generally reflect new optional features rather than new data practices.

---

## Contact

Questions about this policy or about the app:

**hunter.baisden@gmail.com**

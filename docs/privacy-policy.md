---
title: Privacy Policy
---

# Privacy Policy — Steady

**Effective 3 August 2026**

Steady ("the app") is a personal health and fitness tracker for iPhone. It is built to be local-first: your data lives on your device, and there is no Steady account, server, or backend to sign in to.

---

## The short version

- **We do not collect your data.** There is no Steady server. Nothing you log is transmitted to the developer.
- **No accounts, no analytics, no advertising, no tracking**, and no third-party analytics or ad SDKs are embedded in the app.
- Two optional features talk to outside services, and **only when you use them** — see [Optional network features](#optional-network-features).
- Your Health data is never used for advertising and is never sold or shared.

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

---

## Permissions the app asks for, and why

| Permission | Why |
| --- | --- |
| Apple Health | Read steps, sleep, and weigh-ins; write your logged weight, water, nutrition, and workouts |
| Camera | Progress photos, food photos for AI estimates, and barcode scanning |
| Microphone & Speech Recognition | Dictating a meal description so it can be turned into text for an AI estimate |
| Face ID | Unlocking your private progress photos |
| Photos (add only) | Saving a progress photo to your library when you choose to export one |
| Calendar (write only) | Adding your planned workouts to your calendar as repeating events |
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

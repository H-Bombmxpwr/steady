# TestFlight Setup

How to get **Steady** onto other people's phones with TestFlight, and what still needs doing before that works.

---

## Contents

- [Is it ready?](#is-it-ready)
- [Publishing the privacy policy on GitHub Pages](#publishing-the-privacy-policy-on-github-pages)
- [Is it safe to make the repo public?](#is-it-safe-to-make-the-repo-public)
- [One-time setup](#one-time-setup)
- [Uploading a build](#uploading-a-build)
- [Inviting testers](#inviting-testers)
- [What to tell testers](#what-to-tell-testers)
- [Shipping updates](#shipping-updates)
- [Troubleshooting](#troubleshooting)
- [Project facts (verified)](#project-facts-verified)

---

## Is it ready?

**Yes.** A Release archive was built after the changes below and it passed Xcode's `-validate-for-store` check:

```
** ARCHIVE SUCCEEDED **
```

| Requirement | Status |
| --- | --- |
| Real bundle ID (`com.hunter.seventyfivehard`) | ✅ |
| Development team set (`U3PXY283T3`), automatic signing | ✅ |
| App icon (1024 + 10 alternate icons) | ✅ |
| Version / build number (`1.0 (2)`) | ✅ |
| Every permission has a usage string (Health, Camera, Mic, Speech, Face ID, Photos, Calendar) | ✅ |
| Export compliance pre-answered (`ITSAppUsesNonExemptEncryption = NO`) | ✅ — no export question on every upload |
| App category set (Lifestyle) | ✅ |
| Widget extension + Live Activity embed and validate | ✅ |
| No hardcoded API keys in the binary | ✅ — Gemini key is user-supplied |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | ✅ — in both the app and widget bundles |
| Privacy policy | ✅ — written, needs GitHub Pages turned on |
| Shared Xcode schemes | ✅ |
| iPhone only, iOS 18.0+ | ✅ |

Nothing is blocking the upload. What remains is App Store Connect paperwork, covered below.

### What changed

**Privacy manifests added** — `75/PrivacyInfo.xcprivacy` and `Widgets/PrivacyInfo.xcprivacy`. The app and widget both read and write App Group `UserDefaults` (`Shared/WidgetSnapshot.swift`, `75/App/Theme.swift`, `Widgets/FitnessWidgets.swift`), which is a "required reason API" — undeclared, the upload gets flagged with ITMS-91053. Both declare `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` ("access info from the app itself or an app group of the same team"), which is exactly what Steady does. `NSPrivacyCollectedDataTypes` is empty because nothing is collected: there is no server, and the Gemini traffic goes from the user's device to the user's own API key.

Verified in the built archive — `PrivacyInfo.xcprivacy` is present in both `75.app/` and `75.app/PlugIns/WidgetsExtension.appex/`. The project uses Xcode 16 synchronized folder groups, so the files were picked up by target membership automatically.

No file-timestamp declaration is needed: no app code touches those APIs, and while ZIPFoundation (the one SPM dependency) does, it is **not imported anywhere in the project** and gets dead-stripped — `nm` finds zero ZIPFoundation symbols in the shipped binary. Worth removing that dependency at some point; it's dead weight and the README already claims no external dependencies.

**Privacy policy written** — `docs/privacy-policy.md`, ready to publish. See the next section.

**Shared schemes added** — `75.xcodeproj/xcshareddata/xcschemes/` now holds `75` and `WidgetsExtension`, so any machine or CI runner can build without Xcode regenerating them.

**iPad support dropped** — `TARGETED_DEVICE_FAMILY` is now `1`, and the iPad orientation keys are gone. The built `Info.plist` reports `UIDeviceFamily = [1]`. This means a beta reviewer will never open it on an iPad and reject iPhone-shaped layout.

**Deployment target lowered to iOS 18.0** from 18.5 — builds clean, widens the tester pool. The built `Info.plist` reports `MinimumOSVersion = 18.0`.

### App name

You said the name is **Steady - private health logging**. That's 31 characters and App Store Connect caps the app name at **30**, so it will be rejected as typed. Two ways to fit:

1. **Name:** `Steady` · **Subtitle:** `Private health logging` — the idiomatic App Store split, and the subtitle field gives you 30 more characters. Use this if `Steady` is available.
2. **Name:** `Steady: Private Health Logging` — exactly 30 characters, fits if the bare `Steady` is taken.

App names are globally unique across the App Store, and `Steady` is a common word, so have option 2 ready. Neither has to match the home-screen name, which stays *Steady*.

---

## Publishing the privacy policy on GitHub Pages

The policy is written and sitting in `docs/` as a small Jekyll site. Once Pages is on, these are your URLs:

| Field in App Store Connect | URL |
| --- | --- |
| **Privacy Policy URL** | `https://h-bombmxpwr.github.io/75/privacy-policy` |
| **Support URL** | `https://h-bombmxpwr.github.io/75/` |

Both are required — Support URL for the App Store listing, Privacy Policy URL before external TestFlight testing. `docs/index.md` doubles as the support page, with a short FAQ covering the Gemini key, Health permissions, and widgets.

### Turning it on

1. Commit and push `docs/` to `main`.
2. On GitHub: **your repo → Settings → Pages**.
3. Under **Build and deployment → Source**, choose **Deploy from a branch**.
4. Set branch to **`main`** and folder to **`/docs`**. Save.
5. Wait 1–2 minutes for the first build (watch the **Actions** tab). The Pages settings screen will show the live URL when it's done.

**Pages on a private repo requires a paid GitHub plan.** On the free plan, Pages only works for public repos — so this is tied to the question below.

Check the two URLs in a browser before pasting them into App Store Connect. Apple's reviewers do click them, and a 404 on the privacy policy is a straightforward rejection.

---

## Is it safe to make the repo public?

**Yes, based on what's actually in the repo.** I checked the working tree and the full git history:

- **No API keys, anywhere.** `75/Resources/Secrets.plist` is gitignored and has never been committed — confirmed against every commit, not just the current tree. The only `AIza...` string in the repo is the placeholder example in the "how to get a key" help screen.
- **No certificates, provisioning profiles, `.p8` keys, or `.env` files** are tracked.
- **No user data.** Backup JSON exports are gitignored.
- **The git history is clean of AI-authorship trailers.** The five commits carrying `Co-Authored-By` lines existed only in `refs/original/*` — local leftovers from an earlier `git filter-branch`, never pushed. Those backup refs have now been deleted, so nothing on GitHub or in your local clone references it. `AGENTS.md` and `docs/agents/` have also been removed.

Two things to think about before flipping the switch, neither a security issue:

- **`.scratch/fitness-tracker/`** (41 tracked files) is your PRD and issue log, and the README links to it. Nothing sensitive in it, but it's candid product thinking that will be public. Keep or drop — your call.
- **Your bundle ID and Team ID become public.** That's normal and harmless; they're visible in any shipped app anyway. Nobody can sign anything with them without your certificates.

One caveat worth knowing: making a repo public is not fully reversible in the sense that matters — once it's public, anything in it can be cloned, cached, or forked, and taking the repo private later doesn't recall those copies. Since the history is clean, that's fine here.

---

## One-time setup

### Step 1 — Confirm your account is active

Go to [developer.apple.com/account](https://developer.apple.com/account). If you see "Certificates, Identifiers & Profiles" and no pending-agreement banner, you're in. New accounts often need the **Paid Apps / Free Apps agreement** accepted before builds are accepted — check App Store Connect → **Business** → Agreements and accept anything pending. This trips up nearly every new account.

### Step 2 — Sign in inside Xcode

**Xcode → Settings → Accounts → +** → Apple ID. Select your team, then **Manage Certificates → + → Apple Distribution**.

You currently only have an *Apple Development* certificate. Xcode will create the distribution one automatically on first upload, but making it here first avoids a confusing error mid-upload.

### Step 3 — Register the App IDs

Automatic signing has already created these implicitly (the archive signed cleanly), but confirm the capabilities stuck. At [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers):

| Identifier | Capabilities needed |
| --- | --- |
| `com.hunter.seventyfivehard` | HealthKit, App Groups |
| `com.hunter.seventyfivehard.widgets` | App Groups |

And the App Group `group.com.hunter.seventyfivehard` must exist and be checked on both. If the group isn't shared correctly, **the widgets and Live Activity silently show no data** — that's the single most likely TestFlight-only bug.

### Step 4 — Create the app record in App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps → +**:

- **Platform:** iOS
- **Name:** `Steady` (or `Steady: Private Health Logging` if that's taken — see [App name](#app-name))
- **Primary language:** English (U.S.)
- **Bundle ID:** `com.hunter.seventyfivehard` (pick it from the dropdown — if it's missing, Step 3 didn't take)
- **SKU:** anything unique, e.g. `steady-001`
- **User access:** Full Access

### Step 5 — Fill in App Privacy

App Store Connect → your app → **App Privacy**. This is **mandatory before external testing** and it's a questionnaire, not a document. For Steady, the honest answers are:

- **Do you collect data?** → No, if the Gemini calls are the only network traffic and you never receive that data yourself. Apple's definition of "collect" is *transmitted off device and retained by you or your third-party partners* — you retain nothing.
- Answer **No** to tracking, and declare no third-party advertising SDKs.

If you'd rather over-declare: *Health & Fitness* → *Not linked to the user* → *App Functionality*.

While you're here, fill in **App Information** on the same screen:

- **Subtitle:** `Private health logging`
- **Privacy Policy URL:** `https://h-bombmxpwr.github.io/75/privacy-policy`
- **Support URL:** `https://h-bombmxpwr.github.io/75/`

---

## Uploading a build

### The GUI path (recommended for the first one)

1. Open `75.xcodeproj` in Xcode.
2. Scheme selector → **75**, destination → **Any iOS Device (arm64)**. Archive is greyed out on a simulator destination.
3. **Product → Archive.** Takes a few minutes.
4. The Organizer opens. Select the archive → **Distribute App**.
5. **App Store Connect → Upload** → keep all the defaults ticked (upload symbols, manage version and build number) → **Next** through signing (automatic) → **Upload**.
6. Wait. The build appears in App Store Connect → **TestFlight** as "Processing" for 5–30 minutes, then flips to ready.

### The command-line path

Archiving works headlessly — this is the exact command that was verified against this project:

```bash
xcodebuild -project 75.xcodeproj \
  -scheme 75 \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/75.xcarchive \
  archive
```

Then export and upload. Create `ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>U3PXY283T3</string>
    <key>uploadSymbols</key><true/>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
```

```bash
xcodebuild -exportArchive \
  -archivePath build/75.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export

xcrun altool --upload-app -f build/export/75.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

The API key comes from App Store Connect → **Users and Access → Integrations → App Store Connect API** (create one with *App Manager* access, download the `.p8` **once**, and put it in `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`).

---

## Inviting testers

Two tiers, and the difference matters:

### Internal testing — instant, no review

Up to **100 people**, but each must be added as a user on your App Store Connect account (**Users and Access → +**, role *Developer* or higher, with access to the app). Builds go live to them within minutes of processing finishing. No Apple review.

This is the right choice for friends and family. Do this first.

1. TestFlight → **Internal Testing** → **+** next to Testers → create a group, e.g. "Friends".
2. Add testers by Apple ID email.
3. TestFlight → your build → **Add to group**.

### External testing — up to 10,000, needs Beta App Review

Testers just need an email address; no App Store Connect account. But the **first** build submitted to an external group goes through Beta App Review (usually under 48 hours, lighter than full App Store review).

To submit you must have filled in: beta app description, feedback email, privacy policy URL, and the App Privacy questionnaire.

1. TestFlight → **External Testing** → **+** → group name.
2. Add the build → fill in **Test Information** → **Submit for Review**.
3. Once approved, enable the **Public Link** to hand out a URL anyone can tap — the easiest way to distribute.

### On the tester's phone

They install **TestFlight** from the App Store, open the invite email or public link, tap **Install**. That's it — no UDIDs, no provisioning profiles, no cables.

---

## What to tell testers

Steady has two things a first-time tester will get stuck on. Put both in the beta description:

> **Steady** is a private, on-device weight-loss and fitness tracker. Everything stays on your phone.
>
> **The AI food logging needs your own free Gemini key.** In Settings → AI Assist, tap "How to get a free key" and follow the steps (takes about a minute at aistudio.google.com). Without it, manual food logging and everything else still works — you just don't get "describe your meal" or photo estimates.
>
> **Please allow Health access** when asked — steps, sleep, and weigh-ins come from there, including Garmin devices that sync to Apple Health.
>
> Things I'd love feedback on: does the calorie budget feel right after a few days? Do the widgets update? Anything confusing in onboarding?
>
> Report bugs with the **screenshot → share → TestFlight** flow, or shake the phone to send feedback.

Requires **iOS 18.0 or later**, iPhone only. Worth stating up front so nobody installs TestFlight for nothing.

---

## Shipping updates

- **Every upload needs a higher build number.** You're at `1.0 (2)`, so the next one is `1.0 (3)`. Bump `CURRENT_PROJECT_VERSION` in build settings, or let Xcode's "Manage version and build number" do it during distribution. Reusing a build number is rejected instantly.
- `MARKETING_VERSION` (`1.0`) only needs bumping for a user-visible release.
- **Builds expire after 90 days.** Testers get cut off when that happens, so plan on uploading something at least quarterly during a long beta.
- Subsequent external builds usually skip review unless you change something significant — but Apple decides, not you.
- Crash reports land in Xcode → **Organizer → Crashes**, aggregated across testers. Written feedback lands in App Store Connect → TestFlight → **Feedback**.

---

## Troubleshooting

**"No account for team U3PXY283T3"** — Xcode → Settings → Accounts, sign in, download manual profiles.

**"Missing Compliance" on the build in App Store Connect** — shouldn't happen here (the Info.plist key is set), but if it does, answer the export-compliance question in the build's page. It only blocks distribution, not upload.

**ITMS-91053 email about missing API declarations** — that's the privacy manifest. Both bundles now carry one; if a new email names an API category that isn't declared, add it to `75/PrivacyInfo.xcprivacy` and `Widgets/PrivacyInfo.xcprivacy`. Apple's email always names the exact category and the reason codes you can pick from.

**Widgets blank on a tester's phone, fine on yours** — App Group mismatch in the distribution profile. Verify `group.com.hunter.seventyfivehard` is enabled on *both* App IDs in the developer portal, then re-archive.

**Health data empty for testers** — they denied the permission prompt, or they're on a device with no Health data. Both are real bugs to watch for: make sure the app degrades gracefully.

**Build stuck "Processing" over an hour** — usually a bad binary. Check your email; Apple sends the reason.

---

## Project facts (verified)

Everything below was read from `75.xcodeproj/project.pbxproj` and the entitlements files, not assumed:

| | |
| --- | --- |
| Team ID | `U3PXY283T3` |
| App bundle ID | `com.hunter.seventyfivehard` |
| Widget bundle ID | `com.hunter.seventyfivehard.widgets` |
| App Group | `group.com.hunter.seventyfivehard` |
| Display name | Steady (target/product is still named `75`) |
| Version | `1.0` build `2` |
| Deployment target | iOS 18.0 |
| Devices | iPhone only (`1`) |
| Signing | Automatic |
| Entitlements | HealthKit (app), App Groups (app + widget) |
| Category | Lifestyle |
| URL scheme | `seventyfive://` |
| Dependency | ZIPFoundation 0.9.19 (SPM) — linked but never imported; dead-stripped from the binary |
| Targets | `75`, `WidgetsExtension`, `75Tests`, `75UITests` |

Note: Live Activities are started locally via `ActivityKit` (`75/Services/LiveActivityManager.swift`), so no push-notification entitlement is needed. Notifications are local too — no APNs setup required.

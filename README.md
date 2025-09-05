# 75 Hard – Personal Tracker (SwiftUI + SwiftData)

A private, local-only iOS app to track the 75 Hard challenge with:
- **Face ID lock** on launch/resume
- **Diet name + description** (locked after setup)
- **Dashboard** with today’s checklist, live indicators, and cumulative stats (indoor/outdoor minutes, pages, water in oz & gal)
- **Calendar view** with scrolling days
- **Manual workouts** + **presets**
- **One alcohol use per month** enforcement
- **Progress photos** (camera or library), gallery with full-screen viewer and compare mode
- **Weight logging** (starting weight and daily weight; net change shown)
- **Configurable water step** (e.g., 48 oz bottle)
- **Local storage** only (SwiftData + Documents)
- **Backup export** as a single JSON (embedded photos)

## Tech
- iOS 17+, Swift 5.9
- SwiftUI, SwiftData
- No external dependencies

## Getting Started
1. **Clone**
   ```bash
   git clone https://github.com/<you>/SeventyFiveHard.git
   cd SeventyFiveHard
    ```

2. **Open** `SeventyFiveHard.xcodeproj` in Xcode 15+.
3. **Capabilities / Privacy**
   In **Targets → Info** (or the app’s Info plist):

   * `NSCameraUsageDescription` = “To capture progress photos”
   * `NSPhotoLibraryUsageDescription` = “To import progress photos”
   * `NSPhotoLibraryAddUsageDescription` = “To save exports if needed”
4. **Run on device**
   Use your Apple ID (free provisioning = 7-day installs; paid Dev Program ≈ 12 months).

## App Flow

* **Onboarding**: choose start date (no future), diet name + description, optional starting weight, pre-seeds 75 Day entries.
* **Dashboard**: shows today’s date, day N/75, remaining days, live checklist, and totals.
* **Day Detail**: steppers for workouts/water/pages, outdoor toggles, weight field, diet toggle, alcohol button, photo strip.
* **Photos**: grid with date & day labels, full-screen viewer, two-photo compare (swipe), save-to-library from viewer.
* **Settings**: water step size, diet info read-only, Face ID note, JSON backup export, erase-all.

## Backup / Export

* **Settings → Export Backup (JSON)**
  Exports a single `*.75hard-backup.json` into your Documents; a system document picker lets you save to Files/iCloud/Drive.
* JSON contains:

  * Challenge metadata, all days, presets
  * Photos embedded as Base64
* (Optional) Import can be added later by reading the JSON and rebuilding SwiftData + writing photos back to `Documents/Photos`.

## Build Expiry (sideloading)

* Free Apple ID: \~7 days
* Paid Developer: typically up to 12 months
* Data lives in app container and persists across rebuilds if the bundle identifier stays the same and you do not uninstall the app.

## Project Structure (high level)

```
SeventyFiveHard/
  ├─ Models/ (ChallengeState, DayEntry, WorkoutPreset, PhotoEntry)
  ├─ Persistence.swift
  ├─ Views/
  │   ├─ AuthGateView (Face ID)
  │   ├─ RootRouterView / MainTabView
  │   ├─ OnboardingView
  │   ├─ DashboardView (+ components)
  │   ├─ CalendarScreen
  │   ├─ DayDetailView (+ CameraCaptureView)
  │   ├─ PhotosGalleryView (+ Compare, Fullscreen viewer)
  │   ├─ PresetsView
  │   └─ SettingsView
  ├─ Services/
  │   └─ BackupService.swift
  └─ Utilities/
      └─ File helpers (documentsURL, photosDir, ensureDay)
```




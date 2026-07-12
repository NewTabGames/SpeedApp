# SpeedApp (MPH Tracker)

A GPS speedometer, ride recorder, and turn-by-turn navigator built for electric scooters. No paywalls, no subscriptions — every feature is free.

**Version 2.0**

## Features

### Speed
- Large, live MPH (or KM/H) readout with animated digits
- Max speed tracking with reset
- GPS signal quality indicator (locked / weak / acquiring)
- Optional speed limit alert with vibration + on-screen warning

### Record
- Log a full ride with a live speed graph
- Tracks duration, current/max/average speed, and total distance
- Drag across the graph to inspect exact speed at any moment
- Keeps the screen awake while recording (optional)

### Map
- Search any destination (address or place name), biased to your area
- Real road routing with distance and ETA
- **Spoken turn-by-turn directions** as you ride
- Live position tracking with mute toggle and adjustable voice speed

### History
- Every saved ride with a route map showing exactly where you went
- Start/end pins and your GPS trail drawn on the map
- Full-screen interactive speed graph per ride
- **Export any ride's graph as a PNG image** to share or save

### Settings
- Units: MPH or KM/H (applies everywhere, including the graph and navigation)
- Theme: System / Light / Dark
- Accent color: 7 options
- Map style: Standard / Satellite / Hybrid
- Graph line style: smooth curve or straight lines
- Speed smoothing: Responsive / Balanced / Smooth
- GPS mode: High Accuracy or Battery Saver
- Voice speed for navigation prompts
- Haptic feedback toggle
- Keep screen awake toggle
- Custom speed limit alert (type in any value)
- Clear all recordings

## Project structure

| File | Purpose |
|---|---|
| `SpeedAppApp.swift` | App entry point, wires up all stores and applies settings |
| `ContentView.swift` | Tab bar + Speed, Record, History, Settings, and ride detail views |
| `MapTabView.swift` | Map tab: search, route preview, turn-by-turn banner |
| `NavigationStore.swift` | Destination search, route calculation, spoken guidance |
| `LocationManager.swift` | GPS speed reading, smoothing, distance tracking, recording |
| `RunStore.swift` | Saving and loading ride recordings on-device |
| `SettingsStore.swift` | All user preferences, persisted via UserDefaults |
| `ChartHelpers.swift` | Interactive drag-to-inspect speed chart, share sheet helper |
| `GraphDetailView.swift` | Full-screen graph view with PNG export |

All data stays on your device. Nothing is uploaded anywhere.

## Building the IPA (no Mac required)

This repo builds itself using GitHub Actions on a macOS runner.

1. Push this folder to a GitHub repo (public or private both work).
2. Go to the **Actions** tab. The `Build IPA` workflow runs automatically on push to `main` (or click **Run workflow** to trigger manually).
3. Wait for the green checkmark (3–8 minutes).
4. Open the completed run, scroll to **Artifacts**, download `SpeedApp-ipa`.
5. Unzip it to get `SpeedApp.ipa`.

## Installing on your phone

1. Open **Sideloadly**.
2. Drag `SpeedApp.ipa` in, connect your iPhone, sign in with your Apple ID when prompted.
3. Sideloadly signs and installs the app.
4. On your phone: **Settings > General > VPN & Device Management** → trust your developer profile the first time you open the app.
5. Free Apple ID signing expires after 7 days — you'll need to re-sideload periodically. A paid Apple Developer account ($99/year) signs for a full year instead.

## Customizing

**App name:** change `CFBundleDisplayName` in `project.yml`.

**App icon:** replace `Sources/SpeedApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with your own 1024×1024 PNG (no transparency, no rounded corners — iOS adds those).

## Local building (if you have a Mac)

```bash
brew install xcodegen
xcodegen generate
open SpeedApp.xcodeproj
```
Then hit Run in Xcode with your phone plugged in — Xcode signs it with your free Apple ID over USB, no Sideloadly needed.

## Notes & limitations

- **Location permission is required** for any speed reading. The app prompts on first launch.
- **Speed accuracy depends on GPS quality.** Smoothing is applied to reduce jitter; adjust it in Settings if the number feels too laggy or too jumpy. iPhone GPS updates roughly once per second, which is the hard floor on responsiveness.
- **Navigation uses Apple's driving routes.** MapKit has no scooter-specific routing mode, so it may occasionally route you onto a road that isn't ideal for a scooter. Use judgment.
- **Navigation does not reroute if you go off-path.** It keeps guiding along the original route rather than recalculating like Apple Maps does.
- **Short recordings may not draw a route.** A ride needs at least a couple of GPS points before the map has anything to show.

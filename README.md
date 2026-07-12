# SpeedApp (MPH Tracker)

A GPS speedometer, ride recorder, and turn-by-turn navigator for electric scooters. No paywalls, no subscriptions.

**Version 2.0** — Requires iOS 18 or newer.

## Features

### Speed
- Live MPH/KM-H readout, smoothly interpolated between GPS fixes
- Max speed tracking with reset
- GPS signal quality indicator
- Optional speed limit alert (set any value) with vibration

### Record
- Log a ride with a live speed graph
- Tracks duration, current/max/average speed, and distance
- Drag across the graph to see exact speed at any point
- Optionally keeps the screen awake

### Map
- Search a destination, tap a place on the map, or long-press to drop a pin
- Real road routing with distance and ETA
- Spoken turn-by-turn directions with adjustable voice speed and a mute toggle

### History
- Every saved ride with a route map showing where you went
- Full-screen interactive speed graph
- Export any ride's graph as a PNG
- Confirmation prompt before clearing (can be turned off)

### Settings
- Units: MPH or KM/H
- Theme: System / Light / Dark
- Accent color (7 options)
- Map style: Standard / Satellite / Hybrid
- Graph line style: smooth or straight
- Speed smoothing: Responsive / Balanced / Smooth
- GPS mode: High Accuracy or Battery Saver
- Navigation voice speed
- Haptic feedback toggle
- Keep screen awake toggle
- Confirm before clearing toggle

## Project structure

| File | Purpose |
|---|---|
| `SpeedAppApp.swift` | App entry point, wires up stores and applies settings |
| `ContentView.swift` | Tab bar + Speed, Record, History, Settings, ride detail |
| `MapTabView.swift` | Map tab: search, route preview, turn-by-turn banner |
| `NavigationStore.swift` | Destination search, routing, spoken guidance |
| `LocationManager.swift` | GPS speed, smoothing, distance, recording |
| `RunStore.swift` | Saving/loading recordings |
| `SettingsStore.swift` | User preferences |
| `ChartHelpers.swift` | Interactive chart, sparkline, downsampling, share sheet |
| `GraphDetailView.swift` | Full-screen graph with PNG export |

Recordings are stored as JSON in the app's Documents directory. All data stays on your device.

## Building the IPA (no Mac required)

1. Push this folder to a GitHub repo.
2. Go to the **Actions** tab. The `Build IPA` workflow runs on push to `main`, or trigger it manually with **Run workflow**.
3. Wait for the green checkmark (3–8 minutes).
4. Open the run, scroll to **Artifacts**, download `SpeedApp-ipa`.
5. Unzip to get `SpeedApp.ipa`.

## Installing

1. Open **Sideloadly**, drag in `SpeedApp.ipa`, connect your iPhone, sign in with your Apple ID.
2. On your phone: **Settings > General > VPN & Device Management** → trust your developer profile.
3. Free Apple ID signing expires after 7 days and needs re-sideloading. A paid Apple Developer account ($99/year) signs for a year.

## Customizing

- **App name:** `CFBundleDisplayName` in `project.yml`
- **App icon:** replace `Sources/SpeedApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with a 1024×1024 PNG (no transparency, no rounded corners)

## Building locally (with a Mac)

```bash
brew install xcodegen
xcodegen generate
open SpeedApp.xcodeproj
```

## Limitations

- Location permission is required for any speed reading.
- iPhone GPS updates about once per second. The displayed number is interpolated between fixes to look smooth, but that's the underlying data rate.
- Navigation uses Apple's driving routes. There's no scooter-specific routing in MapKit, so it may route onto roads that aren't ideal for a scooter.
- Navigation does not reroute if you go off-path. It keeps guiding along the original route.
- Graphs are downsampled for display on long rides. Drag-to-inspect still reads full-resolution data.

## Changelog

**2.0**
- Map tab with destination search, tap/long-press to set a destination, and spoken turn-by-turn
- Distance tracking and route maps for saved rides
- Interactive graphs with drag-to-inspect and PNG export
- Settings: theme, map style, GPS mode, graph style, voice speed, haptics, confirm-before-clear
- Custom speed limit alert
- Smooth speed readout between GPS fixes
- Recordings moved from UserDefaults to file storage; graphs downsampled for performance
- Minimum iOS raised to 18

**1.0**
- Live speed, 0–60/0–100 timers, run history

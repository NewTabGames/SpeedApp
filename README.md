# Epstein's GPS

A GPS speedometer, ride recorder, and turn-by-turn navigator for electric scooters. No paywalls, no subscriptions.

**Version 2.1** — Requires iOS 18 or newer.

## Features

### Speed
- Live MPH/KM-H readout, smoothly interpolated between GPS fixes
- Max speed tracking with reset
- GPS signal quality indicator
- Optional speed limit alert (set any value) with vibration

### Record
- Log a ride with a live speed graph
- Tracks duration, current/max/average speed, distance, and elevation gain/loss
- Pause and resume mid-ride
- Optional auto-pause when you stop moving
- Optional battery logging (start/end percentage)
- Drag across the graph to see exact speed at any point
- Graph axes show elapsed time (m:ss) and speed
- Optionally keeps the screen awake

### Map
- Search a destination, tap a place on the map, or long-press to drop a pin
- Real road routing with distance and ETA
- Spoken turn-by-turn directions — a heads-up before each turn, then a final call at the turn
- Automatic rerouting if you leave the route
- Adjustable voice speed and a mute toggle
- Music (Spotify, podcasts) only dips while a direction is being spoken, then returns to full volume

### History
Split into two sections:

**Rides**
- Every saved ride with a route map showing where you went
- Rename any ride; sort by date, distance, top speed, or duration; search by name
- Trip replay — watch a marker retrace your route with the speed graph scrubbing in sync
- Full-screen interactive speed graph — dragging shows speed, elapsed time, and time of day
- Export the route map as a PNG, with your path, start/end markers, and ride stats
- Export the speed graph as a PNG
- Export a single ride's raw GPS data as CSV
- Confirmation prompt before clearing (can be turned off)

**Lifetime**
- Total rides, distance, time, top speed, average speed, longest ride, total climb
- Estimated range per charge, once you've logged battery on a few rides

**CSV export** — two formats, both from the share menus:

| Export | Where | One row per | Columns |
|---|---|---|---|
| Rides summary | History → ⋯ menu | Ride | date, name, duration, distance, max/avg speed, elevation gain/loss, battery start/end/used, sample count |
| Ride data | Ride Detail → share menu | GPS reading | elapsed seconds, timestamp, speed, latitude, longitude, altitude |

Both respect your unit setting (mph/mi or km/h/km), and column headers say which.

### Settings
- Units: MPH or KM/H
- Theme: System / Light / Dark
- Accent color (7 options)
- Map style: Standard / Satellite / Hybrid
- Graph line style: smooth or straight
- Speed smoothing: Responsive / Balanced / Smooth
- GPS mode: High Accuracy or Battery Saver
- Navigation voice speed
- Auto-pause when stopped
- Battery tracking
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
| `MapExporter.swift` | Renders a ride's route map to a shareable PNG |
| `TripReplayView.swift` | Animated playback of a saved ride |
| `CSVExporter.swift` | Ride summary and raw sample CSV export |
| `AboutView.swift` | In-app "What This App Does" feature list |

Recordings are stored as JSON in the app's Documents directory. All data stays on your device.

## Keeping docs in sync

There are two places that describe what the app does: this README, and `AboutView.swift`
(the "What This App Does" screen in Settings). **When a feature changes, update both.**
A stale in-app feature list is worse than none.

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

- **App name:** `CFBundleDisplayName` in `project.yml` (currently "Epstein's GPS")
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
- Rerouting requires a data connection. Without one, guidance continues along the original route.
- Graphs are downsampled for display on long rides. Drag-to-inspect still reads full-resolution data.
- Exporting a route map downloads map tiles, so it needs a network connection and takes a second or two.
- GPS altitude is noisier than horizontal position. Elevation numbers only count changes above ~1.5 m and should be treated as approximate.
- Battery range estimates need at least 3 logged rides and get better with more. They assume your riding is roughly consistent — a hilly ride will drain faster than the estimate suggests.
- Pausing stops collecting data entirely. If you move while paused, the route map draws a straight line across the gap, and that distance isn't counted.

## Changelog

**2.1**
- Fixed music staying quiet the whole time the app was open — it now only dips while speaking a direction
- Automatic rerouting when you leave the route
- Turn announcements now warn you before the turn, not just at it
- "What This App Does" screen in Settings
- CSV export (rides summary and per-ride raw data)
- History split into Rides and Lifetime Totals
- Rename, sort, and search rides
- Elevation gain/loss tracking
- Pause/resume, plus optional auto-pause when stopped
- Battery tracking with range estimation
- Trip replay

**2.0**
- Map tab with destination search, tap/long-press to set a destination, and spoken turn-by-turn
- Route map export (PNG with path, markers, and stats)
- Graph axes labeled with elapsed time instead of raw seconds
- Distance tracking and route maps for saved rides
- Interactive graphs with drag-to-inspect and PNG export
- Settings: theme, map style, GPS mode, graph style, voice speed, haptics, confirm-before-clear
- Custom speed limit alert
- Smooth speed readout between GPS fixes
- Recordings moved from UserDefaults to file storage; graphs downsampled for performance
- Minimum iOS raised to 18

**1.0**
- Live speed, 0–60/0–100 timers, run history

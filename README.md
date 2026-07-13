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
- Optional auto-pause when you stop moving, with adjustable speed threshold and delay
- Keeps recording while the phone is locked or in your pocket
- Optional battery logging (start/end percentage)
- Drag across the graph to see exact speed at any point
- Graph axes show elapsed time (m:ss) and speed
- Optionally keeps the screen awake

### Map
- Search a destination, tap a place on the map, or long-press to drop a pin
- Recenter button to snap back to your location, and a lock button to keep the map following you
- Real road routing with distance and ETA
- Spoken turn-by-turn directions — a heads-up before each turn, then a final call at the turn
- Automatic rerouting if you leave the route
- Choose the navigation voice from those installed on your phone, with a preview button
- Adjustable voice speed and a mute toggle
- Music (Spotify, podcasts) only dips while a direction is being spoken, then returns to full volume

### History
Split into two sections:

**Rides**
- Every saved ride with a route map showing where you went
- Swipe a ride to rename or delete it; sort by date, distance, top speed, or duration; search by name
- Trip replay — watch a marker retrace your route with the speed graph scrubbing in sync, in real-time or sped up
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
- Accent color (12 options)
- Map style: Standard / Satellite / Hybrid
- Graph line style: smooth or straight
- Speed smoothing: Responsive / Balanced / Smooth
- GPS mode: High Accuracy or Battery Saver
- Navigation voice speed
- Auto-pause when stopped (adjustable speed threshold and delay)
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
| `RouteMap.swift` | Route map view with optional speed-based coloring and a legend |
| `VoiceCatalog.swift` | Lists the navigation voices installed on the device |
| `Haptics.swift` | Central haptic feedback helper, respects the Haptics setting |
| `SpeechText.swift` | Expands street abbreviations so directions read aloud properly |
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

- Location permission is required for any speed reading. Background recording (with the phone locked) needs "Always" permission — with "While Using" only, recording pauses when the screen locks.
- iPhone GPS updates about once per second. The displayed number is interpolated between fixes to look smooth, but that's the underlying data rate.
- Navigation uses Apple's driving routes. There's no scooter-specific routing in MapKit, so it may route onto roads that aren't ideal for a scooter.
- Rerouting requires a data connection. Without one, guidance continues along the original route.
- Graphs are downsampled for display on long rides. Drag-to-inspect still reads full-resolution data.
- Exporting a route map downloads map tiles, so it needs a network connection and takes a second or two.
- GPS altitude is noisier than horizontal position. Elevation numbers only count changes above ~1.5 m and should be treated as approximate.
- The route line is drawn from raw GPS (accurate to ~15-30 ft). On a path near a parallel road, the line can appear to follow the road — that's GPS position error, not map-snapping. Low-confidence fixes (>30 m error) are discarded to reduce this.
- Battery range estimates need at least 3 logged rides and get better with more. They assume your riding is roughly consistent — a hilly ride will drain faster than the estimate suggests.
- Pausing stops collecting data entirely. If you move while paused, the route map draws a straight line across the gap, and that distance isn't counted.

## Changelog

**2.1**
- Speed-colored routes are now much more distinct (muted-to-vivid, not just light-to-dark)
- Expanded haptic feedback across tabs, buttons, and controls, unified under one setting
- Fixed: swiping away the end-of-ride battery sheet silently discarded the ride — it now saves regardless
- Fixed: opening the Record tab directly (without visiting Speed first) never started GPS
- Fixed: speed-colored routes drew thousands of map overlays on long rides, causing stutter
- Map: recenter button and a lock-on (follow) button
- Fixed speed alert repeating while over the limit, and it now shows your chosen unit
- Centralized screen-awake handling so recording and navigation don't conflict
- Serialized ride saves to prevent an older write clobbering a newer one
- Long rides (1 hr+) now show h:mm:ss in graph detail and exported images
- Route maps can be colored by speed (pale = slow, deep = fast), toggle in Settings. Exported route images use the same speed shading.
- Accent colors expanded from 7 to 12
- Auto-pause speed threshold and delay are now adjustable in Settings
- Fixed the voice spelling out street abbreviations ("Bull Run D-R" instead of "Bull Run Drive")
- Trip replay now has a real-time (1x) speed and interpolates for smooth motion
- Choose the navigation voice, with a preview button
- Tightened GPS filtering to reduce the route drifting onto nearby roads
- Fixed navigation voice clipping the first words of a direction
- Recording continues while the phone is locked (background location)
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

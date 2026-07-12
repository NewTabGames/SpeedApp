# SpeedApp

A simple iOS speedometer app: live MPH, max speed, 0-60 / 0-100 timers, and run history. No paywalls, no map/route tracking.

## How it works

- **Speed.swift / ContentView.swift** – live speed readout using `CoreLocation`
- **LocationManager.swift** – reads GPS speed, smooths it, detects 0-60 and 0-100 runs
- **RunStore.swift** – saves completed runs locally on-device (UserDefaults/JSON, no server)

## Building the IPA (no Mac required)

This repo builds itself using GitHub Actions on a macOS runner.

1. Push this whole folder to a new GitHub repo (public or private both work).
2. Go to the **Actions** tab in your repo. The `Build IPA` workflow runs automatically on push to `main` (or click **Run workflow** to trigger manually).
3. Wait for the green checkmark (3–8 minutes).
4. Open the completed run, scroll to **Artifacts**, download `SpeedApp-ipa` (a zip containing `SpeedApp.ipa`).
5. Unzip it to get `SpeedApp.ipa`.

## Installing on your phone

1. Open **Sideloadly**.
2. Drag `SpeedApp.ipa` in, connect your iPhone, sign in with your Apple ID when prompted.
3. Sideloadly signs and installs the app.
4. On your phone: **Settings > General > VPN & Device Management** → trust your developer profile the first time you open the app.
5. Free Apple ID signing expires after 7 days — you'll need to re-sideload periodically. A paid Apple Developer account ($99/year) signs for a full year instead, if this becomes annoying.

## Local building (if you ever get Mac access)

```bash
brew install xcodegen
xcodegen generate
open SpeedApp.xcodeproj
```
Then just hit Run in Xcode with your phone plugged in — Xcode signs it with your free Apple ID automatically over USB, no Sideloadly needed.

## Notes

- First launch will prompt for location permission — required for speed readings.
- Speed accuracy depends on GPS quality; smoothing is applied over the last 3 readings to reduce jitter.
- 0-60/0-100 timers start once the car crosses ~1 mph from a stop, so make sure you're stationary before hitting "Start Run Timer."

import SwiftUI

/// An in-app summary of everything the app can do.
///
/// KEEP THIS IN SYNC. Whenever a feature is added, changed, or removed, update this file
/// and the README together. This is what the rider sees when they tap
/// "What This App Does" in Settings — if it drifts out of date, it's worse than useless.
struct AboutView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A GPS speedometer, ride recorder, and navigator built for electric scooters. Everything here is free — no paywalls, no subscriptions, no ads. All your data stays on your device.")
                        .font(.subheadline)
                        .padding(.vertical, 4)
                }

                ForEach(Self.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            featureRow(item)
                        }
                    } header: {
                        Label(section.title, systemImage: section.icon)
                    }
                }

                Section {
                    ForEach(Self.privacyPoints, id: \.self) { point in
                        Text(point)
                            .font(.caption)
                            .padding(.vertical, 1)
                    }
                } header: {
                    Label("Privacy", systemImage: "lock.shield")
                }

                Section {
                    ForEach(Self.limitations, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Good to Know", systemImage: "info.circle")
                } footer: {
                    Text("Version 2.1")
                }
            }
            .navigationTitle("What This App Does")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(settings.accent.color)
    }

    private func featureRow(_ item: Feature) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.subheadline.weight(.semibold))
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Content

    struct Feature: Identifiable {
        let name: String
        let detail: String
        var id: String { name }
    }

    struct FeatureSection: Identifiable {
        let title: String
        let icon: String
        let items: [Feature]
        var id: String { title }
    }

    static let sections: [FeatureSection] = [
        FeatureSection(title: "Vehicles", icon: "car.2.fill", items: [
            Feature(
                name: "Four modes",
                detail: "Switch between Scooter, Car, Motorcycle, and Walking in Settings. Each one keeps its own speed alert, auto-pause, GPS, and smoothing — so tuning one never disturbs another."
            ),
            Feature(
                name: "Mode-aware behavior",
                detail: "Walking gets footpath routes instead of roads. Battery tracking only appears for the scooter. Auto-pause and alert defaults are sensible for each vehicle."
            ),
            Feature(
                name: "Per-vehicle history",
                detail: "Every ride is tagged with the vehicle you used. Filter your history by vehicle, and see lifetime totals per vehicle or all together."
            )
        ]),
        FeatureSection(title: "Speed", icon: "speedometer", items: [
            Feature(
                name: "Live speed",
                detail: "Big readout in MPH or KM/H, smoothed so it doesn't jump around between GPS updates."
            ),
            Feature(
                name: "Max speed",
                detail: "Tracks your top speed since the last reset. Reset it from the Speed tab or Settings."
            ),
            Feature(
                name: "GPS signal indicator",
                detail: "Tells you when the reading is trustworthy, weak, or still locking on."
            ),
            Feature(
                name: "Speed limit alert",
                detail: "Optional. Set any speed and get a vibration and on-screen warning when you pass it."
            )
        ]),

        FeatureSection(title: "Record", icon: "record.circle", items: [
            Feature(
                name: "Record a ride",
                detail: "Logs speed, distance, duration, and elevation with a live graph as you go."
            ),
            Feature(
                name: "Pause and resume",
                detail: "Time spent paused doesn't count toward your ride. If you move while paused, that distance isn't counted either."
            ),
            Feature(
                name: "Auto-pause",
                detail: "Optional. Pauses on its own once you've been still for a while, and resumes when you move. Keeps red lights out of your ride time and average speed. You can tune both the speed and the delay in Settings."
            ),
            Feature(
                name: "Elevation",
                detail: "Tracks how much you climbed and descended."
            ),
            Feature(
                name: "Battery logging",
                detail: "Optional. Enter your scooter's battery level before and after a ride. After a few rides the app estimates your range."
            ),
            Feature(
                name: "Records with the screen off",
                detail: "Keeps logging speed, distance, and route while your phone is locked or in your pocket. A blue indicator shows in the status bar while it's tracking in the background."
            ),
            Feature(
                name: "Keep screen awake",
                detail: "Optional. Stops your phone locking mid-ride if you'd rather watch the live readout."
            )
        ]),

        FeatureSection(title: "Map", icon: "map", items: [
            Feature(
                name: "Set a destination",
                detail: "Search for a place, tap one on the map, or press and hold anywhere to drop a pin."
            ),
            Feature(
                name: "Recenter and lock-on",
                detail: "A button snaps the map back to your location, and a lock button keeps the map pinned to you as you move. Panning the map yourself is always available."
            ),
            Feature(
                name: "Turn-by-turn navigation",
                detail: "Real road routing with distance and ETA, and spoken directions as you ride. You get a heads-up before each turn and a final call at the turn itself. Mute or change the voice speed any time."
            ),
            Feature(
                name: "Automatic rerouting",
                detail: "If you leave the route, it recalculates a new one from where you actually are, just like Apple Maps."
            ),
            Feature(
                name: "Choose the voice",
                detail: "Pick which voice reads your directions from the voices installed on your phone, and preview it. Download more (including higher-quality ones) in iOS Settings › Accessibility › Read & Speak › Voices."
            ),
            Feature(
                name: "Plays nicely with music",
                detail: "Spotify or whatever you're listening to only dips for the second it takes to speak a direction, then goes straight back to full volume."
            ),
            Feature(
                name: "Keeps talking with the screen off",
                detail: "Spoken directions continue when your phone is locked or in your pocket."
            ),
            Feature(
                name: "Doesn't over-talk",
                detail: "Ordinary announcements are spaced out so the voice isn't constantly chattering. Turn calls, arrival, and rerouting always come through regardless."
            )
        ]),

        FeatureSection(title: "History", icon: "clock.arrow.circlepath", items: [
            Feature(
                name: "Saved rides",
                detail: "Every recording, with a route map showing exactly where you went — shaded from pale to deep to show where you were slow and fast (toggle in Settings)."
            ),
            Feature(
                name: "Rename, sort, and search",
                detail: "Swipe a ride in the list to rename or delete it. Sort by date, distance, top speed, or duration, and search by name."
            ),
            Feature(
                name: "Trip replay",
                detail: "Watch a marker retrace your route while the speed graph scrubs along with it. Play it back in real-time, slow it to half speed, or speed it up to 8x."
            ),
            Feature(
                name: "Interactive graph",
                detail: "Drag across any ride's graph to see your exact speed, how far into the ride it was, and the time of day."
            ),
            Feature(
                name: "Trends",
                detail: "Weekly and monthly charts of your distance and ride count. Empty weeks show as zero, so gaps in your riding are visible rather than hidden."
            ),
            Feature(
                name: "Personal records",
                detail: "Top speed, longest distance, longest ride, biggest climb, busiest week. You get told right after a ride if you just beat one."
            ),
            Feature(
                name: "Heatmap",
                detail: "Every route you've ever recorded on one map. Roads you ride often glow brighter than one-off trips."
            ),
            Feature(
                name: "Lifetime totals",
                detail: "Total rides, distance, time, top speed, average speed, longest ride, and total climb."
            )
        ]),

        FeatureSection(title: "Exports", icon: "square.and.arrow.up", items: [
            Feature(
                name: "Route map image",
                detail: "A PNG of your route with start and end markers and your ride stats. Good for sharing."
            ),
            Feature(
                name: "Speed graph image",
                detail: "A PNG of a ride's speed graph."
            ),
            Feature(
                name: "Rides summary (CSV)",
                detail: "A spreadsheet with one row per ride — date, distance, speeds, elevation, battery. Good for spotting trends."
            ),
            Feature(
                name: "Ride data (CSV)",
                detail: "A spreadsheet with one row per GPS reading — time, speed, latitude, longitude, altitude. Raw data for your own analysis."
            )
        ]),

        FeatureSection(title: "Customization", icon: "gearshape", items: [
            Feature(
                name: "Units",
                detail: "MPH or KM/H. Applies everywhere, including graphs, navigation, and exports."
            ),
            Feature(
                name: "Appearance",
                detail: "Light, dark, or match your system. Twelve accent colors."
            ),
            Feature(
                name: "Map style",
                detail: "Standard, satellite, or hybrid."
            ),
            Feature(
                name: "Speed-colored routes",
                detail: "Saved routes shade from dark and muted (slow) to bright and vivid (fast) in your accent color. Colours are scaled to each ride's own speeds, so a 15 mph scooter trip and an 80 mph drive both show their fast and slow stretches clearly. That means colour shows speed relative to that ride, not an absolute number. Exported route images match. Toggle it under Map in Settings."
            ),
            Feature(
                name: "Graph style",
                detail: "Smooth curves or straight lines."
            ),
            Feature(
                name: "Speed smoothing",
                detail: "Responsive reacts fastest but can jitter. Smooth is steadier but lags a little."
            ),
            Feature(
                name: "GPS mode",
                detail: "High accuracy, or battery saver for longer rides."
            ),
            Feature(
                name: "Haptics and confirmations",
                detail: "Subtle vibration on taps, tab switches, recording controls, and alerts — toggle it all off in one place. Also choose whether deleting your history asks first."
            )
        ])
    ]

    /// Privacy disclosure. These statements must stay true — if the app's data handling
    /// ever changes (a server, analytics, any network call), update this first.
    static let privacyPoints: [String] = [
        "Your data never leaves your phone. There is no account, no server, no analytics, and no third parties. The app makes no network calls with your data.",
        "Backing up your rides creates a file you choose where to put. If you save it to iCloud Drive, that copy is in your own iCloud — the app never sends it anywhere itself.",
        "Rides you record are saved on your device so you can view them later. That includes the GPS route, speed, elevation, and any battery levels you logged.",
        "Location is used while the app is open, and continues in the background only while you are actively recording a ride. iOS shows a blue indicator whenever that is happening.",
        "Recording never starts on its own. It only runs when you tap Start, and stops when you tap Stop.",
        "You can delete any ride by swiping it, or erase everything with Clear All Recordings in Settings. Deleting the app removes all of it.",
        "The map, search, and navigation features send your search terms and route requests to Apple Maps, which is what makes them work. Apple's privacy policy covers that."
    ]

    static let limitations: [String] = [
        "Speed comes from GPS, which updates about once a second. The number on screen is smoothed to look fluid, but that's the real data rate underneath.",
        "Elevation is the noisiest thing GPS measures. Treat those numbers as approximate.",
        "Your route is drawn from raw GPS, which is only accurate to about 15-30 feet. On a path running close to a road, the line may appear to sit on the road even though you weren't on it — that's the phone's position estimate, not the app moving you.",
        "Navigation uses Apple's driving routes — there's no scooter-specific routing available, so it may occasionally send you down a road that isn't ideal.",
        "Rerouting needs a data connection. Without one, it keeps guiding you along the original route.",
        "Battery range estimates need at least 3 logged rides and get better with more. They assume your riding stays fairly consistent.",
        "Exporting a route map needs an internet connection, since it downloads map tiles.",
        "Background recording needs Always location permission. If it's set to \"While Using the App\", GPS stops the moment your screen locks and your ride gets cut short. Check it under Permissions in Settings — the app will warn you if it isn't set correctly."
    ]
}

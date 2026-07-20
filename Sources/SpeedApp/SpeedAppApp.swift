import SwiftUI
import AVFoundation
import UIKit

@main
struct SpeedAppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationManager = LocationManager()
    @StateObject private var runStore = RunStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var navigation = NavigationStore()
    @StateObject private var heatmapStore = HeatmapStore()

    init() {
        // Deliberately does NOT activate the audio session here.
        //
        // Activating at launch meant Spotify stayed quiet the whole time the app was open.
        // NavigationStore owns the session instead: claimed when navigation starts, released
        // when it ends (stop or arrival). With .duckOthers + .mixWithOthers, iOS only dips
        // other audio while a direction is actually being spoken — and holding the session
        // for the whole navigation is what keeps speech working after the screen locks,
        // since a backgrounded app can't activate a session from cold. Do not "optimize"
        // this back to per-utterance activate/release; that reintroduces the bug where
        // guidance went silent as soon as the phone locked.
    }

    /// The screen should stay awake if we're recording (and the user wants it to) or if
    /// we're actively navigating. Centralized here so recording and navigation don't each
    /// write isIdleTimerDisabled independently and fight — ending one mode used to let the
    /// screen sleep even while the other was still going.
    private var shouldKeepScreenAwake: Bool {
        (locationManager.isRecording && settings.keepScreenAwake) || navigation.isNavigating
    }

    private func syncScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = shouldKeepScreenAwake
    }

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    // The view is assembled in layers, each its own computed property. One flat chain of
    // 15 modifiers with a dozen closures is a single giant expression, and the Release
    // build's type-checker gave up on it ("unable to type-check this expression in
    // reasonable time"). Splitting the chain gives the compiler small, independent
    // expressions instead. Behavior is identical.

    private var rootView: some View {
        syncedView
            .onChange(of: locationManager.isRecording) { _, _ in syncScreenAwake() }
            .onChange(of: settings.keepScreenAwake) { _, _ in syncScreenAwake() }
            .onChange(of: navigation.isNavigating) { _, _ in syncScreenAwake() }
            // Coming back from iOS Settings — the rider may have just changed the
            // location permission, so re-read it rather than showing a stale warning.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    locationManager.refreshAuthorizationStatus()
                }
            }
            .onReceive(locationManager.$currentLocation) { loc in
                if let loc {
                    navigation.updateProgress(currentLocation: loc)
                }
            }
    }

    private var syncedView: some View {
        baseView
            .onChange(of: settings.smoothing) { _, v in locationManager.smoothingAlpha = v.alpha }
            .onChange(of: settings.gpsAccuracy) { _, v in locationManager.applyAccuracyMode(v) }
            .onChange(of: settings.autoPauseEnabled) { _, v in locationManager.autoPauseEnabled = v }
            .onChange(of: settings.autoPauseSpeedMph) { _, v in locationManager.autoPauseSpeedThreshold = v }
            .onChange(of: settings.autoPauseDelaySeconds) { _, v in locationManager.autoPauseDelay = v }
            .onChange(of: settings.voiceSpeechRate) { _, v in navigation.speechRate = Float(v) }
            .onChange(of: settings.unit) { _, v in navigation.usesMetricUnits = v == .kmh }
            .onChange(of: settings.voiceIdentifier) { _, v in navigation.voiceIdentifier = v }
            .onChange(of: settings.hapticsEnabled) { _, v in Haptics.enabled = v }
            // Switching vehicle re-tunes GPS filtering and the routing profile, and
            // swaps in that vehicle's own settings (handled inside SettingsStore).
            .onChange(of: settings.vehicleMode) { _, v in
                locationManager.applyVehicleMode(v)
                navigation.transportType = v.transportType
            }
    }

    private var baseView: some View {
        ContentView()
            .environmentObject(locationManager)
            .environmentObject(runStore)
            .environmentObject(settings)
            .environmentObject(navigation)
            .environmentObject(heatmapStore)
            .preferredColorScheme(settings.appearance.colorScheme)
            .tint(settings.accent.color)
            .onAppear { applyInitialSettings() }
    }

    /// One-time push of every persisted setting into the live objects at launch.
    private func applyInitialSettings() {
        locationManager.smoothingAlpha = settings.smoothing.alpha
        locationManager.applyAccuracyMode(settings.gpsAccuracy)
        locationManager.applyVehicleMode(settings.vehicleMode)
        navigation.transportType = settings.vehicleMode.transportType
        locationManager.autoPauseEnabled = settings.autoPauseEnabled
        locationManager.autoPauseSpeedThreshold = settings.autoPauseSpeedMph
        locationManager.autoPauseDelay = settings.autoPauseDelaySeconds
        navigation.speechRate = Float(settings.voiceSpeechRate)
        navigation.voiceIdentifier = settings.voiceIdentifier
        navigation.usesMetricUnits = settings.unit == .kmh
        Haptics.enabled = settings.hapticsEnabled
        syncScreenAwake()
    }
}

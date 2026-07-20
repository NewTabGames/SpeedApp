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
        // Deliberately does NOT activate the audio session here. NavigationStore claims it
        // for the duration of a navigation session (see its audio-session notes); claiming
        // it at launch made music stay ducked the whole time the app was open.
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

    // The view is assembled in SMALL layers, each its own computed property, with AnyView
    // between them. The Release build's type-checker has to solve each modifier chain as one
    // expression, and both a 15-modifier chain and a 10-modifier chain have now failed with
    // "unable to type-check this expression in reasonable time". AnyView erases the
    // accumulated generic type at each boundary, so every layer stays a small independent
    // problem no matter how many more syncs get added later. At the app root this costs
    // nothing measurable — these re-evaluate only when a setting changes.

    private var rootView: some View {
        observationLayer
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

    /// Screen-awake and haptics observation.
    private var observationLayer: AnyView {
        AnyView(
            voiceSyncLayer
                .onChange(of: locationManager.isRecording) { _, _ in syncScreenAwake() }
                .onChange(of: settings.keepScreenAwake) { _, _ in syncScreenAwake() }
                .onChange(of: navigation.isNavigating) { _, _ in syncScreenAwake() }
                .onChange(of: settings.hapticsEnabled) { _, v in Haptics.enabled = v }
        )
    }

    /// Voice and unit syncs into NavigationStore.
    private var voiceSyncLayer: AnyView {
        AnyView(
            gpsSyncLayer
                .onChange(of: settings.voiceSpeechRate) { _, v in navigation.speechRate = Float(v) }
                .onChange(of: settings.voiceIdentifier) { _, v in navigation.voiceIdentifier = v }
                .onChange(of: settings.unit) { _, v in navigation.usesMetricUnits = v == .kmh }
                // Switching vehicle re-tunes GPS filtering and the routing profile, and
                // swaps in that vehicle's own settings (handled inside SettingsStore).
                .onChange(of: settings.vehicleMode) { _, v in
                    locationManager.applyVehicleMode(v)
                    navigation.transportType = v.transportType
                }
        )
    }

    /// GPS tuning syncs into LocationManager.
    private var gpsSyncLayer: AnyView {
        AnyView(
            baseView
                .onChange(of: settings.smoothing) { _, v in locationManager.smoothingAlpha = v.alpha }
                .onChange(of: settings.gpsAccuracy) { _, v in locationManager.applyAccuracyMode(v) }
                .onChange(of: settings.autoPauseEnabled) { _, v in locationManager.autoPauseEnabled = v }
                .onChange(of: settings.autoPauseSpeedMph) { _, v in locationManager.autoPauseSpeedThreshold = v }
                .onChange(of: settings.autoPauseDelaySeconds) { _, v in locationManager.autoPauseDelay = v }
        )
    }

    /// The content view with its environment, appearance, and launch sync.
    private var baseView: AnyView {
        AnyView(
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(runStore)
                .environmentObject(settings)
                .environmentObject(navigation)
                .environmentObject(heatmapStore)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(settings.accent.color)
                .onAppear { applyInitialSettings() }
        )
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

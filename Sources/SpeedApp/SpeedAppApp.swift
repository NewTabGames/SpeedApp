import SwiftUI
import AVFoundation
import UIKit

@main
struct SpeedAppApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var runStore = RunStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var navigation = NavigationStore()

    init() {
        // Deliberately does NOT activate the audio session here.
        //
        // The session uses .duckOthers so spoken directions are audible over music, but
        // ducking lasts as long as the session is *active*. Activating at launch meant
        // Spotify stayed quiet the whole time the app was open. NavigationStore now
        // activates the session immediately before speaking and releases it as soon as
        // the utterance finishes, so music is only dipped for the second or two it takes
        // to say "turn right".
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
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(runStore)
                .environmentObject(settings)
                .environmentObject(navigation)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(settings.accent.color)
                .onAppear {
                    locationManager.smoothingAlpha = settings.smoothing.alpha
                    locationManager.applyAccuracyMode(settings.gpsAccuracy)
                    locationManager.autoPauseEnabled = settings.autoPauseEnabled
                    locationManager.autoPauseSpeedThreshold = settings.autoPauseSpeedMph
                    locationManager.autoPauseDelay = settings.autoPauseDelaySeconds
                    navigation.speechRate = Float(settings.voiceSpeechRate)
                    navigation.voiceIdentifier = settings.voiceIdentifier
                    syncScreenAwake()
                }
                .onChange(of: settings.smoothing) { _, newValue in
                    locationManager.smoothingAlpha = newValue.alpha
                }
                .onChange(of: settings.gpsAccuracy) { _, newValue in
                    locationManager.applyAccuracyMode(newValue)
                }
                .onChange(of: settings.autoPauseEnabled) { _, newValue in
                    locationManager.autoPauseEnabled = newValue
                }
                .onChange(of: settings.autoPauseSpeedMph) { _, newValue in
                    locationManager.autoPauseSpeedThreshold = newValue
                }
                .onChange(of: settings.autoPauseDelaySeconds) { _, newValue in
                    locationManager.autoPauseDelay = newValue
                }
                .onChange(of: settings.voiceSpeechRate) { _, newValue in
                    navigation.speechRate = Float(newValue)
                }
                .onChange(of: settings.voiceIdentifier) { _, newValue in
                    navigation.voiceIdentifier = newValue
                }
                .onChange(of: locationManager.isRecording) { _, _ in syncScreenAwake() }
                .onChange(of: settings.keepScreenAwake) { _, _ in syncScreenAwake() }
                .onChange(of: navigation.isNavigating) { _, _ in syncScreenAwake() }
                .onReceive(locationManager.$currentLocation) { loc in
                    if let loc {
                        navigation.updateProgress(currentLocation: loc)
                    }
                }
        }
    }
}

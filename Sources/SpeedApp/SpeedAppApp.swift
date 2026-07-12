import SwiftUI
import AVFoundation

@main
struct SpeedAppApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var runStore = RunStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var navigation = NavigationStore()

    init() {
        // Lets spoken turn-by-turn prompts play out loud (not muted by the silent switch)
        // and duck any other audio briefly while speaking.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
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
                    navigation.speechRate = Float(settings.voiceSpeechRate)
                }
                .onChange(of: settings.smoothing) { _, newValue in
                    locationManager.smoothingAlpha = newValue.alpha
                }
                .onChange(of: settings.gpsAccuracy) { _, newValue in
                    locationManager.applyAccuracyMode(newValue)
                }
                .onChange(of: settings.voiceSpeechRate) { _, newValue in
                    navigation.speechRate = Float(newValue)
                }
                .onReceive(locationManager.$currentLocation) { loc in
                    if let loc {
                        navigation.updateProgress(currentLocation: loc)
                    }
                }
        }
    }
}

import SwiftUI

@main
struct SpeedAppApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var runStore = RunStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(runStore)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(settings.accent.color)
                .onAppear {
                    locationManager.smoothingAlpha = settings.smoothing.alpha
                }
                .onChange(of: settings.smoothing) { _, newValue in
                    locationManager.smoothingAlpha = newValue.alpha
                }
        }
    }
}

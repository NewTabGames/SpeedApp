import SwiftUI

@main
struct SpeedAppApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var runStore = RunStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(runStore)
                .preferredColorScheme(.dark)
        }
    }
}

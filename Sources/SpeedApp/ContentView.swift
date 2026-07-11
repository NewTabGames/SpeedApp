import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SpeedView()
                .tabItem {
                    Label("Speed", systemImage: "speedometer")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}

// MARK: - Speed Tab

struct SpeedView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var runStore: RunStore

    var body: some View {
        VStack(spacing: 28) {

            permissionBanner

            Spacer()

            VStack(spacing: 4) {
                Text(String(format: "%.0f", location.speedMph))
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("MPH")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 40) {
                statBlock(title: "MAX", value: String(format: "%.0f mph", location.maxSpeedMph))
                statBlock(title: "0-60", value: timeString(location.zeroToSixtySeconds))
                statBlock(title: "0-100", value: timeString(location.zeroToHundredSeconds))
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: toggleTiming) {
                    Text(location.isTiming ? "Cancel Run" : "Start Run Timer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(location.isTiming ? Color.red.opacity(0.85) : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button("Reset Max Speed") {
                    location.resetMaxSpeed()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .padding(.top, 20)
        .onAppear {
            location.requestPermission()
            location.start()
        }
        .onChange(of: location.zeroToHundredSeconds) { _, newValue in
            if newValue != nil {
                saveCompletedRun()
            }
        }
    }

    private var permissionBanner: some View {
        Group {
            if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                Text("Location access is off. Enable it in Settings to see your speed.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleTiming() {
        if location.isTiming {
            location.cancelTimer()
        } else {
            location.armTimer()
        }
    }

    private func saveCompletedRun() {
        runStore.addRun(
            zeroToSixty: location.zeroToSixtySeconds,
            zeroToHundred: location.zeroToHundredSeconds,
            topSpeedMph: location.maxSpeedMph
        )
    }

    private func timeString(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2fs", value)
    }
}

// MARK: - History Tab

struct HistoryView: View {
    @EnvironmentObject var runStore: RunStore

    var body: some View {
        NavigationView {
            List {
                ForEach(runStore.runs) { run in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(run.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 20) {
                            if let z60 = run.zeroToSixty {
                                Text("0-60: \(String(format: "%.2f", z60))s")
                            }
                            if let z100 = run.zeroToHundred {
                                Text("0-100: \(String(format: "%.2f", z100))s")
                            }
                        }
                        .font(.body.weight(.medium))
                        Text("Top speed: \(String(format: "%.0f", run.topSpeedMph)) mph")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: runStore.deleteRun)
            }
            .navigationTitle("Run History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !runStore.runs.isEmpty {
                        Button("Clear All", role: .destructive) {
                            runStore.clearAll()
                        }
                    }
                }
            }
            .overlay {
                if runStore.runs.isEmpty {
                    ContentUnavailableView(
                        "No Runs Yet",
                        systemImage: "stopwatch",
                        description: Text("Start a run timer from the Speed tab to log your first run.")
                    )
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(RunStore())
}

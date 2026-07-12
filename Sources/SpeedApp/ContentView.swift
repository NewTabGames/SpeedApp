import SwiftUI
import Charts
import UIKit

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        TabView {
            SpeedView()
                .tabItem { Label("Speed", systemImage: "speedometer") }
            RecordView()
                .tabItem { Label("Record", systemImage: "record.circle") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(settings.accent.color)
    }
}

// MARK: - Shared helpers

private func signalColor(_ q: LocationManager.SignalQuality) -> Color {
    switch q {
    case .acquiring: return .gray
    case .weak: return .yellow
    case .good: return .green
    }
}

private func signalLabel(_ q: LocationManager.SignalQuality) -> String {
    switch q {
    case .acquiring: return "Acquiring GPS…"
    case .weak: return "Weak signal"
    case .good: return "GPS locked"
    }
}

private func backgroundGradient() -> some View {
    LinearGradient(colors: [Color.black, Color(red: 0.08, green: 0.08, blue: 0.1)],
                   startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
}

// MARK: - Speed Tab

struct SpeedView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var settings: SettingsStore
    @State private var didAlert = false

    var body: some View {
        ZStack {
            backgroundGradient()

            VStack(spacing: 24) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(signalColor(location.signalQuality))
                        .frame(width: 8, height: 8)
                    Text(signalLabel(location.signalQuality))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                    Text("Location access is off. Enable it in Settings to see your speed.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 0) {
                    Text(String(format: "%.0f", displaySpeed))
                        .font(.system(size: 130, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.15), value: location.speedMph)
                    Text(settings.unit.rawValue)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(settings.accent.color)
                        .tracking(4)
                }

                HStack(spacing: 0) {
                    statBlock(title: "MAX", value: String(format: "%.0f %@", displayMax, settings.unit.rawValue))
                }
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                Button("Reset Max Speed") {
                    location.resetMaxSpeed()
                    didAlert = false
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            location.requestPermission()
            location.start()
        }
        .alert("Speed Alert", isPresented: $didAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You've exceeded your set speed limit of \(String(format: "%.0f", settings.maxSpeedAlertMph)) mph.")
        }
        .onChange(of: location.speedMph) { _, newValue in
            if settings.maxSpeedAlertEnabled && newValue >= settings.maxSpeedAlertMph && !didAlert {
                didAlert = true
            }
        }
    }

    private var displaySpeed: Double {
        settings.unit.convert(fromMph: location.speedMph)
    }
    private var displayMax: Double {
        settings.unit.convert(fromMph: location.maxSpeedMph)
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Record Tab

struct RecordView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var runStore: RunStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ZStack {
            backgroundGradient()

            VStack(spacing: 20) {
                Text(location.isRecording ? "Recording…" : "Ready to Record")
                    .font(.headline)
                    .foregroundStyle(location.isRecording ? .red : .secondary)
                    .padding(.top, 16)

                Text(elapsedString(location.recordingElapsed))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Chart(location.recordingSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.offsetSeconds),
                        y: .value("Speed", settings.unit.convert(fromMph: sample.mph))
                    )
                    .foregroundStyle(settings.accent.color)
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 180)
                .padding(.horizontal)
                .chartYAxisLabel(settings.unit.rawValue.lowercased())

                HStack(spacing: 0) {
                    statBlock(title: "CURRENT", value: unitString(location.speedMph))
                    statBlock(title: "MAX", value: unitString(location.recordingMaxMph))
                    statBlock(title: "AVG", value: unitString(location.recordingAvgMph))
                }
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                Button(action: toggleRecording) {
                    Text(location.isRecording ? "Stop & Save Recording" : "Start Recording")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(location.isRecording ? Color.red : settings.accent.color)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .onChange(of: location.isRecording) { _, isRecording in
            UIApplication.shared.isIdleTimerDisabled = isRecording && settings.keepScreenAwake
        }
    }

    private func unitString(_ mph: Double) -> String {
        String(format: "%.0f %@", settings.unit.convert(fromMph: mph), settings.unit.rawValue)
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleRecording() {
        if location.isRecording {
            if let result = location.stopRecording() {
                runStore.addRecording(samples: result.samples, maxMph: result.maxMph, avgMph: result.avgMph, duration: result.duration)
            }
        } else {
            location.startRecording()
        }
    }

    private func elapsedString(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - History Tab

struct HistoryView: View {
    @EnvironmentObject var runStore: RunStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        NavigationView {
            List {
                ForEach(runStore.recordings) { rec in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rec.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Chart(rec.samples) { sample in
                            LineMark(
                                x: .value("Time", sample.offsetSeconds),
                                y: .value("Speed", settings.unit.convert(fromMph: sample.mph))
                            )
                            .foregroundStyle(settings.accent.color)
                            .interpolationMethod(.catmullRom)
                        }
                        .frame(height: 60)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)

                        HStack(spacing: 20) {
                            Text("Max: \(String(format: "%.0f", settings.unit.convert(fromMph: rec.maxMph))) \(settings.unit.rawValue)")
                            Text("Avg: \(String(format: "%.0f", settings.unit.convert(fromMph: rec.avgMph))) \(settings.unit.rawValue)")
                            Text("Time: \(durationString(rec.duration))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: runStore.deleteRecording)
            }
            .navigationTitle("Recording History")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !runStore.recordings.isEmpty {
                        Button("Clear", role: .destructive) { runStore.clearAllRecordings() }
                    }
                }
            }
            .overlay {
                if runStore.recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings Yet",
                        systemImage: "record.circle",
                        description: Text("Start a recording from the Record tab to log your first ride.")
                    )
                }
            }
        }
    }

    private func durationString(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Settings Tab

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var runStore: RunStore

    var body: some View {
        NavigationView {
            Form {
                Section("Units") {
                    Picker("Speed Unit", selection: $settings.unit) {
                        ForEach(SpeedUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Appearance") {
                    Picker("Accent Color", selection: $settings.accent) {
                        ForEach(AccentTheme.allCases) { theme in
                            HStack {
                                Circle().fill(theme.color).frame(width: 14, height: 14)
                                Text(theme.rawValue)
                            }
                            .tag(theme)
                        }
                    }
                }

                Section {
                    Picker("Speed Smoothing", selection: $settings.smoothing) {
                        ForEach(SmoothingLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                } header: {
                    Text("Reading Behavior")
                } footer: {
                    Text("Responsive reacts fastest to speed changes but may jitter slightly. Smooth is steadier but has more lag.")
                }

                Section {
                    Toggle("Keep Screen Awake While Recording", isOn: $settings.keepScreenAwake)
                }

                Section {
                    Toggle("Speed Limit Alert", isOn: $settings.maxSpeedAlertEnabled)
                    if settings.maxSpeedAlertEnabled {
                        HStack {
                            Text("Alert above")
                            Spacer()
                            Text("\(Int(settings.maxSpeedAlertMph)) mph")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.maxSpeedAlertMph, in: 5...60, step: 1)
                    }
                } header: {
                    Text("Safety")
                }

                Section {
                    Button("Clear All Recordings", role: .destructive) {
                        runStore.clearAllRecordings()
                    }
                } header: {
                    Text("Data")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(RunStore())
        .environmentObject(SettingsStore())
}

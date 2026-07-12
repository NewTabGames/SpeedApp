import SwiftUI
import Charts
import UIKit
import MapKit

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        TabView {
            SpeedView()
                .tabItem { Label("Speed", systemImage: "speedometer") }
            RecordView()
                .tabItem { Label("Record", systemImage: "record.circle") }
            MapTabView()
                .tabItem { Label("Map", systemImage: "map") }
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
                if settings.hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
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

            ScrollView {
                VStack(spacing: 20) {
                    Text(location.isRecording ? "Recording…" : "Ready to Record")
                        .font(.headline)
                        .foregroundStyle(location.isRecording ? .red : .secondary)
                        .padding(.top, 16)

                    Text(elapsedString(location.recordingElapsed))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    InteractiveSpeedChart(
                        samples: location.recordingSamples,
                        unit: settings.unit,
                        accent: settings.accent.color,
                        height: 180,
                        lineStyle: settings.chartLineStyle
                    )
                    .padding(.horizontal)

                    HStack(spacing: 0) {
                        statBlock(title: "CURRENT", value: unitString(location.speedMph))
                        statBlock(title: "MAX", value: unitString(location.recordingMaxMph))
                        statBlock(title: "AVG", value: unitString(location.recordingAvgMph))
                        statBlock(title: "DISTANCE", value: distanceString(location.recordingDistanceMiles))
                    }
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

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
        }
        .onChange(of: location.isRecording) { _, isRecording in
            UIApplication.shared.isIdleTimerDisabled = isRecording && settings.keepScreenAwake
        }
    }

    private func unitString(_ mph: Double) -> String {
        String(format: "%.0f %@", settings.unit.convert(fromMph: mph), settings.unit.rawValue)
    }

    private func distanceString(_ miles: Double) -> String {
        String(format: "%.2f %@", settings.unit.convertDistance(fromMiles: miles), settings.unit.distanceUnitLabel)
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
        if settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if location.isRecording {
            if let result = location.stopRecording() {
                runStore.addRecording(samples: result.samples, maxMph: result.maxMph, avgMph: result.avgMph, duration: result.duration, distanceMiles: result.distanceMiles)
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
                    NavigationLink(destination: RecordingDetailView(recording: rec)) {
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

                            HStack(spacing: 16) {
                                Text("Max: \(String(format: "%.0f", settings.unit.convert(fromMph: rec.maxMph))) \(settings.unit.rawValue)")
                                Text("\(String(format: "%.1f", settings.unit.convertDistance(fromMiles: rec.distanceMiles))) \(settings.unit.distanceUnitLabel)")
                                Text(durationString(rec.duration))
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
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

// MARK: - Recording Detail (with route map)

struct RecordingDetailView: View {
    let recording: SpeedRecording
    @EnvironmentObject var settings: SettingsStore

    private var coordinates: [CLLocationCoordinate2D] {
        recording.samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var cameraPosition: MapCameraPosition {
        guard !coordinates.isEmpty else {
            return .automatic
        }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.005),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.005)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if coordinates.count > 1 {
                    Map(initialPosition: cameraPosition) {
                        MapPolyline(coordinates: coordinates)
                            .stroke(settings.accent.color, lineWidth: 4)
                        if let first = coordinates.first {
                            Marker("Start", coordinate: first)
                                .tint(.green)
                        }
                        if let last = coordinates.last {
                            Marker("End", coordinate: last)
                                .tint(.red)
                        }
                    }
                    .frame(height: 280)
                    .mapStyle(settings.mapStyle.mapStyle)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                } else {
                    Text("Not enough GPS data to draw a route for this ride.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    statRow("Date", recording.date.formatted(date: .abbreviated, time: .shortened))
                    statRow("Duration", durationString(recording.duration))
                    statRow("Distance", String(format: "%.2f %@", settings.unit.convertDistance(fromMiles: recording.distanceMiles), settings.unit.distanceUnitLabel))
                    statRow("Max Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: recording.maxMph), settings.unit.rawValue))
                    statRow("Avg Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: recording.avgMph), settings.unit.rawValue))
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                NavigationLink(destination: GraphDetailView(recording: recording)) {
                    VStack(alignment: .leading, spacing: 8) {
                        InteractiveSpeedChart(
                            samples: recording.samples,
                            unit: settings.unit,
                            accent: settings.accent.color,
                            height: 160,
                            lineStyle: settings.chartLineStyle
                        )
                        HStack {
                            Text("View Full Graph & Export")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(settings.accent.color)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(settings.accent.color)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Ride Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
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
    @EnvironmentObject var location: LocationManager

    @State private var alertSpeedText: String = ""
    @FocusState private var alertFieldFocused: Bool

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
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

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

                Section("Map") {
                    Picker("Map Style", selection: $settings.mapStyle) {
                        ForEach(MapStyleOption.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }

                Section {
                    Picker("Graph Line Style", selection: $settings.chartLineStyle) {
                        ForEach(ChartLineStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                } header: {
                    Text("Graphs")
                }

                Section {
                    Picker("Speed Smoothing", selection: $settings.smoothing) {
                        ForEach(SmoothingLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }

                    Picker("GPS Mode", selection: $settings.gpsAccuracy) {
                        ForEach(GPSAccuracyMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } header: {
                    Text("Reading Behavior")
                } footer: {
                    Text("Responsive reacts fastest to speed changes but may jitter. Battery Saver reduces GPS precision to extend battery life on longer rides.")
                }

                Section {
                    Toggle("Keep Screen Awake While Recording", isOn: $settings.keepScreenAwake)
                    Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)
                } header: {
                    Text("Behavior")
                }

                Section {
                    HStack {
                        Text("Voice Speed")
                        Spacer()
                        Text(voiceRateLabel)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.voiceSpeechRate, in: 0.3...0.6, step: 0.05)
                } header: {
                    Text("Navigation Voice")
                } footer: {
                    Text("Controls how fast spoken turn-by-turn directions are read out.")
                }

                Section {
                    Toggle("Speed Limit Alert", isOn: $settings.maxSpeedAlertEnabled)
                    if settings.maxSpeedAlertEnabled {
                        HStack {
                            Text("Alert above")
                            Spacer()
                            TextField("0", text: $alertSpeedText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($alertFieldFocused)
                                .frame(width: 70)
                                .onChange(of: alertSpeedText) { _, newValue in
                                    let digits = newValue.filter(\.isWholeNumber)
                                    if digits != newValue { alertSpeedText = digits }
                                    if let value = Double(digits), value > 0 {
                                        settings.maxSpeedAlertMph = settings.unit == .mph ? value : value / 1.60934
                                    }
                                }
                            Text(settings.unit.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Safety")
                } footer: {
                    Text("Get a vibration and on-screen alert when you exceed this speed.")
                }

                Section {
                    Button("Reset Max Speed", role: .destructive) {
                        location.resetMaxSpeed()
                    }
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
                        Text("2.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Saved Recordings")
                        Spacer()
                        Text("\(runStore.recordings.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { alertFieldFocused = false }
                }
            }
            .onAppear { syncAlertText() }
            .onChange(of: settings.unit) { _, _ in syncAlertText() }
        }
    }

    private var voiceRateLabel: String {
        switch settings.voiceSpeechRate {
        case ..<0.4: return "Slow"
        case ..<0.52: return "Normal"
        default: return "Fast"
        }
    }

    /// Keeps the text field showing the alert speed in whatever unit is currently selected.
    private func syncAlertText() {
        let displayed = settings.unit.convert(fromMph: settings.maxSpeedAlertMph)
        alertSpeedText = String(Int(displayed.rounded()))
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(RunStore())
        .environmentObject(SettingsStore())
}

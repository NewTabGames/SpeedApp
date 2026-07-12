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
                        .animation(.snappy(duration: 0.1), value: location.displaySpeedMph)
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
        settings.unit.convert(fromMph: location.displaySpeedMph)
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

    @State private var batteryStartText: String = ""
    @State private var showEndBatteryPrompt = false
    @State private var batteryEndText: String = ""
    @State private var pendingResult: LocationManager.RecordingResult?
    @FocusState private var batteryFieldFocused: Bool

    var body: some View {
        ZStack {
            backgroundGradient()

            ScrollView {
                VStack(spacing: 20) {
                    statusHeader

                    Text(elapsedString(location.recordingElapsed))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    if settings.batteryTrackingEnabled && !location.isRecording {
                        batteryStartField
                    }

                    InteractiveSpeedChart(
                        samples: location.recordingSamples,
                        unit: settings.unit,
                        accent: settings.accent.color,
                        height: 180,
                        lineStyle: settings.chartLineStyle
                    )
                    .padding(.horizontal)

                    statsGrid

                    controls
                }
            }
        }
        .onChange(of: location.isRecording) { _, isRecording in
            UIApplication.shared.isIdleTimerDisabled = isRecording && settings.keepScreenAwake
        }
        .sheet(isPresented: $showEndBatteryPrompt) {
            endBatterySheet
        }
    }

    // MARK: Header

    private var statusHeader: some View {
        VStack(spacing: 4) {
            Text(statusText)
                .font(.headline)
                .foregroundStyle(statusColor)

            if location.pauseState == .autoPaused {
                Text("Paused automatically — you've stopped moving")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
    }

    private var statusText: String {
        guard location.isRecording else { return "Ready to Record" }
        switch location.pauseState {
        case .running:        return "Recording…"
        case .manuallyPaused: return "Paused"
        case .autoPaused:     return "Auto-Paused"
        }
    }

    private var statusColor: Color {
        guard location.isRecording else { return .secondary }
        return location.isPaused ? .yellow : .red
    }

    // MARK: Battery

    private var batteryStartField: some View {
        HStack {
            Image(systemName: "battery.100")
                .foregroundStyle(.secondary)
            Text("Battery at start")
                .font(.subheadline)
            Spacer()
            TextField("—", text: $batteryStartText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($batteryFieldFocused)
                .frame(width: 50)
            Text("%")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .onAppear {
            if batteryStartText.isEmpty, let last = runStore.lastKnownBatteryPercent {
                batteryStartText = String(Int(last))
            }
        }
    }

    private var endBatterySheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Battery now")
                        Spacer()
                        TextField("—", text: $batteryEndText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Log Battery")
                } footer: {
                    Text("Optional. Logging this on a few rides lets the app estimate your range.")
                }
            }
            .navigationTitle("Ride Finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finishSave(logBattery: false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { finishSave(logBattery: true) }
                }
            }
        }
        .presentationDetents([.height(240)])
    }

    // MARK: Stats

    private var statsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statBlock(title: "CURRENT", value: unitString(location.displaySpeedMph))
                statBlock(title: "MAX", value: unitString(location.recordingMaxMph))
                statBlock(title: "AVG", value: unitString(location.recordingAvgMph))
            }
            Divider().padding(.vertical, 10)
            HStack(spacing: 0) {
                statBlock(title: "DISTANCE", value: distanceString(location.recordingDistanceMiles))
                statBlock(title: "CLIMB", value: String(format: "%.0f ft", location.recordingElevationGainFt))
                statBlock(title: "DESCENT", value: String(format: "%.0f ft", location.recordingElevationLossFt))
            }
        }
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            if location.isRecording {
                HStack(spacing: 10) {
                    Button {
                        if settings.hapticsEnabled {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        if location.isPaused {
                            location.resumeRecording()
                        } else {
                            location.pauseRecording()
                        }
                    } label: {
                        Label(
                            location.isPaused ? "Resume" : "Pause",
                            systemImage: location.isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        stopAndPrompt()
                    } label: {
                        Text("Stop & Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            } else {
                Button {
                    if settings.hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    batteryFieldFocused = false
                    location.startRecording()
                } label: {
                    Text("Start Recording")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(settings.accent.color)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    // MARK: Actions

    private func stopAndPrompt() {
        if settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        guard let result = location.stopRecording() else { return }
        pendingResult = result

        if settings.batteryTrackingEnabled {
            batteryEndText = ""
            showEndBatteryPrompt = true
        } else {
            finishSave(logBattery: false)
        }
    }

    private func finishSave(logBattery: Bool) {
        showEndBatteryPrompt = false
        guard let result = pendingResult else { return }

        let start = logBattery ? Double(batteryStartText) : nil
        let end = logBattery ? Double(batteryEndText) : nil

        runStore.addRecording(result: result, batteryStart: start, batteryEnd: end)

        pendingResult = nil
        if let end { batteryStartText = String(Int(end)) }
    }

    // MARK: Formatting

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

    @State private var section = 0
    @State private var sort: RecordingSort = .newest
    @State private var searchText = ""
    @State private var showClearConfirmation = false
    @State private var renameTarget: SpeedRecording?
    @State private var renameText = ""
    @State private var shareFile: ShareableFile?
    @State private var exportFailed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $section) {
                    Text("Rides").tag(0)
                    Text("Lifetime").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if section == 0 {
                    ridesList
                } else {
                    LifetimeTotalsView()
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !runStore.recordings.isEmpty {
                        Menu {
                            if section == 0 {
                                Picker("Sort", selection: $sort) {
                                    ForEach(RecordingSort.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
                                Divider()
                            }
                            Button {
                                exportSummaryCSV()
                            } label: {
                                Label("Export All Rides (CSV)", systemImage: "tablecells")
                            }
                            Divider()
                            Button("Clear All", role: .destructive) { requestClear() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .tint(settings.accent.color)
        .alert("Clear History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { runStore.clearAllRecordings() }
        } message: {
            Text("Are you sure you want to clear your history? This will permanently delete all \(runStore.recordings.count) saved recordings and can't be undone.")
        }
        .alert("Rename Ride", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Ride name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let target = renameTarget {
                    runStore.rename(id: target.id, to: renameText)
                }
                renameTarget = nil
            }
        }
        .sheet(item: $shareFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .alert("Export Failed", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't write the CSV file.")
        }
    }

    /// One row per ride — a spreadsheet of your whole riding history.
    private func exportSummaryCSV() {
        do {
            let url = try CSVExporter.ridesSummary(
                recordings: runStore.recordings,
                unit: settings.unit
            )
            shareFile = ShareableFile(url: url)
        } catch {
            exportFailed = true
        }
    }

    private var visibleRecordings: [SpeedRecording] {
        runStore.sorted(by: sort, search: searchText)
    }

    private var ridesList: some View {
        List {
            ForEach(visibleRecordings) { rec in
                NavigationLink(destination: RecordingDetailView(recording: rec)) {
                    rideRow(rec)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        runStore.delete(id: rec.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        renameText = rec.name
                        renameTarget = rec
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search rides")
        .overlay {
            if runStore.recordings.isEmpty {
                ContentUnavailableView(
                    "No Rides Yet",
                    systemImage: "record.circle",
                    description: Text("Start a recording from the Record tab to log your first ride.")
                )
            } else if visibleRecordings.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func rideRow(_ rec: SpeedRecording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rec.displayName)
                .font(.subheadline.weight(.semibold))

            SpeedSparkline(
                samples: rec.samples,
                unit: settings.unit,
                accent: settings.accent.color
            )
            .frame(height: 50)

            HStack(spacing: 14) {
                Text("\(String(format: "%.1f", settings.unit.convertDistance(fromMiles: rec.distanceMiles))) \(settings.unit.distanceUnitLabel)")
                Text("Max \(String(format: "%.0f", settings.unit.convert(fromMph: rec.maxMph)))")
                Text(elapsedLabel(rec.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func requestClear() {
        if settings.confirmBeforeClearing {
            showClearConfirmation = true
        } else {
            runStore.clearAllRecordings()
        }
    }
}

// MARK: - Lifetime Totals

struct LifetimeTotalsView: View {
    @EnvironmentObject var runStore: RunStore
    @EnvironmentObject var settings: SettingsStore

    private var totals: LifetimeTotals { runStore.lifetimeTotals }

    var body: some View {
        if runStore.recordings.isEmpty {
            ContentUnavailableView(
                "Nothing Yet",
                systemImage: "chart.bar",
                description: Text("Your lifetime stats will appear here once you've recorded a ride.")
            )
        } else {
            List {
                Section("All Time") {
                    row("Rides", "\(totals.rideCount)")
                    row("Total Distance", String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: totals.totalDistanceMiles), settings.unit.distanceUnitLabel))
                    row("Total Time", elapsedLabel(totals.totalDurationSeconds))
                    row("Top Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: totals.topSpeedMph), settings.unit.rawValue))
                    row("Average Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: totals.overallAvgMph), settings.unit.rawValue))
                    row("Longest Ride", String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: totals.longestRideMiles), settings.unit.distanceUnitLabel))
                    row("Total Climb", String(format: "%.0f ft", totals.totalElevationGainFt))
                }

                Section {
                    batteryContent
                } header: {
                    Text("Battery & Range")
                } footer: {
                    Text("Estimated from rides where you logged the battery level before and after. More rides make the estimate better.")
                }
            }
        }
    }

    @ViewBuilder
    private var batteryContent: some View {
        if !settings.batteryTrackingEnabled {
            Text("Turn on Battery Tracking in Settings to estimate your range.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let perPercent = runStore.milesPerBatteryPercent,
                  let fullRange = runStore.estimatedFullRangeMiles {
            row("Rides Logged", "\(runStore.batteryRidesLogged)")
            row(
                "Range per 10%",
                String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: perPercent * 10), settings.unit.distanceUnitLabel)
            )
            row(
                "Full Charge Range",
                String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: fullRange), settings.unit.distanceUnitLabel)
            )
        } else {
            let logged = runStore.batteryRidesLogged
            let needed = RunStore.minimumRidesForBatteryEstimate - logged
            VStack(alignment: .leading, spacing: 4) {
                Text("\(logged) of \(RunStore.minimumRidesForBatteryEstimate) rides logged")
                    .font(.subheadline.weight(.medium))
                Text("Log battery on \(needed) more ride\(needed == 1 ? "" : "s") to get a range estimate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

// MARK: - Recording Detail (with route map)

struct RecordingDetailView: View {
    let recording: SpeedRecording
    @EnvironmentObject var settings: SettingsStore

    @State private var shareFile: ShareableFile?
    @State private var isExporting = false
    @State private var exportErrorMessage: String?

    private var coordinates: [CLLocationCoordinate2D] {
        recording.samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var cameraPosition: MapCameraPosition {
        guard !coordinates.isEmpty else { return .automatic }
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
                            Marker("Start", coordinate: first).tint(.green)
                        }
                        if let last = coordinates.last {
                            Marker("End", coordinate: last).tint(.red)
                        }
                    }
                    .frame(height: 260)
                    .mapStyle(settings.mapStyle.mapStyle)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    NavigationLink(destination: TripReplayView(recording: recording)) {
                        Label("Replay Ride", systemImage: "play.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(settings.accent.color.opacity(0.15))
                            .foregroundStyle(settings.accent.color)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                } else {
                    Text("Not enough GPS data to draw a route for this ride.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    statRow("Date", recording.date.formatted(date: .abbreviated, time: .shortened))
                    statRow("Duration", elapsedLabel(recording.duration))
                    statRow("Distance", String(format: "%.2f %@", settings.unit.convertDistance(fromMiles: recording.distanceMiles), settings.unit.distanceUnitLabel))
                    statRow("Max Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: recording.maxMph), settings.unit.rawValue))
                    statRow("Avg Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: recording.avgMph), settings.unit.rawValue))
                    statRow("Elevation Gain", String(format: "%.0f ft", recording.elevationGainFt))
                    statRow("Elevation Loss", String(format: "%.0f ft", recording.elevationLossFt))
                    if let used = recording.batteryUsedPercent {
                        statRow("Battery Used", String(format: "%.0f%%", used))
                    }
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
                            lineStyle: settings.chartLineStyle,
                            startDate: recording.date
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
        .navigationTitle(recording.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isExporting {
                    ProgressView()
                } else {
                    Menu {
                        if coordinates.count > 1 {
                            Button {
                                exportRoute()
                            } label: {
                                Label("Route Map (PNG)", systemImage: "map")
                            }
                        }
                        Button {
                            exportSamplesCSV()
                        } label: {
                            Label("Ride Data (CSV)", systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(item: $shareFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    /// Renders the route map to a PNG and opens the share sheet.
    /// Snapshotting downloads map tiles, so it's async and can take a second or two.
    private func exportRoute() {
        isExporting = true
        MapExporter.exportRouteImage(
            recording: recording,
            unit: settings.unit,
            accent: settings.accent.uiColor,
            mapType: settings.mapStyle.mkMapType
        ) { result in
            isExporting = false
            switch result {
            case .success(let url):
                shareFile = ShareableFile(url: url)
            case .failure(let error):
                if let exportError = error as? MapExporter.ExportError,
                   case .notEnoughPoints = exportError {
                    exportErrorMessage = "This ride doesn't have enough GPS points to draw a route."
                } else {
                    exportErrorMessage = "Something went wrong rendering the map. Check your connection and try again."
                }
            }
        }
    }

    /// One row per GPS reading. Raw data for charting or analysis outside the app.
    private func exportSamplesCSV() {
        do {
            let url = try CSVExporter.rideSamples(recording: recording, unit: settings.unit)
            shareFile = ShareableFile(url: url)
        } catch {
            exportErrorMessage = "This ride has no GPS data to export."
        }
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
}

// MARK: - Settings Tab

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var runStore: RunStore
    @EnvironmentObject var location: LocationManager

    @State private var alertSpeedText: String = ""
    @State private var showClearConfirmation = false
    @State private var showAbout = false
    @FocusState private var alertFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showAbout = true
                    } label: {
                        Label("What This App Does", systemImage: "questionmark.circle")
                    }
                }

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

                Section("Graphs") {
                    Picker("Graph Line Style", selection: $settings.chartLineStyle) {
                        ForEach(ChartLineStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
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
                    Toggle("Auto-Pause When Stopped", isOn: $settings.autoPauseEnabled)
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Automatically pauses the recording after about 4 seconds below 1.5 mph, and resumes when you start moving again. Time spent stopped won't count toward your ride duration, and stops won't drag down your average speed. Turn this off if you want your ride timed door-to-door including every red light.")
                }

                Section {
                    Toggle("Battery Tracking", isOn: $settings.batteryTrackingEnabled)
                } header: {
                    Text("Battery")
                } footer: {
                    Text("Adds an optional battery percentage field before and after each ride. After \(RunStore.minimumRidesForBatteryEstimate) logged rides, the app estimates how far you can go per charge. See it under History → Lifetime.")
                }

                Section {
                    Toggle("Keep Screen Awake While Recording", isOn: $settings.keepScreenAwake)
                    Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)
                    Toggle("Confirm Before Clearing", isOn: $settings.confirmBeforeClearing)
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("When on, you'll be asked to confirm before deleting all your recordings.")
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
                        requestClear()
                    }
                } header: {
                    Text("Data")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.1")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Saved Rides")
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
        .tint(settings.accent.color)
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .alert("Clear History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { runStore.clearAllRecordings() }
        } message: {
            Text("Are you sure you want to clear your history? This will permanently delete all \(runStore.recordings.count) saved recordings and can't be undone.")
        }
    }

    private func requestClear() {
        if settings.confirmBeforeClearing {
            showClearConfirmation = true
        } else {
            runStore.clearAllRecordings()
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

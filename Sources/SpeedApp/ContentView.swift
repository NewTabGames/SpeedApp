import SwiftUI
import Charts
import UIKit
import MapKit
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SpeedView()
                .tabItem { Label("Speed", systemImage: "speedometer") }
                .tag(0)
            RecordView()
                .tabItem { Label("Record", systemImage: "record.circle") }
                .tag(1)
            MapTabView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(2)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(settings.accent.color)
        .onChange(of: selectedTab) { _, _ in
            Haptics.selection()
        }
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

/// Page background for the Speed and Record tabs. These were originally dark-only, so the
/// gradient was hardcoded black — which meant Light mode had nothing to switch to. Now it
/// follows the color scheme.
private struct BackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors: [Color] = colorScheme == .dark
            ? [Color.black, Color(red: 0.08, green: 0.08, blue: 0.1)]
            : [Color(red: 0.97, green: 0.97, blue: 0.98), Color(red: 0.90, green: 0.91, blue: 0.94)]

        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

private func backgroundGradient() -> some View {
    BackgroundGradient()
}

/// Translucent fill for the stat cards. A white tint is invisible on a light background,
/// so this flips to a dark tint in light mode.
private struct CardFill: View {
    @Environment(\.colorScheme) private var colorScheme
    var opacity: Double = 0.05

    var body: some View {
        (colorScheme == .dark ? Color.white : Color.black)
            .opacity(colorScheme == .dark ? opacity : opacity * 1.4)
    }
}

/// Warns when location permission isn't sufficient for what the rider is trying to do.
///
/// "While Using" is the dangerous case: everything looks fine until the screen locks, and
/// then GPS silently stops and the ride is ruined. Better to say so up front, with a button
/// that goes straight to the right place in iOS Settings.
struct LocationPermissionBanner: View {
    @EnvironmentObject var location: LocationManager

    var body: some View {
        if location.isLocationDenied {
            banner(
                icon: "location.slash.fill",
                tint: .red,
                title: "Location is off",
                message: "This app can't measure speed without it. Turn on location access in Settings."
            )
        } else if location.needsAlwaysPermission {
            banner(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Set location to \"Always\"",
                message: "Right now it's set to \"While Using the App\". Recording will stop the moment your screen locks. Change it to Always so rides keep tracking in your pocket."
            )
        }
    }

    private func banner(icon: String, tint: Color, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.tap()
                openSettings()
            } label: {
                Text("Open Settings")
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    /// Deep-links to this app's own page in iOS Settings, where the Location row lives.
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Speed Tab

struct SpeedView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var settings: SettingsStore
    @State private var speedAlertArmed = true
    @State private var showSpeedAlert = false

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

                LocationPermissionBanner()

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
                .background(CardFill())
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                Button("Reset Max Speed") {
                    Haptics.impact()
                    location.resetMaxSpeed()
                    speedAlertArmed = true
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
        .alert("Speed Alert", isPresented: $showSpeedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You've exceeded your set speed limit of \(String(format: "%.0f", settings.unit.convert(fromMph: settings.maxSpeedAlertMph))) \(settings.unit.rawValue).")
        }
        .onChange(of: location.speedMph) { _, newValue in
            guard settings.maxSpeedAlertEnabled else { return }
            if newValue >= settings.maxSpeedAlertMph {
                // Fire once per crossing; stays quiet while you remain over the limit.
                if speedAlertArmed {
                    speedAlertArmed = false
                    showSpeedAlert = true
                    Haptics.warning()
                }
            } else {
                // Back under the limit — re-arm so the next crossing alerts again.
                speedAlertArmed = true
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
    @EnvironmentObject var heatmapStore: HeatmapStore

    @State private var batteryStartText: String = ""
    @State private var showEndBatteryPrompt = false
    @State private var batteryEndText: String = ""
    @State private var pendingResult: LocationManager.RecordingResult?
    @State private var newRecords: [String] = []
    @FocusState private var batteryFieldFocused: Bool

    var body: some View {
        ZStack {
            backgroundGradient()

            ScrollView {
                VStack(spacing: 20) {
                    statusHeader

                    LocationPermissionBanner()

                    Text(elapsedString(location.recordingElapsed))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    if settings.vehicleMode.usesBattery
                        && settings.batteryTrackingEnabled
                        && !location.isRecording {
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
        .onAppear {
            // The Speed tab normally kicks off GPS, but there's no guarantee the user visited
            // it first. Without this, going straight to Record on a fresh install would record
            // a ride with no permission prompt and zero GPS data.
            location.requestPermission()
            location.start()
        }
        .alert("New Record!", isPresented: Binding(
            get: { !newRecords.isEmpty },
            set: { if !$0 { newRecords = [] } }
        )) {
            Button("Nice") { newRecords = [] }
        } message: {
            Text("That ride set a new personal best for \(newRecords.joined(separator: ", ")). See it under History → Trends.")
        }
        .sheet(isPresented: $showEndBatteryPrompt, onDismiss: {
            // Safety net: if the sheet was swiped away instead of using Skip/Save, the ride
            // would otherwise be silently lost. Save it without battery info.
            if pendingResult != nil {
                finishSave(logBattery: false)
            }
        }) {
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
        .background(CardFill())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .onAppear {
            if batteryStartText.isEmpty,
               let last = runStore.lastKnownBatteryPercent(for: settings.vehicleMode) {
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
        .background(CardFill())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            if location.isRecording {
                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
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
                        .background(CardFill(opacity: 0.12))
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
                    Haptics.impact()
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
        Haptics.impact()
        guard let result = location.stopRecording() else { return }
        pendingResult = result

        if settings.vehicleMode.usesBattery && settings.batteryTrackingEnabled {
            batteryEndText = ""
            showEndBatteryPrompt = true
        } else {
            finishSave(logBattery: false)
        }
    }

    private func finishSave(logBattery: Bool) {
        showEndBatteryPrompt = false
        guard let result = pendingResult else { return }
        pendingResult = nil

        let start = logBattery ? Double(batteryStartText) : nil
        let end = logBattery ? Double(batteryEndText) : nil

        // Use the returned ride rather than assuming recordings.first — a ride under 2
        // seconds isn't saved at all, and we'd otherwise be inspecting the *previous* ride
        // and could congratulate the rider for a record they didn't just set.
        let saved = runStore.addRecording(
            result: result,
            mode: settings.vehicleMode,
            batteryStart: start,
            batteryEnd: end
        )

        if let end { batteryStartText = String(Int(end)) }

        guard let saved else { return }
        Haptics.success()

        // Regenerate the heatmap now that there's a new ride. Runs off the main thread.
        heatmapStore.rebuild(from: runStore.recordings)

        let broken = runStore.recordsBroken(by: saved)
        guard !broken.isEmpty else { return }

        // Presenting an alert while the battery sheet is still animating away tends to get
        // swallowed by SwiftUI, so wait for the dismissal to finish first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            newRecords = broken
        }
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
    @EnvironmentObject var heatmapStore: HeatmapStore

    @State private var section = 0
    @State private var sort: RecordingSort = .newest
    @State private var searchText = ""
    @State private var showClearConfirmation = false
    @State private var renameTarget: SpeedRecording?
    @State private var renameText = ""
    @State private var shareFile: ShareableFile?
    @State private var exportFailed = false
    /// nil = show every vehicle's rides.
    @State private var modeFilter: VehicleMode? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if runStore.loadFailed {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Couldn't read your saved rides", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("The file was kept and renamed. Find it in the Files app under On My iPhone, and send it over if you want it recovered. New rides will save normally.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Picker("", selection: $section) {
                    Text("Rides").tag(0)
                    Text("Trends").tag(1)
                    Text("Lifetime").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if section == 0 {
                    ridesList
                } else if section == 1 {
                    TrendsView()
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
                                // Nested menus with explicit buttons rather than inline
                                // Pickers. A Picker placed directly inside a Menu — especially
                                // one with an optional selection — makes the menu re-render on
                                // a loop, which shows up as the whole menu visibly pulsing.
                                Menu {
                                    ForEach(RecordingSort.allCases) { option in
                                        Button {
                                            sort = option
                                        } label: {
                                            if sort == option {
                                                Label(option.rawValue, systemImage: "checkmark")
                                            } else {
                                                Text(option.rawValue)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Sort: \(sort.rawValue)", systemImage: "arrow.up.arrow.down")
                                }

                                if runStore.modesWithRides.count > 1 {
                                    Menu {
                                        Button {
                                            modeFilter = nil
                                        } label: {
                                            if modeFilter == nil {
                                                Label("All Vehicles", systemImage: "checkmark")
                                            } else {
                                                Text("All Vehicles")
                                            }
                                        }
                                        ForEach(runStore.modesWithRides) { mode in
                                            Button {
                                                modeFilter = mode
                                            } label: {
                                                if modeFilter == mode {
                                                    Label(mode.rawValue, systemImage: "checkmark")
                                                } else {
                                                    Label(mode.rawValue, systemImage: mode.icon)
                                                }
                                            }
                                        }
                                    } label: {
                                        Label(
                                            "Vehicle: \(modeFilter?.rawValue ?? "All")",
                                            systemImage: "car.2"
                                        )
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
            Button("Clear All", role: .destructive) {
                Haptics.warning()
                runStore.clearAllRecordings()
                heatmapStore.clear()
            }
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
                    Haptics.success()
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
        runStore.sorted(by: sort, search: searchText, mode: modeFilter)
    }

    private var ridesList: some View {
        List {
            Section {
                ForEach(visibleRecordings) { rec in
                    NavigationLink(destination: RecordingDetailView(recording: rec)) {
                        rideRow(rec)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Haptics.warning()
                            runStore.delete(id: rec.id)
                            heatmapStore.rebuild(from: runStore.recordings)
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
                    .contextMenu {
                        // Quick vehicle reassignment without opening the ride — for when
                        // you recorded under the wrong one.
                        Menu {
                            ForEach(VehicleMode.allCases) { mode in
                                Button {
                                    Haptics.selection()
                                    runStore.setMode(id: rec.id, to: mode)
                                } label: {
                                    if rec.mode == mode {
                                        Label(mode.rawValue, systemImage: "checkmark")
                                    } else {
                                        Label(mode.rawValue, systemImage: mode.icon)
                                    }
                                }
                            }
                        } label: {
                            Label("Change Vehicle", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            } footer: {
                if !visibleRecordings.isEmpty {
                    Text("Swipe a ride to rename or delete it. Press and hold to change its vehicle.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
            HStack(spacing: 6) {
                Image(systemName: rec.mode.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(rec.displayName)
                    .font(.subheadline.weight(.semibold))
            }

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

    /// nil = totals across every vehicle.
    @State private var scope: VehicleMode? = nil

    private var totals: LifetimeTotals { runStore.lifetimeTotals(for: scope) }

    private var scopeLabel: String {
        scope?.rawValue ?? "All Vehicles"
    }

    var body: some View {
        if runStore.recordings.isEmpty {
            ContentUnavailableView(
                "Nothing Yet",
                systemImage: "chart.bar",
                description: Text("Your lifetime stats will appear here once you've recorded a ride.")
            )
        } else {
            List {
                // Only worth offering a scope picker once there's more than one vehicle logged.
                if runStore.modesWithRides.count > 1 {
                    Section {
                        Picker("Vehicle", selection: $scope) {
                            Text("All Vehicles").tag(VehicleMode?.none)
                            ForEach(runStore.modesWithRides) { mode in
                                Label(mode.rawValue, systemImage: mode.icon)
                                    .tag(VehicleMode?.some(mode))
                            }
                        }
                    }
                }

                Section(scopeLabel) {
                    row("Rides", "\(totals.rideCount)")
                    row("Total Distance", String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: totals.totalDistanceMiles), settings.unit.distanceUnitLabel))
                    row("Total Time", elapsedLabel(totals.totalDurationSeconds))
                    row("Top Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: totals.topSpeedMph), settings.unit.rawValue))
                    row("Average Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: totals.overallAvgMph), settings.unit.rawValue))
                    row("Longest Ride", String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: totals.longestRideMiles), settings.unit.distanceUnitLabel))
                    row("Total Climb", String(format: "%.0f ft", totals.totalElevationGainFt))
                }

                // Per-vehicle breakdown, only when viewing everything together.
                if scope == nil && runStore.modesWithRides.count > 1 {
                    Section("By Vehicle") {
                        ForEach(runStore.modesWithRides) { mode in
                            let t = runStore.lifetimeTotals(for: mode)
                            HStack {
                                Label(mode.rawValue, systemImage: mode.icon)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(t.rideCount) · \(String(format: "%.1f", settings.unit.convertDistance(fromMiles: t.totalDistanceMiles))) \(settings.unit.distanceUnitLabel)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                // Battery only exists for electric vehicles, so this section only appears
                // when the scope is one (or when the current vehicle has a battery).
                if let batteryMode {
                    Section {
                        batteryContent(for: batteryMode)
                    } header: {
                        Text("\(batteryMode.rawValue) Battery & Range")
                    } footer: {
                        Text("Estimated from \(batteryMode.rawValue.lowercased()) rides where you logged the battery level before and after. More rides make the estimate better.")
                    }
                }
            }
        }
    }

    /// Which vehicle's battery stats to show, if any. When scoped to a specific vehicle we
    /// use that; otherwise we fall back to the currently-selected one — but only if it
    /// actually has a battery.
    private var batteryMode: VehicleMode? {
        let candidate = scope ?? settings.vehicleMode
        return candidate.usesBattery ? candidate : nil
    }

    @ViewBuilder
    private func batteryContent(for mode: VehicleMode) -> some View {
        if !settings.batteryTrackingEnabled {
            Text("Turn on Battery Tracking in Settings to estimate your range.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let perPercent = runStore.milesPerBatteryPercent(for: mode),
                  let fullRange = runStore.estimatedFullRangeMiles(for: mode) {
            row("Rides Logged", "\(runStore.batteryRidesLogged(for: mode))")
            row(
                "Range per 10%",
                String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: perPercent * 10), settings.unit.distanceUnitLabel)
            )
            row(
                "Full Charge Range",
                String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: fullRange), settings.unit.distanceUnitLabel)
            )
        } else {
            let logged = runStore.batteryRidesLogged(for: mode)
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
    @EnvironmentObject var runStore: RunStore

    @State private var shareFile: ShareableFile?
    @State private var isExporting = false
    @State private var exportErrorMessage: String?

    /// The ride's current vehicle, read live from the store. `recording` is an immutable
    /// snapshot taken when this screen opened, so after a reassignment it would still show
    /// the old vehicle without this lookup.
    private var currentMode: VehicleMode {
        runStore.recordings.first(where: { $0.id == recording.id })?.mode ?? recording.mode
    }

    private var coordinates: [CLLocationCoordinate2D] {
        recording.samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if coordinates.count > 1 {
                    RouteMap(
                        recording: recording,
                        accent: settings.accent,
                        colorBySpeed: settings.colorRouteBySpeed,
                        mapStyle: settings.mapStyle.mapStyle
                    )
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    if settings.colorRouteBySpeed {
                        SpeedLegend(
                            accent: settings.accent,
                            minLabel: String(format: "%.0f", settings.unit.convert(fromMph: recording.samples.map(\.mph).min() ?? 0)),
                            maxLabel: String(format: "%.0f %@", settings.unit.convert(fromMph: recording.samples.map(\.mph).max() ?? 0), settings.unit.rawValue)
                        )
                        .padding(.horizontal)
                    }

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
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Reassign the ride's vehicle — for when you recorded under the wrong one.
                // Buttons with checkmarks rather than a Picker: a Picker directly inside a
                // Menu causes the visible pulsing glitch fixed in the History menu.
                Menu {
                    ForEach(VehicleMode.allCases) { mode in
                        Button {
                            Haptics.selection()
                            runStore.setMode(id: recording.id, to: mode)
                        } label: {
                            if currentMode == mode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Label(mode.rawValue, systemImage: mode.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: currentMode.icon)
                }

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
            accentTheme: settings.accent,
            colorBySpeed: settings.colorRouteBySpeed,
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
    @EnvironmentObject var heatmapStore: HeatmapStore

    @State private var alertSpeedText: String = ""
    @State private var showClearConfirmation = false
    @State private var showAbout = false
    @State private var showImporter = false
    @State private var backupFile: ShareableFile?
    @State private var backupMessage: String?
    @FocusState private var alertFieldFocused: Bool

    /// Installed voices, loaded once when the view appears.
    @State private var availableVoices: [VoiceCatalog.Voice] = []
    /// A dedicated synthesizer for the Settings preview button, separate from navigation.
    private let previewSynth = AVSpeechSynthesizer()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("Location Access", systemImage: locationStatusIcon)
                            .foregroundStyle(locationStatusColor)
                        Spacer()
                        Text(locationStatusText)
                            .foregroundStyle(.secondary)
                    }
                    if !location.hasAlwaysPermission {
                        Button {
                            Haptics.tap()
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Fix in iOS Settings", systemImage: "arrow.up.forward.app")
                        }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Recording needs \"Always\" to keep tracking when your screen locks or the app is in your pocket. With \"While Using the App\", GPS stops the moment you lock the phone and your ride will be cut short.")
                }

                Section {
                    Picker("Vehicle", selection: $settings.vehicleMode) {
                        ForEach(VehicleMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                } header: {
                    Text("Vehicle")
                } footer: {
                    Text("Each vehicle keeps its own speed alert, auto-pause, GPS, and smoothing settings — changing the car's doesn't affect the scooter's. Walking also uses footpath routes instead of roads.")
                }

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

                Section {
                    Picker("Map Style", selection: $settings.mapStyle) {
                        ForEach(MapStyleOption.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    Toggle("Color Route by Speed", isOn: $settings.colorRouteBySpeed)
                } header: {
                    Text("Map")
                } footer: {
                    Text("When on, saved routes are shaded from pale (slow) to deep (fast) in your accent color. When off, the route is a single solid color.")
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
                    Text("\(settings.vehicleMode.rawValue) — Reading Behavior")
                } footer: {
                    Text("Responsive reacts fastest to speed changes but may jitter. Battery Saver reduces GPS precision to extend battery life on longer rides.")
                }

                Section {
                    Toggle("Auto-Pause When Stopped", isOn: $settings.autoPauseEnabled)

                    if settings.autoPauseEnabled {
                        HStack {
                            Text("Pause below")
                            Spacer()
                            Text(String(format: "%.1f %@",
                                        settings.unit.convert(fromMph: settings.autoPauseSpeedMph),
                                        settings.unit.rawValue))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.autoPauseSpeedMph, in: 0.5...5, step: 0.5)

                        HStack {
                            Text("After")
                            Spacer()
                            Text("\(Int(settings.autoPauseDelaySeconds)) sec")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.autoPauseDelaySeconds, in: 2...15, step: 1)
                    }
                } header: {
                    Text("\(settings.vehicleMode.rawValue) — Recording")
                } footer: {
                    Text("Automatically pauses the recording once you've been below the set speed for the set time, and resumes when you start moving again. Time spent stopped won't count toward your ride duration, and stops won't drag down your average speed. Turn this off if you want your ride timed door-to-door including every red light.")
                }

                // Battery tracking only makes sense for electric vehicles. Cars and
                // motorcycles report their own fuel economy; walking has no energy source.
                if settings.vehicleMode.usesBattery {
                    Section {
                        Toggle("Battery Tracking", isOn: $settings.batteryTrackingEnabled)
                    } header: {
                        Text("Battery")
                    } footer: {
                        Text("Adds an optional battery percentage field before and after each ride. After \(RunStore.minimumRidesForBatteryEstimate) logged rides, the app estimates how far you can go per charge. See it under History → Lifetime.")
                    }
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
                    Picker("Voice", selection: $settings.voiceIdentifier) {
                        Text("System Default").tag(VoiceCatalog.systemDefaultID)
                        ForEach(availableVoices) { voice in
                            Text(voice.label).tag(voice.id)
                        }
                    }

                    Button {
                        previewVoice()
                    } label: {
                        Label("Preview Voice", systemImage: "play.circle")
                    }

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
                    Text("Controls the voice and speed of spoken turn-by-turn directions. More voices — including higher-quality ones — can be downloaded in iOS Settings › Accessibility › Read & Speak › Voices.")
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
                    Text("\(settings.vehicleMode.rawValue) — Safety")
                } footer: {
                    Text("Get a vibration and on-screen alert when you exceed this speed.")
                }

                Section {
                    Button {
                        Haptics.tap()
                        exportBackup()
                    } label: {
                        Label("Back Up Rides", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Haptics.tap()
                        showImporter = true
                    } label: {
                        Label("Restore from Backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Saves all \(runStore.recordings.count) rides to a file you can keep in Files or iCloud Drive. Worth doing before you re-sideload — if the app gets deleted or the signing changes, your rides go with it. Restoring merges: re-importing the same backup won't duplicate anything.")
                }

                Section {
                    Button("Reset \(settings.vehicleMode.rawValue) Settings", role: .destructive) {
                        Haptics.warning()
                        settings.resetCurrentModeSettings()
                    }
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
            .onAppear {
                syncAlertText()
                availableVoices = VoiceCatalog.availableVoices()
            }
            .onChange(of: settings.unit) { _, _ in syncAlertText() }
        }
        .tint(settings.accent.color)
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(item: $backupFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            "Backup",
            isPresented: Binding(
                get: { backupMessage != nil },
                set: { if !$0 { backupMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupMessage ?? "")
        }
        .alert("Clear History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                Haptics.warning()
                runStore.clearAllRecordings()
                heatmapStore.clear()
            }
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

    private func exportBackup() {
        do {
            let url = try BackupManager.exportBackup(recordings: runStore.recordings)
            backupFile = ShareableFile(url: url)
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            backupMessage = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let backup = try BackupManager.readBackup(from: url)
                let outcome = runStore.merge(backup.recordings)
                Haptics.success()
                if outcome.added > 0 {
                    heatmapStore.rebuild(from: runStore.recordings)
                }

                if outcome.added == 0 {
                    backupMessage = "Those \(outcome.skipped) rides are already in your history — nothing to add."
                } else {
                    let skipNote = outcome.skipped > 0
                        ? " \(outcome.skipped) were already there."
                        : ""
                    backupMessage = "Restored \(outcome.added) ride\(outcome.added == 1 ? "" : "s").\(skipNote)"
                }
            } catch {
                backupMessage = error.localizedDescription
            }
        }
    }

    private var locationStatusText: String {
        if location.isLocationDenied { return "Off" }
        if location.needsAlwaysPermission { return "While Using" }
        if location.hasAlwaysPermission { return "Always" }
        return "Not Set"
    }

    private var locationStatusIcon: String {
        if location.hasAlwaysPermission { return "checkmark.circle.fill" }
        if location.isLocationDenied { return "xmark.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var locationStatusColor: Color {
        if location.hasAlwaysPermission { return .green }
        if location.isLocationDenied { return .red }
        return .orange
    }

    private func previewVoice() {
        previewSynth.stopSpeaking(at: .immediate)
        let text = SpeechText.spoken("In 500 feet, turn right onto N Main St.")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = VoiceCatalog.voice(for: settings.voiceIdentifier)
        utterance.rate = Float(settings.voiceSpeechRate)
        previewSynth.speak(utterance)
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

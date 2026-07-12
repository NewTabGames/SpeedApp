import SwiftUI
import Charts

struct GraphDetailView: View {
    let recording: SpeedRecording
    @EnvironmentObject var settings: SettingsStore

    @State private var shareFile: ShareableFile?
    @State private var exportError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InteractiveSpeedChart(
                    samples: recording.samples,
                    unit: settings.unit,
                    accent: settings.accent.color,
                    height: 320
                )
                .padding(.horizontal)
                .padding(.top, 8)

                VStack(spacing: 12) {
                    statRow("Max Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: recording.maxMph), settings.unit.rawValue))
                    statRow("Avg Speed", String(format: "%.0f %@", settings.unit.convert(fromMph: recording.avgMph), settings.unit.rawValue))
                    statRow("Distance", String(format: "%.2f %@", settings.unit.convertDistance(fromMiles: recording.distanceMiles), settings.unit.distanceUnitLabel))
                    statRow("Duration", durationString(recording.duration))
                    statRow("Data Points", "\(recording.samples.count)")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Speed Graph")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    exportGraph()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $shareFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .alert("Couldn't Export Graph", isPresented: $exportError) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Renders the chart (plus a small stats header) to a PNG and opens the share sheet.
    private func exportGraph() {
        let exportView = ExportableGraphImage(recording: recording, settings: settings)
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = UIScreen.main.scale

        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else {
            exportError = true
            return
        }

        let filename = "ride-\(Int(recording.date.timeIntervalSince1970)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            shareFile = ShareableFile(url: url)
        } catch {
            exportError = true
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

    private func durationString(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// A static, non-interactive layout used only for rendering to an exported PNG image.
/// (Kept separate from the on-screen view since the exported image shouldn't include
/// drag-to-inspect UI or navigation chrome.)
private struct ExportableGraphImage: View {
    let recording: SpeedRecording
    let settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ride Summary")
                        .font(.title2.bold())
                    Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Chart(recording.samples) { sample in
                LineMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("Speed", settings.unit.convert(fromMph: sample.mph))
                )
                .foregroundStyle(settings.accent.color)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("Speed", settings.unit.convert(fromMph: sample.mph))
                )
                .foregroundStyle(settings.accent.color.opacity(0.15))
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 260)
            .chartYAxisLabel(settings.unit.rawValue.lowercased())

            HStack(spacing: 24) {
                statBlock("MAX", String(format: "%.0f %@", settings.unit.convert(fromMph: recording.maxMph), settings.unit.rawValue))
                statBlock("AVG", String(format: "%.0f %@", settings.unit.convert(fromMph: recording.avgMph), settings.unit.rawValue))
                statBlock("DIST", String(format: "%.2f %@", settings.unit.convertDistance(fromMiles: recording.distanceMiles), settings.unit.distanceUnitLabel))
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(.systemBackground))
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

import SwiftUI
import Charts
import UIKit

/// Wraps a URL so it can be used with .sheet(item:), which requires Identifiable.
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin wrapper around UIActivityViewController so we can trigger the native share sheet from SwiftUI.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Formats elapsed seconds into something readable (2:05, or 1:12:30 for long rides).
/// Chart axes store raw seconds, which is meaningless to look at ("750" is 12.5 minutes).
func elapsedLabel(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

/// Thins a sample array down to a bounded number of evenly-spaced points for drawing.
///
/// At one GPS fix per second, an hour-long ride produces ~3,600 samples. Rendering all of
/// them is wasted work — the drawn line looks identical — and it gets genuinely slow once
/// several recordings are on screen at once (like the History list). The last sample is
/// always kept so a live recording still tracks the present moment.
///
/// This is display-only. The full-resolution data is never modified.
func downsampled(_ samples: [SpeedSample], maxPoints: Int) -> [SpeedSample] {
    guard samples.count > maxPoints, maxPoints > 0 else { return samples }

    let stride = Double(samples.count) / Double(maxPoints)
    var thinned: [SpeedSample] = []
    thinned.reserveCapacity(maxPoints + 1)

    for i in 0..<maxPoints {
        let index = Int(Double(i) * stride)
        if index < samples.count {
            thinned.append(samples[index])
        }
    }
    if let last = samples.last, thinned.last?.offsetSeconds != last.offsetSeconds {
        thinned.append(last)
    }
    return thinned
}

/// A compact, non-interactive speed line for list rows. Heavily downsampled since it's
/// only a few points tall and many of them render at once.
struct SpeedSparkline: View {
    let samples: [SpeedSample]
    let unit: SpeedUnit
    let accent: Color

    var body: some View {
        Chart(downsampled(samples, maxPoints: 60)) { sample in
            LineMark(
                x: .value("Time", sample.offsetSeconds),
                y: .value("Speed", unit.convert(fromMph: sample.mph))
            )
            .foregroundStyle(accent)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
struct InteractiveSpeedChart: View {
    let samples: [SpeedSample]
    let unit: SpeedUnit
    let accent: Color
    var height: CGFloat = 220
    var showAxes: Bool = true
    var lineStyle: ChartLineStyle = .smooth
    /// When set (i.e. for a saved ride), the drag readout also shows the time of day.
    /// Live recordings leave this nil since "now" isn't meaningful to display.
    var startDate: Date? = nil

    @State private var selectedTime: Double?

    /// Drawn at reduced resolution for performance. Drag-to-inspect still reads from the
    /// full-resolution `samples` array, so inspection stays exact.
    private var displaySamples: [SpeedSample] {
        downsampled(samples, maxPoints: 250)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedTime, let nearest = nearestSample(to: selectedTime) {
                HStack(spacing: 6) {
                    Text(String(format: "%.0f %@", unit.convert(fromMph: nearest.mph), unit.rawValue))
                        .font(.headline)
                        .foregroundStyle(accent)
                    Text("at \(elapsedLabel(nearest.offsetSeconds))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    // For a saved ride we know when it started, so we can also show the
                    // actual time of day this moment happened.
                    if let startDate {
                        Text("(\(clockLabel(start: startDate, offset: nearest.offsetSeconds)))")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .transition(.opacity)
            } else if showAxes && samples.count >= 2 {
                // Only worth prompting once there's an actual line to drag across — a
                // just-started recording has too few points to inspect.
                Text("Drag across the graph to inspect a point")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Chart(displaySamples) { sample in
                LineMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("Speed", unit.convert(fromMph: sample.mph))
                )
                .foregroundStyle(accent)
                .interpolationMethod(lineStyle == .smooth ? .catmullRom : .linear)

                AreaMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("Speed", unit.convert(fromMph: sample.mph))
                )
                .foregroundStyle(accent.opacity(0.12))
                .interpolationMethod(lineStyle == .smooth ? .catmullRom : .linear)

                if let selectedTime, let nearest = nearestSample(to: selectedTime) {
                    RuleMark(x: .value("Selected", nearest.offsetSeconds))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", nearest.offsetSeconds),
                        y: .value("Speed", unit.convert(fromMph: nearest.mph))
                    )
                    .foregroundStyle(accent)
                    .symbolSize(80)
                }
            }
            .chartXSelection(value: $selectedTime)
            .frame(height: height)
            .chartXAxis {
                if showAxes {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(elapsedLabel(seconds))
                            }
                        }
                    }
                }
            }
            .chartXAxisLabel(showAxes ? "elapsed time" : "")
            .chartYAxis {
                if showAxes {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel(format: FloatingPointFormatStyle<Double>().precision(.fractionLength(0)))
                    }
                }
            }
            .chartYAxisLabel(showAxes ? unit.rawValue.lowercased() : "")
            // GPS only delivers a fix about once per second, so without this the line
            // would visibly jump each time a point lands. Animating the data change
            // makes the chart glide between fixes instead.
            .animation(.easeInOut(duration: 0.9), value: samples.count)
        }
    }

    private func nearestSample(to time: Double) -> SpeedSample? {
        samples.min(by: { abs($0.offsetSeconds - time) < abs($1.offsetSeconds - time) })
    }

    private func clockLabel(start: Date, offset: Double) -> String {
        let moment = start.addingTimeInterval(offset)
        return moment.formatted(date: .omitted, time: .shortened)
    }
}

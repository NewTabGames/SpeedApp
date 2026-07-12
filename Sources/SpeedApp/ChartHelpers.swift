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

    @State private var selectedTime: Double?

    /// Drawn at reduced resolution for performance. Drag-to-inspect still reads from the
    /// full-resolution `samples` array, so inspection stays exact.
    private var displaySamples: [SpeedSample] {
        downsampled(samples, maxPoints: 250)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedTime, let nearest = nearestSample(to: selectedTime) {
                HStack {
                    Text(String(format: "%.0f %@", unit.convert(fromMph: nearest.mph), unit.rawValue))
                        .font(.headline)
                        .foregroundStyle(accent)
                    Text("at " + timeString(nearest.offsetSeconds))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if showAxes {
                Text("Drag across the graph to inspect a point")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .chartXAxis(showAxes ? .visible : .hidden)
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

    private func timeString(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

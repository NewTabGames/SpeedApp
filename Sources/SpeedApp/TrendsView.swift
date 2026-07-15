import SwiftUI
import Charts

/// Riding trends over time, plus personal records.
struct TrendsView: View {
    @EnvironmentObject var runStore: RunStore
    @EnvironmentObject var settings: SettingsStore

    @State private var period: StatsPeriod = .weekly
    /// Records default to the current vehicle — comparing a car's top speed to a scooter's
    /// isn't a meaningful record, it's just a faster vehicle.
    @State private var scope: VehicleMode?
    /// Seeds `scope` once. Without this, returning to the tab would keep re-applying the
    /// default and quietly undo the rider choosing "All Vehicles".
    @State private var didSeedScope = false

    private var buckets: [StatsBucket] {
        runStore.buckets(period: period, mode: scope)
    }

    private var records: PersonalRecords {
        runStore.personalRecords(for: scope)
    }

    /// X-axis categories, in chronological order.
    private var bucketLabels: [String] {
        buckets.map { period.label(for: $0.start) }
    }

    var body: some View {
        Group {
            if runStore.recordings.isEmpty {
                ContentUnavailableView(
                    "Nothing Yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Record a few rides and your trends and records will show up here.")
                )
            } else {
                List {
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

                    distanceSection
                    ridesSection
                    recordsSection
                }
            }
        }
        .onAppear {
            // Start scoped to whatever vehicle they're currently using, if they've ridden it.
            guard !didSeedScope else { return }
            didSeedScope = true
            if runStore.modesWithRides.contains(settings.vehicleMode) {
                scope = settings.vehicleMode
            }
        }
    }

    // MARK: Distance chart

    private var distanceSection: some View {
        Section {
            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Period", period.label(for: bucket.start)),
                    y: .value("Distance", settings.unit.convertDistance(fromMiles: bucket.distanceMiles))
                )
                .foregroundStyle(settings.accent.color)
                .cornerRadius(3)
            }
            .frame(height: 180)
            .chartYAxisLabel(settings.unit.distanceUnitLabel)
            // String x-values are categorical, and Charts doesn't promise to keep them in
            // data order. Pinning the domain guarantees the bars stay chronological.
            .chartXScale(domain: bucketLabels)
            .padding(.vertical, 6)

            if let best = buckets.max(by: { $0.distanceMiles < $1.distanceMiles }),
               best.distanceMiles > 0 {
                row(
                    "Best \(period == .weekly ? "week" : "month")",
                    String(format: "%.1f %@",
                           settings.unit.convertDistance(fromMiles: best.distanceMiles),
                           settings.unit.distanceUnitLabel)
                )
            }
        } header: {
            Text("Distance")
        } footer: {
            Text("Periods with no rides show as zero, so gaps in your riding are visible rather than hidden.")
        }
    }

    // MARK: Rides chart

    private var ridesSection: some View {
        Section("Rides") {
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Period", period.label(for: bucket.start)),
                    y: .value("Rides", bucket.rideCount)
                )
                .foregroundStyle(settings.accent.color.opacity(0.7))
                .cornerRadius(3)
            }
            .frame(height: 140)
            .chartXScale(domain: bucketLabels)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>().precision(.fractionLength(0)))
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: Records

    @ViewBuilder
    private var recordsSection: some View {
        if !records.isEmpty {
            Section {
                if let r = records.fastest {
                    recordRow(
                        "Top Speed",
                        String(format: "%.0f %@", settings.unit.convert(fromMph: r.maxMph), settings.unit.rawValue),
                        icon: "flame.fill",
                        ride: r
                    )
                }
                if let r = records.farthest {
                    recordRow(
                        "Longest Distance",
                        String(format: "%.1f %@", settings.unit.convertDistance(fromMiles: r.distanceMiles), settings.unit.distanceUnitLabel),
                        icon: "arrow.left.and.right",
                        ride: r
                    )
                }
                if let r = records.longest {
                    recordRow(
                        "Longest Ride",
                        elapsedLabel(r.duration),
                        icon: "clock.fill",
                        ride: r
                    )
                }
                if let r = records.biggestClimb, r.elevationGainFt > 10 {
                    recordRow(
                        "Biggest Climb",
                        String(format: "%.0f ft", r.elevationGainFt),
                        icon: "mountain.2.fill",
                        ride: r
                    )
                }
                if records.mostRidesInAWeek > 1 {
                    row("Most Rides in a Week", "\(records.mostRidesInAWeek)")
                }
            } header: {
                Text("Personal Records")
            } footer: {
                Text("Tap a record to open that ride.")
            }
        }
    }

    private func recordRow(_ title: String, _ value: String, icon: String, ride: SpeedRecording) -> some View {
        NavigationLink(destination: RecordingDetailView(recording: ride)) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(settings.accent.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(ride.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
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

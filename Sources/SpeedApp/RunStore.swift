import Foundation
import Combine

struct SpeedRecording: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var duration: Double
    var maxMph: Double
    var avgMph: Double
    var distanceMiles: Double
    var samples: [SpeedSample]

    // Added after v2.0 — defaults keep older saved rides decodable.
    var name: String = ""
    var elevationGainFt: Double = 0
    var elevationLossFt: Double = 0
    /// Scooter battery percentage at the start/end of the ride, if the rider logged it.
    var batteryStartPercent: Double?
    var batteryEndPercent: Double?

    /// Falls back to the date when the rider hasn't given the ride a name.
    var displayName: String {
        name.isEmpty ? date.formatted(date: .abbreviated, time: .shortened) : name
    }

    var batteryUsedPercent: Double? {
        guard let start = batteryStartPercent, let end = batteryEndPercent, start > end else { return nil }
        return start - end
    }

    static func == (lhs: SpeedRecording, rhs: SpeedRecording) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

/// Aggregate stats across every saved ride.
struct LifetimeTotals {
    var rideCount: Int = 0
    var totalDistanceMiles: Double = 0
    var totalDurationSeconds: Double = 0
    var topSpeedMph: Double = 0
    var totalElevationGainFt: Double = 0
    /// Distance divided by time — a true overall average, not an average of averages.
    var overallAvgMph: Double = 0
    var longestRideMiles: Double = 0
}

enum RecordingSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case farthest = "Farthest"
    case fastest = "Fastest"
    case longest = "Longest Time"
    var id: String { rawValue }
}

final class RunStore: ObservableObject {
    @Published private(set) var recordings: [SpeedRecording] = []

    /// Recordings are stored as a JSON file rather than in UserDefaults.
    /// UserDefaults is for small preferences and is loaded into memory at launch —
    /// a handful of hour-long rides is megabytes of sample data, which does not belong there.
    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("recordings.json")
    }()

    private let legacyKey = "speedapp.recordings.v1"

    init() {
        load()
    }

    // MARK: - Mutations

    func addRecording(
        result: LocationManager.RecordingResult,
        batteryStart: Double?,
        batteryEnd: Double?
    ) {
        guard result.duration > 2 else { return } // skip accidental taps
        let recording = SpeedRecording(
            date: Date(),
            duration: result.duration,
            maxMph: result.maxMph,
            avgMph: result.avgMph,
            distanceMiles: result.distanceMiles,
            samples: result.samples,
            elevationGainFt: result.elevationGainFt,
            elevationLossFt: result.elevationLossFt,
            batteryStartPercent: batteryStart,
            batteryEndPercent: batteryEnd
        )
        recordings.insert(recording, at: 0)
        save()
    }

    func rename(id: UUID, to newName: String) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func delete(id: UUID) {
        recordings.removeAll { $0.id == id }
        save()
    }

    func clearAllRecordings() {
        recordings.removeAll()
        save()
    }

    // MARK: - Sorting

    func sorted(by sort: RecordingSort, search: String) -> [SpeedRecording] {
        let filtered: [SpeedRecording]
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filtered = recordings
        } else {
            filtered = recordings.filter { $0.displayName.lowercased().contains(query) }
        }

        switch sort {
        case .newest:   return filtered.sorted { $0.date > $1.date }
        case .oldest:   return filtered.sorted { $0.date < $1.date }
        case .farthest: return filtered.sorted { $0.distanceMiles > $1.distanceMiles }
        case .fastest:  return filtered.sorted { $0.maxMph > $1.maxMph }
        case .longest:  return filtered.sorted { $0.duration > $1.duration }
        }
    }

    // MARK: - Lifetime totals

    var lifetimeTotals: LifetimeTotals {
        var totals = LifetimeTotals()
        totals.rideCount = recordings.count

        for rec in recordings {
            totals.totalDistanceMiles += rec.distanceMiles
            totals.totalDurationSeconds += rec.duration
            totals.totalElevationGainFt += rec.elevationGainFt
            totals.topSpeedMph = max(totals.topSpeedMph, rec.maxMph)
            totals.longestRideMiles = max(totals.longestRideMiles, rec.distanceMiles)
        }

        if totals.totalDurationSeconds > 0 {
            let hours = totals.totalDurationSeconds / 3600
            totals.overallAvgMph = totals.totalDistanceMiles / hours
        }
        return totals
    }

    // MARK: - Battery estimation

    /// Number of battery-logged rides needed before an estimate is offered.
    /// One ride is far too noisy to extrapolate from.
    static let minimumRidesForBatteryEstimate = 3

    /// Rides where the rider logged both a start and end battery percentage
    /// and actually covered meaningful ground.
    private var batteryLoggedRides: [SpeedRecording] {
        recordings.filter { rec in
            guard let used = rec.batteryUsedPercent else { return false }
            return used > 0 && rec.distanceMiles > 0.2
        }
    }

    var batteryRidesLogged: Int { batteryLoggedRides.count }

    /// Average miles travelled per 1% of battery, pooled across all logged rides.
    /// Pooling totals (rather than averaging each ride's ratio) means longer rides
    /// carry more weight, which is what you want — they're better data.
    var milesPerBatteryPercent: Double? {
        let rides = batteryLoggedRides
        guard rides.count >= Self.minimumRidesForBatteryEstimate else { return nil }

        let totalMiles = rides.reduce(0.0) { $0 + $1.distanceMiles }
        let totalPercent = rides.reduce(0.0) { $0 + ($1.batteryUsedPercent ?? 0) }
        guard totalPercent > 0 else { return nil }
        return totalMiles / totalPercent
    }

    /// Estimated miles left at a given battery level, based on your riding history.
    func estimatedRangeMiles(atBatteryPercent percent: Double) -> Double? {
        guard let perPercent = milesPerBatteryPercent else { return nil }
        return perPercent * max(percent, 0)
    }

    /// Full-charge range implied by your history.
    var estimatedFullRangeMiles: Double? {
        estimatedRangeMiles(atBatteryPercent: 100)
    }

    /// Battery percentage entered at the end of the most recent logged ride —
    /// a sensible default for the next ride's starting value.
    var lastKnownBatteryPercent: Double? {
        recordings.first(where: { $0.batteryEndPercent != nil })?.batteryEndPercent
    }

    // MARK: - Persistence

    private func save() {
        let snapshot = recordings
        // Writing can be slow with lots of samples, so keep it off the main thread.
        DispatchQueue.global(qos: .utility).async { [fileURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SpeedRecording].self, from: data) {
            recordings = decoded
            return
        }

        // One-time migration from the old UserDefaults-based storage.
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey),
           let decoded = try? JSONDecoder().decode([SpeedRecording].self, from: legacyData) {
            recordings = decoded
            save()
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }
}

import Foundation
import Combine

struct SpeedRecording: Identifiable, Codable, Equatable, Sendable {
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
    /// Which vehicle this was recorded on. Rides saved before vehicle modes existed were
    /// all scooter rides, so that's the right fallback.
    var mode: VehicleMode = .scooter

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

    // MARK: - Decoding
    //
    // Written by hand rather than synthesized, because Swift's generated Decodable calls
    // decode(_:forKey:) for non-optional properties, which THROWS when a key is absent —
    // it does not fall back to the property's default value. Fields added over time (name,
    // elevation, mode) are missing from older saved rides, so the synthesized version would
    // fail on them. RunStore.load() swallows decode errors with `try?`, meaning that failure
    // would silently present as "all your history is gone".
    //
    // decodeIfPresent gives every added field a safe fallback, so old rides keep loading.

    enum CodingKeys: String, CodingKey {
        case id, date, duration, maxMph, avgMph, distanceMiles, samples
        case name, elevationGainFt, elevationLossFt
        case batteryStartPercent, batteryEndPercent, mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Core fields — present in every version, so a genuine failure here is a real error.
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        duration = try c.decode(Double.self, forKey: .duration)
        maxMph = try c.decode(Double.self, forKey: .maxMph)
        avgMph = try c.decode(Double.self, forKey: .avgMph)
        distanceMiles = try c.decode(Double.self, forKey: .distanceMiles)
        samples = try c.decode([SpeedSample].self, forKey: .samples)

        // Added later — tolerate their absence.
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        elevationGainFt = try c.decodeIfPresent(Double.self, forKey: .elevationGainFt) ?? 0
        elevationLossFt = try c.decodeIfPresent(Double.self, forKey: .elevationLossFt) ?? 0
        batteryStartPercent = try c.decodeIfPresent(Double.self, forKey: .batteryStartPercent)
        batteryEndPercent = try c.decodeIfPresent(Double.self, forKey: .batteryEndPercent)
        // Rides predating vehicle modes were all scooter rides.
        mode = try c.decodeIfPresent(VehicleMode.self, forKey: .mode) ?? .scooter
    }

    /// Memberwise init, which the custom `init(from:)` above would otherwise suppress.
    init(
        id: UUID = UUID(),
        date: Date,
        duration: Double,
        maxMph: Double,
        avgMph: Double,
        distanceMiles: Double,
        samples: [SpeedSample],
        name: String = "",
        elevationGainFt: Double = 0,
        elevationLossFt: Double = 0,
        batteryStartPercent: Double? = nil,
        batteryEndPercent: Double? = nil,
        mode: VehicleMode = .scooter
    ) {
        self.id = id
        self.date = date
        self.duration = duration
        self.maxMph = maxMph
        self.avgMph = avgMph
        self.distanceMiles = distanceMiles
        self.samples = samples
        self.name = name
        self.elevationGainFt = elevationGainFt
        self.elevationLossFt = elevationLossFt
        self.batteryStartPercent = batteryStartPercent
        self.batteryEndPercent = batteryEndPercent
        self.mode = mode
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

    /// A dedicated serial queue for writes. Saves stay off the main thread, but run one at a
    /// time in order — so a slower earlier write can't finish after (and clobber) a later one.
    private let saveQueue = DispatchQueue(label: "RunStore.saveQueue", qos: .utility)

    init() {
        load()
    }

    // MARK: - Mutations

    /// Returns the saved ride, or nil if it was too short to keep. Callers need to know the
    /// difference — assuming `recordings.first` is the new ride is wrong when nothing was saved.
    @discardableResult
    func addRecording(
        result: LocationManager.RecordingResult,
        mode: VehicleMode,
        batteryStart: Double?,
        batteryEnd: Double?
    ) -> SpeedRecording? {
        guard result.duration > 2 else { return nil } // skip accidental taps
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
            batteryEndPercent: batteryEnd,
            mode: mode
        )
        recordings.insert(recording, at: 0)
        save()
        return recording
    }

    func rename(id: UUID, to newName: String) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    /// Reassigns a ride to a different vehicle — for when you record under the wrong one.
    /// Everything derived from mode (per-vehicle records, lifetime totals, battery range,
    /// history filters, trends) is computed live from the rides, so it all updates instantly.
    func setMode(id: UUID, to mode: VehicleMode) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].mode = mode
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

    // MARK: - Backup restore

    /// Result of restoring a backup, so the UI can report what actually happened.
    struct RestoreResult {
        var added: Int
        var skipped: Int   // already present
    }

    /// Merges a backup into the existing rides. Rides carry stable UUIDs, so re-importing
    /// the same backup twice adds nothing the second time — no duplicates.
    @discardableResult
    func merge(_ incoming: [SpeedRecording]) -> RestoreResult {
        let existingIDs = Set(recordings.map(\.id))
        let new = incoming.filter { !existingIDs.contains($0.id) }

        recordings.append(contentsOf: new)
        recordings.sort { $0.date > $1.date }
        save()

        return RestoreResult(added: new.count, skipped: incoming.count - new.count)
    }

    /// Throws away everything currently stored and uses the backup instead.
    func replaceAll(with incoming: [SpeedRecording]) {
        recordings = incoming.sorted { $0.date > $1.date }
        save()
    }

    // MARK: - Sorting / filtering

    /// `mode: nil` means all vehicles.
    func sorted(by sort: RecordingSort, search: String, mode: VehicleMode? = nil) -> [SpeedRecording] {
        var filtered = recordings

        if let mode {
            filtered = filtered.filter { $0.mode == mode }
        }

        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            filtered = filtered.filter { $0.displayName.lowercased().contains(query) }
        }

        switch sort {
        case .newest:   return filtered.sorted { $0.date > $1.date }
        case .oldest:   return filtered.sorted { $0.date < $1.date }
        case .farthest: return filtered.sorted { $0.distanceMiles > $1.distanceMiles }
        case .fastest:  return filtered.sorted { $0.maxMph > $1.maxMph }
        case .longest:  return filtered.sorted { $0.duration > $1.duration }
        }
    }

    func recordings(for mode: VehicleMode) -> [SpeedRecording] {
        recordings.filter { $0.mode == mode }
    }

    /// Which vehicles actually have rides logged — used to only show relevant tabs/filters.
    var modesWithRides: [VehicleMode] {
        VehicleMode.allCases.filter { mode in
            recordings.contains { $0.mode == mode }
        }
    }

    // MARK: - Lifetime totals

    /// `mode: nil` totals every vehicle together.
    func lifetimeTotals(for mode: VehicleMode? = nil) -> LifetimeTotals {
        let rides = mode.map { m in recordings.filter { $0.mode == m } } ?? recordings

        var totals = LifetimeTotals()
        totals.rideCount = rides.count

        for rec in rides {
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

    /// Battery-logged rides for a given vehicle. Scoped by mode because pooling a scooter's
    /// miles-per-percent with anything else would produce a meaningless number.
    private func batteryLoggedRides(for mode: VehicleMode) -> [SpeedRecording] {
        recordings.filter { rec in
            guard rec.mode == mode, let used = rec.batteryUsedPercent else { return false }
            return used > 0 && rec.distanceMiles > 0.2
        }
    }

    func batteryRidesLogged(for mode: VehicleMode) -> Int {
        batteryLoggedRides(for: mode).count
    }

    /// Average miles travelled per 1% of battery, pooled across that vehicle's logged rides.
    /// Pooling totals (rather than averaging each ride's ratio) means longer rides carry more
    /// weight, which is what you want — they're better data.
    func milesPerBatteryPercent(for mode: VehicleMode) -> Double? {
        let rides = batteryLoggedRides(for: mode)
        guard rides.count >= Self.minimumRidesForBatteryEstimate else { return nil }

        let totalMiles = rides.reduce(0.0) { $0 + $1.distanceMiles }
        let totalPercent = rides.reduce(0.0) { $0 + ($1.batteryUsedPercent ?? 0) }
        guard totalPercent > 0 else { return nil }
        return totalMiles / totalPercent
    }

    /// Full-charge range implied by that vehicle's history.
    func estimatedFullRangeMiles(for mode: VehicleMode) -> Double? {
        guard let perPercent = milesPerBatteryPercent(for: mode) else { return nil }
        return perPercent * 100
    }

    /// Battery percentage entered at the end of the most recent logged ride on this vehicle —
    /// a sensible default for the next ride's starting value.
    func lastKnownBatteryPercent(for mode: VehicleMode) -> Double? {
        recordings.first(where: { $0.mode == mode && $0.batteryEndPercent != nil })?.batteryEndPercent
    }

    // MARK: - Persistence

    private func save() {
        let snapshot = recordings
        // Writing can be slow with lots of samples, so keep it off the main thread.
        saveQueue.async { [fileURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Set if the saved rides file exists but couldn't be read. The UI can warn instead of
    /// pretending there's no history — silently showing an empty list would invite the rider
    /// to record over it, or hit Clear All, and destroy recoverable data.
    @Published private(set) var loadFailed = false

    private func load() {
        let fm = FileManager.default

        if fm.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                recordings = try JSONDecoder().decode([SpeedRecording].self, from: data)
            } catch {
                // The file exists but won't decode. Don't lose it: move it aside under a
                // timestamped name before carrying on, otherwise the next ride saved would
                // overwrite it. It's plain JSON and reachable via the Files app, so a
                // preserved copy is genuinely recoverable.
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let salvage = fileURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("recordings-unreadable-\(formatter.string(from: Date())).json")
                try? fm.moveItem(at: fileURL, to: salvage)

                loadFailed = true
                recordings = []
            }
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

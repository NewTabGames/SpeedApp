import Foundation

/// Personal records — the standout rides across your history.
///
/// Each record points at the ride that holds it, so tapping one can jump straight to it.
struct PersonalRecords {
    var fastest: SpeedRecording?        // highest top speed
    var farthest: SpeedRecording?       // greatest distance
    var longest: SpeedRecording?        // greatest duration
    var biggestClimb: SpeedRecording?   // most elevation gain
    var mostRidesInAWeek: Int = 0
    var bestWeekDistanceMiles: Double = 0

    var isEmpty: Bool {
        fastest == nil && farthest == nil && longest == nil && biggestClimb == nil
    }
}

/// One bucket of riding — a week or a month.
struct StatsBucket: Identifiable {
    let start: Date
    var rideCount: Int = 0
    var distanceMiles: Double = 0
    var durationSeconds: Double = 0

    var id: Date { start }
}

enum StatsPeriod: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    var id: String { rawValue }

    var component: Calendar.Component {
        self == .weekly ? .weekOfYear : .month
    }

    /// How many buckets back to show by default.
    var bucketsToShow: Int {
        self == .weekly ? 12 : 6
    }

    func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = self == .weekly ? "M/d" : "MMM"
        return formatter.string(from: date)
    }
}

extension RunStore {

    // MARK: - Personal records

    /// `mode: nil` looks across every vehicle. Records are usually more meaningful per
    /// vehicle — a car will always out-run a scooter — so the UI scopes them by default.
    func personalRecords(for mode: VehicleMode? = nil) -> PersonalRecords {
        let rides = mode.map { m in recordings.filter { $0.mode == m } } ?? recordings
        guard !rides.isEmpty else { return PersonalRecords() }

        var records = PersonalRecords()
        records.fastest = rides.max { $0.maxMph < $1.maxMph }
        records.farthest = rides.max { $0.distanceMiles < $1.distanceMiles }
        records.longest = rides.max { $0.duration < $1.duration }
        records.biggestClimb = rides.max { $0.elevationGainFt < $1.elevationGainFt }

        // Busiest week, by both ride count and distance.
        let calendar = Calendar.current
        var weekCounts: [Date: (count: Int, miles: Double)] = [:]
        for ride in rides {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: ride.date)?.start else { continue }
            var entry = weekCounts[week] ?? (0, 0)
            entry.count += 1
            entry.miles += ride.distanceMiles
            weekCounts[week] = entry
        }
        records.mostRidesInAWeek = weekCounts.values.map(\.count).max() ?? 0
        records.bestWeekDistanceMiles = weekCounts.values.map(\.miles).max() ?? 0

        return records
    }

    /// Which records, if any, a newly-saved ride just broke. Compared against every *other*
    /// ride, so the new one isn't competing with itself.
    func recordsBroken(by ride: SpeedRecording) -> [String] {
        let others = recordings.filter { $0.id != ride.id && $0.mode == ride.mode }
        guard !others.isEmpty else { return [] }   // first ride on this vehicle sets no records

        var broken: [String] = []
        if ride.maxMph > (others.map(\.maxMph).max() ?? 0) {
            broken.append("Top Speed")
        }
        if ride.distanceMiles > (others.map(\.distanceMiles).max() ?? 0) {
            broken.append("Longest Distance")
        }
        if ride.duration > (others.map(\.duration).max() ?? 0) {
            broken.append("Longest Ride")
        }
        if ride.elevationGainFt > (others.map(\.elevationGainFt).max() ?? 0),
           ride.elevationGainFt > 10 {   // ignore noise-level "climbs"
            broken.append("Biggest Climb")
        }
        return broken
    }

    // MARK: - Trends over time

    /// Groups rides into weekly or monthly buckets, oldest first (so charts read
    /// left-to-right as time moving forward). Empty periods are included as zeroes —
    /// otherwise a week you didn't ride would silently vanish and distort the trend.
    func buckets(period: StatsPeriod, mode: VehicleMode? = nil) -> [StatsBucket] {
        let rides = mode.map { m in recordings.filter { $0.mode == m } } ?? recordings
        guard !rides.isEmpty else { return [] }

        let calendar = Calendar.current
        let component = period.component

        /// The single way a bucket key is derived. Both the rides being filed away and the
        /// buckets being looked up go through this, so the two can't drift apart. Deriving
        /// them separately (one via dateInterval, one via date(byAdding:)) risks a mismatch
        /// across a DST boundary, and a missed lookup would silently show an empty bar for
        /// a period you actually rode in.
        func bucketStart(for date: Date) -> Date? {
            calendar.dateInterval(of: component, for: date)?.start
        }

        var byStart: [Date: StatsBucket] = [:]
        for ride in rides {
            guard let start = bucketStart(for: ride.date) else { continue }
            var bucket = byStart[start] ?? StatsBucket(start: start)
            bucket.rideCount += 1
            bucket.distanceMiles += ride.distanceMiles
            bucket.durationSeconds += ride.duration
            byStart[start] = bucket
        }

        // Walk backwards from the current period, filling gaps with empty buckets.
        guard let thisStart = bucketStart(for: Date()) else { return [] }

        var result: [StatsBucket] = []
        for offset in stride(from: period.bucketsToShow - 1, through: 0, by: -1) {
            guard
                let raw = calendar.date(byAdding: component, value: -offset, to: thisStart),
                // Re-normalize through the same function used when filing rides away.
                let start = bucketStart(for: raw)
            else { continue }
            result.append(byStart[start] ?? StatsBucket(start: start))
        }
        return result
    }
}

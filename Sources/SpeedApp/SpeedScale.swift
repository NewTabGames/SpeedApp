import Foundation

/// Maps a ride's speeds onto the 0...1 colour ramp.
///
/// The obvious approach — linear between the ride's slowest and fastest point — falls apart
/// whenever the speeds cluster, which they usually do. A motorway drive might be 0-80 mph on
/// paper, but if two thirds of it is spent cruising between 62 and 80, all of that lands in
/// the top fifth of the ramp and the whole route comes out one flat colour. The scale is
/// technically correct and visually useless.
///
/// Instead this ranks each speed against every other speed in the same ride: a point faster
/// than 70% of the ride sits at 0.7 on the ramp, whatever the numbers happen to be. The full
/// colour range gets used on every ride — a 15 mph scooter pootle and an 80 mph motorway run
/// both show their own fast and slow stretches clearly.
///
/// The trade-off, stated plainly: colour shows speed *relative to that ride*, not an absolute
/// mph value. Two different rides' colours aren't comparable to each other. For seeing where
/// you sped up and slowed down — which is the point — that's the right call.
struct SpeedScale {

    private let sortedSpeeds: [Double]
    let minMph: Double
    let maxMph: Double

    init(samples: [SpeedSample]) {
        let speeds = samples.map(\.mph)
        sortedSpeeds = speeds.sorted()
        minMph = sortedSpeeds.first ?? 0
        maxMph = sortedSpeeds.last ?? 0
    }

    /// True when every point was effectively the same speed, so there's nothing to shade.
    var isFlat: Bool {
        maxMph - minMph < 0.5
    }

    /// Position on the colour ramp, 0 (slowest of this ride) to 1 (fastest).
    func normalized(_ mph: Double) -> Double {
        guard sortedSpeeds.count > 1 else { return 0.5 }

        // A genuinely flat ride would otherwise have every point ranked arbitrarily by
        // floating-point noise. Show it as mid-scale rather than inventing variation.
        guard !isFlat else { return 0.5 }

        let rank = lowerBound(mph)
        return Double(rank) / Double(sortedSpeeds.count - 1)
    }

    /// Index of the first element >= value. Binary search — this runs once per route
    /// segment, and a long ride has thousands.
    private func lowerBound(_ value: Double) -> Int {
        var low = 0
        var high = sortedSpeeds.count

        while low < high {
            let mid = (low + high) / 2
            if sortedSpeeds[mid] < value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return min(low, sortedSpeeds.count - 1)
    }
}

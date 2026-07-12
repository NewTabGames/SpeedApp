import SwiftUI
import MapKit

/// Draws a recorded route on the map, optionally colored by speed.
///
/// MapKit draws each MapPolyline in a single color, so a speed-colored route is built from
/// many short segments — each one shaded by the speed at that point (pale = slow, deep =
/// fast, in the current accent hue). When speed coloring is off, it's one flat polyline.
struct RouteMap: View {
    let recording: SpeedRecording
    let accent: AccentTheme
    let colorBySpeed: Bool
    let mapStyle: MapStyle
    var showEndpoints: Bool = true

    private var coordinates: [CLLocationCoordinate2D] {
        recording.samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Speed range across this ride, used to normalize each segment to 0...1.
    /// Falls back to a tiny range if every sample is identical, to avoid divide-by-zero.
    private var speedRange: (min: Double, max: Double) {
        let speeds = recording.samples.map(\.mph)
        let lo = speeds.min() ?? 0
        let hi = speeds.max() ?? 1
        return hi - lo < 0.1 ? (lo, lo + 0.1) : (lo, hi)
    }

    var body: some View {
        Map(initialPosition: cameraPosition) {
            if colorBySpeed && recording.samples.count > 1 {
                ForEach(speedSegments) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            } else {
                MapPolyline(coordinates: coordinates)
                    .stroke(accent.color, lineWidth: 4)
            }

            if showEndpoints {
                if let first = coordinates.first {
                    Marker("Start", coordinate: first).tint(.green)
                }
                if let last = coordinates.last {
                    Marker("End", coordinate: last).tint(.red)
                }
            }
        }
        .mapStyle(mapStyle)
    }

    // MARK: - Speed segments

    private struct Segment: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    /// One segment per pair of adjacent samples, colored by the average speed of the pair.
    /// Consecutive samples share an endpoint so the line stays continuous.
    private var speedSegments: [Segment] {
        let samples = recording.samples
        guard samples.count > 1 else { return [] }

        let range = speedRange
        var segments: [Segment] = []
        segments.reserveCapacity(samples.count - 1)

        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            let avgSpeed = (a.mph + b.mph) / 2
            let t = (avgSpeed - range.min) / (range.max - range.min)

            segments.append(Segment(
                id: i,
                coordinates: [
                    CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude),
                    CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)
                ],
                color: accent.speedShade(t)
            ))
        }
        return segments
    }

    // MARK: - Camera

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
}

/// A small legend explaining the speed gradient, shown under the route map.
struct SpeedLegend: View {
    let accent: AccentTheme
    let minLabel: String
    let maxLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Text(minLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            LinearGradient(
                colors: stride(from: 0.0, through: 1.0, by: 0.1).map { accent.speedShade($0) },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 8)
            .clipShape(Capsule())
            Text(maxLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

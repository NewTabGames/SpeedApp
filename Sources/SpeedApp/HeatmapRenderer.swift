import UIKit
import CoreLocation
import MapKit

/// Builds a density heatmap image from recorded GPS points — the classic blue→red field
/// where colour shows how often you've been somewhere, not just where you went.
///
/// The pipeline is the standard one:
///   1. Project every GPS point into a fixed-size intensity grid.
///   2. Accumulate — cells hit by many rides build up a higher value.
///   3. Blur the grid so isolated points become soft blobs and nearby ones merge.
///   4. Map each cell's intensity through a blue→cyan→green→yellow→red colour ramp.
///
/// The result is a single image plus the geographic rectangle it covers, so it can be laid
/// over the map as one static overlay. It's generated once when a ride finishes (see
/// RunStore) rather than live, so cost here doesn't affect map smoothness.
enum HeatmapRenderer {

    /// A finished heatmap: the image and the map rect it spans.
    struct Result {
        let image: UIImage
        let region: MKCoordinateRegion
    }

    /// The off-thread half of the work: everything up to but not including image creation.
    /// Holds only value types, so it crosses actor boundaries cleanly (UIImage does not).
    struct GridData {
        let grid: [Double]
        let peak: Double
        let region: MKCoordinateRegion
    }

    /// Grid resolution. The image is rendered at a multiple of this for smoothness.
    private static let gridSize = 160
    private static let pixelScale = 4          // output image is gridSize * pixelScale px
    private static let blurRadius = 3          // in grid cells

    /// Heavy part — accumulation and blur. Safe to run on a background thread.
    static func computeGrid(from recordings: [SpeedRecording]) -> GridData? {
        let allSamples = recordings.flatMap { $0.samples }
        guard allSamples.count > 1 else { return nil }

        let lats = allSamples.map(\.latitude)
        let lons = allSamples.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max(),
              maxLat > minLat, maxLon > minLon else { return nil }

        let latPad = (maxLat - minLat) * 0.08 + 0.0008
        let lonPad = (maxLon - minLon) * 0.08 + 0.0008
        let loLat = minLat - latPad, hiLat = maxLat + latPad
        let loLon = minLon - lonPad, hiLon = maxLon + lonPad

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (loLat + hiLat) / 2,
                                           longitude: (loLon + hiLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: hiLat - loLat,
                                   longitudeDelta: hiLon - loLon)
        )

        var grid = [Double](repeating: 0, count: gridSize * gridSize)
        let latRange = hiLat - loLat
        let lonRange = hiLon - loLon

        for s in allSamples {
            let fx = (s.longitude - loLon) / lonRange
            let fy = 1 - (s.latitude - loLat) / latRange
            let gx = min(max(Int(fx * Double(gridSize - 1)), 0), gridSize - 1)
            let gy = min(max(Int(fy * Double(gridSize - 1)), 0), gridSize - 1)
            grid[gy * gridSize + gx] += 1
        }

        for _ in 0..<3 {
            grid = boxBlur(grid, size: gridSize, radius: blurRadius)
        }

        let sorted = grid.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let pct = sorted[Int(Double(sorted.count - 1) * 0.99)]
        let peak = max(pct, 0.0001)

        return GridData(grid: grid, peak: peak, region: region)
    }

    /// Light part — turns the computed grid into an image. Runs on the main actor because
    /// UIGraphicsImageRenderer and UIImage aren't safe to hand across threads.
    @MainActor
    static func image(from data: GridData) -> Result {
        let image = rasterize(grid: data.grid, peak: data.peak)
        return Result(image: image, region: data.region)
    }

    private static func boxBlur(_ src: [Double], size: Int, radius: Int) -> [Double] {
        var tmp = [Double](repeating: 0, count: src.count)
        let window = Double(radius * 2 + 1)

        // Horizontal pass.
        for y in 0..<size {
            let row = y * size
            for x in 0..<size {
                var sum = 0.0
                for k in -radius...radius {
                    let xi = min(max(x + k, 0), size - 1)
                    sum += src[row + xi]
                }
                tmp[row + x] = sum / window
            }
        }

        // Vertical pass.
        var out = [Double](repeating: 0, count: src.count)
        for x in 0..<size {
            for y in 0..<size {
                var sum = 0.0
                for k in -radius...radius {
                    let yi = min(max(y + k, 0), size - 1)
                    sum += tmp[yi * size + x]
                }
                out[y * size + x] = sum / window
            }
        }
        return out
    }

    private static func rasterize(grid: [Double], peak: Double) -> UIImage {
        let dim = gridSize * pixelScale
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            for gy in 0..<gridSize {
                for gx in 0..<gridSize {
                    let v = grid[gy * gridSize + gx] / peak
                    guard v > 0.02 else { continue }   // leave empty areas fully transparent
                    let t = min(v, 1.0)
                    let (r, g, b, a) = heatColor(t)
                    cg.setFillColor(red: r, green: g, blue: b, alpha: a)
                    cg.fill(CGRect(x: gx * pixelScale, y: gy * pixelScale,
                                   width: pixelScale, height: pixelScale))
                }
            }
        }
    }

    /// The classic heatmap ramp: transparent → blue → cyan → green → yellow → red.
    /// Alpha fades in at the low end so faint areas melt into the map instead of showing
    /// a hard blue edge.
    private static func heatColor(_ t: Double) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (0.0,  0.1,  0.5)),   // deep blue
            (0.25, (0.0,  0.6,  1.0)),   // cyan
            (0.50, (0.2,  0.9,  0.3)),   // green
            (0.75, (1.0,  0.85, 0.0)),   // yellow
            (1.00, (0.9,  0.1,  0.05))   // red
        ]

        var lower = stops[0], upper = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where t >= stops[i].0 && t <= stops[i + 1].0 {
            lower = stops[i]; upper = stops[i + 1]
            break
        }
        let span = upper.0 - lower.0
        let f = span > 0 ? (t - lower.0) / span : 0
        let r = lower.1.0 + (upper.1.0 - lower.1.0) * f
        let g = lower.1.1 + (upper.1.1 - lower.1.1) * f
        let b = lower.1.2 + (upper.1.2 - lower.1.2) * f

        // Ramp alpha up quickly over the first 20% so hot areas are solid and cool areas soft.
        let alpha = min(0.85, 0.35 + t * 1.4)
        return (CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(alpha))
    }
}

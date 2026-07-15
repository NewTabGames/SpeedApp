import SwiftUI
import MapKit
import CoreLocation

/// Holds the current heatmap image and rebuilds it when rides change.
///
/// The heatmap is expensive to generate but changes rarely — only when a ride is added or
/// removed — so it's built once, cached to disk, and simply displayed thereafter. Opening the
/// heatmap screen shows the cached image instantly rather than rendering on the spot.
///
/// A separate object (rather than living in RunStore) keeps the image/MapKit dependencies out
/// of the plain data layer, and lets the heavy render run off the main thread without blocking
/// ride saving.
@MainActor
final class HeatmapStore: ObservableObject {

    /// The rendered heatmap, or nil if there aren't enough points yet.
    @Published private(set) var heatmap: HeatmapRenderer.Result?
    @Published private(set) var isRendering = false

    private let imageURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("heatmap.png")
    }()
    private let regionURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("heatmap-region.json")
    }()

    init() {
        loadCached()
    }

    /// Rebuilds the heatmap from the given rides, off the main thread. Called when a ride
    /// finishes. `filterMode` nil renders every vehicle together.
    func rebuild(from recordings: [SpeedRecording]) {
        isRendering = true

        // Snapshot only what the renderer needs (value types), so we're not touching the
        // store's arrays from a background thread.
        let snapshot = recordings

        Task.detached(priority: .utility) {
            // Heavy grid work off the main thread; returns only value types.
            let gridData = HeatmapRenderer.computeGrid(from: snapshot)

            await MainActor.run {
                if let gridData {
                    self.heatmap = HeatmapRenderer.image(from: gridData)
                } else {
                    self.heatmap = nil
                }
                self.isRendering = false
                self.persist(self.heatmap)
            }
        }
    }

    /// Clears the cached heatmap (e.g. when all rides are deleted).
    func clear() {
        heatmap = nil
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: regionURL)
    }

    // MARK: - Persistence

    private struct StoredRegion: Codable {
        let centerLat, centerLon, spanLat, spanLon: Double
    }

    private func persist(_ result: HeatmapRenderer.Result?) {
        guard let result else {
            clear()
            return
        }
        if let data = result.image.pngData() {
            try? data.write(to: imageURL, options: .atomic)
        }
        let r = result.region
        let stored = StoredRegion(
            centerLat: r.center.latitude, centerLon: r.center.longitude,
            spanLat: r.span.latitudeDelta, spanLon: r.span.longitudeDelta
        )
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: regionURL, options: .atomic)
        }
    }

    private func loadCached() {
        guard
            let imageData = try? Data(contentsOf: imageURL),
            let image = UIImage(data: imageData),
            let regionData = try? Data(contentsOf: regionURL),
            let stored = try? JSONDecoder().decode(StoredRegion.self, from: regionData)
        else { return }

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: stored.centerLat, longitude: stored.centerLon),
            span: MKCoordinateSpan(latitudeDelta: stored.spanLat, longitudeDelta: stored.spanLon)
        )
        heatmap = HeatmapRenderer.Result(image: image, region: region)
    }
}

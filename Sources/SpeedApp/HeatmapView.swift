import SwiftUI
import MapKit

/// Shows the density heatmap — the blue→red field where colour reflects how often you've
/// ridden somewhere.
///
/// The image itself is generated when a ride finishes (see HeatmapStore), not here, so this
/// view just lays the cached image over a map. Opening it is instant and there's no rendering
/// cost while it's on screen.
struct HeatmapView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var heatmapStore: HeatmapStore
    @EnvironmentObject var runStore: RunStore

    var body: some View {
        Group {
            if let heatmap = heatmapStore.heatmap {
                ZStack(alignment: .bottom) {
                    HeatmapMap(
                        image: heatmap.image,
                        region: heatmap.region,
                        mapStyle: settings.mapStyle
                    )
                    .ignoresSafeArea(edges: .bottom)

                    legend
                }
            } else if heatmapStore.isRendering {
                ProgressView("Building heatmap…")
            } else if hasRidesToMap {
                // Rides exist but no image is cached yet — e.g. they were recorded before the
                // heatmap feature, or the cache was cleared. Build it now.
                ProgressView("Building heatmap…")
                    .onAppear {
                        // Defer so we're not flipping a @Published flag mid-render.
                        DispatchQueue.main.async {
                            heatmapStore.rebuild(from: runStore.recordings)
                        }
                    }
            } else {
                ContentUnavailableView(
                    "No Routes Yet",
                    systemImage: "flame",
                    description: Text("Record a few rides and they'll build into a heatmap here.")
                )
            }
        }
        .navigationTitle("Heatmap")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Whether there's anything worth rendering — at least one ride with real GPS points.
    private var hasRidesToMap: Bool {
        runStore.recordings.contains { $0.samples.count > 1 }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            LinearGradient(
                colors: [
                    Color(red: 0.0, green: 0.1, blue: 0.5),
                    Color(red: 0.0, green: 0.6, blue: 1.0),
                    Color(red: 0.2, green: 0.9, blue: 0.3),
                    Color(red: 1.0, green: 0.85, blue: 0.0),
                    Color(red: 0.9, green: 0.1, blue: 0.05)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 120, height: 8)
            .clipShape(Capsule())
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
        .padding(.bottom, 20)
    }
}

/// Wraps MKMapView so a pre-rendered heatmap image can be laid over a fixed geographic
/// rectangle with a proper overlay renderer — SwiftUI's Map has no image-overlay support.
private struct HeatmapMap: UIViewRepresentable {
    let image: UIImage
    let region: MKCoordinateRegion
    let mapStyle: MapStyleOption

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.setRegion(paddedRegion, animated: false)
        applyStyle(to: map)
        addOverlay(to: map)
        context.coordinator.lastImage = image
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        applyStyle(to: map)

        // Only touch the overlay when the image actually changed. SwiftUI calls this for
        // ANY state change in the ancestor views (a published flag flipping, a re-render),
        // and tearing down + re-adding the overlay each time makes the heat layer visibly
        // blink for no reason.
        if context.coordinator.lastImage !== image {
            context.coordinator.lastImage = image
            map.removeOverlays(map.overlays)
            addOverlay(to: map)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var paddedRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: region.span.latitudeDelta * 1.25,
                longitudeDelta: region.span.longitudeDelta * 1.25
            )
        )
    }

    private func applyStyle(to map: MKMapView) {
        switch mapStyle {
        case .standard: map.preferredConfiguration = MKStandardMapConfiguration()
        case .hybrid:   map.preferredConfiguration = MKHybridMapConfiguration()
        case .satellite: map.preferredConfiguration = MKImageryMapConfiguration()
        }
    }

    private func addOverlay(to map: MKMapView) {
        let overlay = HeatmapOverlay(image: image, region: region)
        map.addOverlay(overlay)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        /// The image currently applied as an overlay — the churn guard in updateUIView.
        var lastImage: UIImage?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let heat = overlay as? HeatmapOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            return HeatmapOverlayRenderer(overlay: heat)
        }
    }
}

/// An overlay covering the heatmap's geographic rectangle.
private final class HeatmapOverlay: NSObject, MKOverlay {
    let image: UIImage
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(image: UIImage, region: MKCoordinateRegion) {
        self.image = image
        self.coordinate = region.center

        // Convert the region's corners to map points to get the covering rect.
        let topLeft = CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        )
        let bottomRight = CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )
        let tlPoint = MKMapPoint(topLeft)
        let brPoint = MKMapPoint(bottomRight)
        self.boundingMapRect = MKMapRect(
            x: tlPoint.x,
            y: tlPoint.y,
            width: brPoint.x - tlPoint.x,
            height: brPoint.y - tlPoint.y
        )
    }
}

/// Draws the heatmap image stretched across the overlay's rectangle.
private final class HeatmapOverlayRenderer: MKOverlayRenderer {
    private let image: UIImage

    init(overlay: HeatmapOverlay) {
        self.image = overlay.image
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let cgImage = image.cgImage else { return }
        let rect = self.rect(for: overlay.boundingMapRect)

        // The image's row 0 is north; Core Graphics draws bottom-up, so flip vertically to
        // keep north at the top.
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        let drawRect = CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height)
        context.setAlpha(0.75)
        context.draw(cgImage, in: drawRect)
        context.restoreGState()
    }
}

import Foundation
import MapKit
import UIKit

/// Renders a saved ride's route to a shareable PNG.
///
/// SwiftUI's ImageRenderer can't capture a Map — the map is a UIKit view underneath and
/// comes out blank. MKMapSnapshotter is the supported way: it renders the map tiles to an
/// image, and then the route line, start/end markers, and stats banner are drawn on top
/// with Core Graphics.
enum MapExporter {

    enum ExportError: Error {
        case notEnoughPoints
        case snapshotFailed
        case renderFailed
    }

    static func exportRouteImage(
        recording: SpeedRecording,
        unit: SpeedUnit,
        accentTheme: AccentTheme,
        colorBySpeed: Bool,
        mapType: MKMapType,
        size: CGSize = CGSize(width: 1000, height: 1000),
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let coordinates = recording.samples.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard coordinates.count > 1 else {
            completion(.failure(ExportError.notEnoughPoints))
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = boundingRegion(for: coordinates)
        options.size = size
        options.mapType = mapType
        options.showsBuildings = true

        MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snapshot, error in
            guard let snapshot else {
                DispatchQueue.main.async { completion(.failure(error ?? ExportError.snapshotFailed)) }
                return
            }

            let image = draw(
                on: snapshot,
                coordinates: coordinates,
                recording: recording,
                unit: unit,
                accentTheme: accentTheme,
                colorBySpeed: colorBySpeed
            )

            guard let data = image.pngData() else {
                DispatchQueue.main.async { completion(.failure(ExportError.renderFailed)) }
                return
            }

            let filename = "route-\(Int(recording.date.timeIntervalSince1970)).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                DispatchQueue.main.async { completion(.success(url)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Drawing

    private static func draw(
        on snapshot: MKMapSnapshotter.Snapshot,
        coordinates: [CLLocationCoordinate2D],
        recording: SpeedRecording,
        unit: SpeedUnit,
        accentTheme: AccentTheme,
        colorBySpeed: Bool
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)

        return renderer.image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext

            let points = coordinates.map { snapshot.point(for: $0) }

            // Dark casing under the whole route, so the line stays readable over both
            // light streets and dark satellite imagery — drawn once regardless of coloring.
            let casing = UIBezierPath()
            casing.move(to: points[0])
            for point in points.dropFirst() {
                casing.addLine(to: point)
            }
            casing.lineWidth = 12
            casing.lineJoinStyle = .round
            casing.lineCapStyle = .round
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
            casing.stroke()

            if colorBySpeed && recording.samples.count > 1 {
                // Same ranking-based scale as the on-screen map, so a shared image matches
                // what the rider actually saw.
                let scale = SpeedScale(samples: recording.samples)

                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.setLineWidth(7)

                for i in 0..<(points.count - 1) {
                    let avgSpeed = (recording.samples[i].mph + recording.samples[i + 1].mph) / 2
                    let t = scale.normalized(avgSpeed)
                    cg.setStrokeColor(accentTheme.speedShadeUIColor(t).cgColor)
                    cg.move(to: points[i])
                    cg.addLine(to: points[i + 1])
                    cg.strokePath()
                }
            } else {
                let path = UIBezierPath()
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.lineWidth = 7
                path.lineJoinStyle = .round
                path.lineCapStyle = .round
                cg.setStrokeColor(accentTheme.uiColor.cgColor)
                path.stroke()
            }

            // Start / end markers
            if let start = points.first {
                drawMarker(at: start, fill: .systemGreen, in: cg)
            }
            if let end = points.last {
                drawMarker(at: end, fill: .systemRed, in: cg)
            }

            drawStatsBanner(
                recording: recording,
                unit: unit,
                canvasSize: snapshot.image.size,
                in: cg
            )
        }
    }

    private static func drawMarker(at point: CGPoint, fill: UIColor, in cg: CGContext) {
        let radius: CGFloat = 14
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        cg.setFillColor(UIColor.white.cgColor)
        cg.fillEllipse(in: rect.insetBy(dx: -4, dy: -4))
        cg.setFillColor(fill.cgColor)
        cg.fillEllipse(in: rect)
    }

    private static func drawStatsBanner(
        recording: SpeedRecording,
        unit: SpeedUnit,
        canvasSize: CGSize,
        in cg: CGContext
    ) {
        let bannerHeight: CGFloat = 130
        let bannerRect = CGRect(
            x: 0,
            y: canvasSize.height - bannerHeight,
            width: canvasSize.width,
            height: bannerHeight
        )

        cg.setFillColor(UIColor.black.withAlphaComponent(0.72).cgColor)
        cg.fill(bannerRect)

        let distance = String(
            format: "%.2f %@",
            unit.convertDistance(fromMiles: recording.distanceMiles),
            unit.distanceUnitLabel
        )
        let maxSpeed = String(
            format: "%.0f %@",
            unit.convert(fromMph: recording.maxMph),
            unit.rawValue
        )
        let avgSpeed = String(
            format: "%.0f %@",
            unit.convert(fromMph: recording.avgMph),
            unit.rawValue
        )
        let duration = elapsedLabel(recording.duration)

        let dateText = recording.date.formatted(date: .abbreviated, time: .shortened)
        let statsText = "\(distance)   •   \(duration)   •   Max \(maxSpeed)   •   Avg \(avgSpeed)"

        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ]
        let statsAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor.white
        ]

        NSString(string: dateText).draw(
            at: CGPoint(x: 32, y: bannerRect.minY + 22),
            withAttributes: dateAttributes
        )
        NSString(string: statsText).draw(
            at: CGPoint(x: 32, y: bannerRect.minY + 62),
            withAttributes: statsAttributes
        )
    }

    // MARK: - Region

    private static func boundingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        // Padded so the route isn't flush against the edges, with a floor for very short rides.
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.004),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.4, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

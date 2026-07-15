import SwiftUI
import MapKit

/// Every route you've ever recorded, drawn on one map.
///
/// Each ride is a translucent line. Where routes overlap, the translucency stacks and the
/// path gets brighter — so the roads you ride most often glow, and one-off trips stay faint.
/// That's the whole trick: no density grid, just alpha compositing doing the work.
struct HeatmapView: View {
    @EnvironmentObject var runStore: RunStore
    @EnvironmentObject var settings: SettingsStore

    /// nil = every vehicle.
    @State private var modeFilter: VehicleMode? = nil
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var rides: [SpeedRecording] {
        let all = modeFilter.map { m in runStore.recordings.filter { $0.mode == m } }
            ?? runStore.recordings
        return all.filter { $0.samples.count > 1 }
    }

    var body: some View {
        Group {
            if rides.isEmpty {
                ContentUnavailableView(
                    "No Routes Yet",
                    systemImage: "map",
                    description: Text("Record a few rides and they'll all show up here together.")
                )
            } else {
                mapContent
            }
        }
        .navigationTitle("Heatmap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if runStore.modesWithRides.count > 1 {
                    Menu {
                        Picker("Vehicle", selection: $modeFilter) {
                            Text("All Vehicles").tag(VehicleMode?.none)
                            ForEach(runStore.modesWithRides) { mode in
                                Label(mode.rawValue, systemImage: mode.icon)
                                    .tag(VehicleMode?.some(mode))
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .onAppear { fitToAllRides() }
        .onChange(of: modeFilter) { _, _ in fitToAllRides() }
    }

    private var mapContent: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                ForEach(rides) { ride in
                    MapPolyline(coordinates: coordinates(for: ride))
                        // Low alpha per ride so overlaps accumulate into brighter lines.
                        // Wide, round caps make the buildup read as a glow rather than
                        // a tangle of hairlines.
                        .stroke(
                            settings.accent.color.opacity(0.35),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            .mapStyle(settings.mapStyle.mapStyle)
            .ignoresSafeArea(edges: .bottom)

            summaryBar
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            stat("\(rides.count)", "routes")
            stat(
                String(format: "%.0f", settings.unit.convertDistance(
                    fromMiles: rides.reduce(0) { $0 + $1.distanceMiles }
                )),
                settings.unit.distanceUnitLabel
            )
            if let mode = modeFilter {
                Label(mode.rawValue, systemImage: mode.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
        .padding(.bottom, 20)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func coordinates(for ride: SpeedRecording) -> [CLLocationCoordinate2D] {
        // Downsampled: a heatmap of many rides could otherwise be tens of thousands of
        // points, and at this zoom the detail is invisible anyway.
        downsampled(ride.samples, maxPoints: 150).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    /// Frames the camera so every route is visible at once.
    private func fitToAllRides() {
        let allCoords = rides.flatMap { coordinates(for: $0) }
        guard !allCoords.isEmpty else { return }

        let lats = allCoords.map(\.latitude)
        let lons = allCoords.map(\.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.3, 0.01),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.3, 0.01)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

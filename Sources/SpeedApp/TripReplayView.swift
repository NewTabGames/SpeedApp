import SwiftUI
import MapKit
import Charts

/// Plays a saved ride back: a marker moves along the route while the speed graph
/// scrubs in sync. Scrub manually with the slider, or hit play.
struct TripReplayView: View {
    let recording: SpeedRecording
    @EnvironmentObject var settings: SettingsStore

    @State private var currentIndex: Int = 0
    @State private var isPlaying = false
    @State private var speedMultiplier: Double = 1
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Replay advances on a wall-clock timer rather than stepping one sample per tick,
    /// so playback speed stays consistent regardless of how dense the GPS data is.
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var samples: [SpeedSample] { recording.samples }

    private var coordinates: [CLLocationCoordinate2D] {
        samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var currentSample: SpeedSample? {
        guard samples.indices.contains(currentIndex) else { return samples.last }
        return samples[currentIndex]
    }

    /// The portion of the route already travelled, drawn brighter than the rest.
    private var travelledCoordinates: [CLLocationCoordinate2D] {
        guard currentIndex > 0 else { return [] }
        return Array(coordinates.prefix(currentIndex + 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            mapSection
            graphSection
            controlsSection
        }
        .navigationTitle("Replay")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setInitialCamera() }
        .onReceive(tick) { _ in advanceIfPlaying() }
        .onDisappear { isPlaying = false }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            // Full route, dimmed.
            MapPolyline(coordinates: coordinates)
                .stroke(settings.accent.color.opacity(0.25), lineWidth: 5)

            // Route covered so far, solid.
            if travelledCoordinates.count > 1 {
                MapPolyline(coordinates: travelledCoordinates)
                    .stroke(settings.accent.color, lineWidth: 5)
            }

            if let first = coordinates.first {
                Marker("Start", coordinate: first)
                    .tint(.green)
            }

            // The moving dot.
            if let sample = currentSample {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 22, height: 22)
                        Circle()
                            .fill(settings.accent.color)
                            .frame(width: 14, height: 14)
                    }
                    .shadow(radius: 3)
                }
            }
        }
        .mapStyle(settings.mapStyle.mapStyle)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Graph

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(String(format: "%.0f %@", settings.unit.convert(fromMph: currentSample?.mph ?? 0), settings.unit.rawValue))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(settings.accent.color)
                Text(elapsedLabel(currentSample?.offsetSeconds ?? 0))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal)

            Chart(downsampled(samples, maxPoints: 200)) { sample in
                LineMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("Speed", settings.unit.convert(fromMph: sample.mph))
                )
                .foregroundStyle(settings.accent.color)
                .interpolationMethod(settings.chartLineStyle == .smooth ? .catmullRom : .linear)

                if let current = currentSample {
                    RuleMark(x: .value("Now", current.offsetSeconds))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .frame(height: 100)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>().precision(.fractionLength(0)))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(elapsedLabel(seconds))
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 10)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(currentIndex) },
                    set: { newValue in
                        currentIndex = Int(newValue)
                        recenter()
                    }
                ),
                in: 0...Double(max(samples.count - 1, 1))
            )

            HStack(spacing: 24) {
                Button {
                    currentIndex = 0
                    recenter()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(settings.accent.color)
                }

                Menu {
                    ForEach([1.0, 2.0, 4.0, 8.0], id: \.self) { rate in
                        Button {
                            speedMultiplier = rate
                        } label: {
                            Text("\(Int(rate))×")
                        }
                    }
                } label: {
                    Text("\(Int(speedMultiplier))×")
                        .font(.headline)
                        .frame(width: 44)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    // MARK: - Playback

    private func togglePlayback() {
        // Restarting from the end should replay from the beginning rather than doing nothing.
        if !isPlaying && currentIndex >= samples.count - 1 {
            currentIndex = 0
        }
        isPlaying.toggle()
    }

    private func advanceIfPlaying() {
        guard isPlaying, !samples.isEmpty else { return }

        let currentOffset = currentSample?.offsetSeconds ?? 0
        // 0.1s tick × multiplier = how much ride-time to advance this frame.
        let targetOffset = currentOffset + (0.1 * speedMultiplier)

        guard let nextIndex = samples.firstIndex(where: { $0.offsetSeconds >= targetOffset }) else {
            currentIndex = samples.count - 1
            isPlaying = false
            return
        }

        currentIndex = nextIndex
        recenter()
    }

    // MARK: - Camera

    private func setInitialCamera() {
        guard !coordinates.isEmpty else { return }
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
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    /// Follows the marker while playing, but leaves the camera alone when paused so the
    /// rider can pan and zoom around the route freely.
    private func recenter() {
        guard isPlaying, let sample = currentSample else { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        ))
    }
}

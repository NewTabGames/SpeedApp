import SwiftUI
import MapKit
import Charts

/// Plays a saved ride back: a marker moves along the route while the speed graph
/// scrubs in sync. Scrub manually with the slider, or hit play.
struct TripReplayView: View {
    let recording: SpeedRecording
    @EnvironmentObject var settings: SettingsStore

    /// Route data for DRAWING, downsampled once at init. The map body re-evaluates 20x a
    /// second during playback, and rebuilding two polylines from every raw GPS sample
    /// (an hour ride is ~3,600 points) each time would stutter. ~300 points is visually
    /// identical. Interpolation and the graph still use the full-resolution samples.
    private let drawSamples: [SpeedSample]
    private let drawCoords: [CLLocationCoordinate2D]

    init(recording: SpeedRecording) {
        self.recording = recording
        self.drawSamples = downsampled(recording.samples, maxPoints: 300)
        self.drawCoords = drawSamples.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    /// Continuous playback position in ride-seconds. The marker interpolates between GPS
    /// samples using this, so playback is smooth instead of hopping sample-to-sample —
    /// and at 1× it tracks real wall-clock time.
    @State private var playbackTime: Double = 0
    @State private var isPlaying = false
    @State private var speedMultiplier: Double = 1
    @State private var cameraPosition: MapCameraPosition = .automatic

    // The camera's current orientation, mirrored from the map as the rider moves it.
    //
    // Following the marker used to rebuild the camera as a north-up region on every tick,
    // which threw away any rotation, tilt or zoom the moment it was applied — so the map
    // couldn't be turned while a replay was playing. Keeping these means the follow update
    // only changes *where* the camera is pointed, never how it's oriented.
    @State private var cameraHeading: Double = 0
    @State private var cameraPitch: Double = 0
    @State private var cameraDistance: Double = 800

    /// Whether the camera tracks the marker. Turning it off lets the map be explored freely
    /// while the replay keeps running.
    @State private var followMarker = true

    // Gesture handshake between recenter() and onMapCameraChange. recenter() records what it
    // applied; the change handler compares incoming values against that to tell the rider's
    // gestures apart from our own follow updates, and recenter() pauses briefly during one.
    @State private var lastAppliedHeading: Double = 0
    @State private var lastAppliedPitch: Double = 0
    @State private var lastAppliedDistance: Double = 800
    @State private var lastUserCameraGestureAt: Date?

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var samples: [SpeedSample] { recording.samples }

    private var totalDuration: Double {
        samples.last?.offsetSeconds ?? 0
    }

    private var coordinates: [CLLocationCoordinate2D] {
        samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// The sample at or just before the current playback time.
    private var currentSample: SpeedSample? {
        guard !samples.isEmpty else { return nil }
        let idx = samples.lastIndex { $0.offsetSeconds <= playbackTime } ?? 0
        return samples[idx]
    }

    /// Marker position, interpolated between the surrounding two samples for smoothness.
    private var interpolatedCoordinate: CLLocationCoordinate2D? {
        guard !samples.isEmpty else { return nil }
        guard let afterIdx = samples.firstIndex(where: { $0.offsetSeconds >= playbackTime }) else {
            return coordinates.last
        }
        guard afterIdx > 0 else { return coordinates.first }

        let before = samples[afterIdx - 1]
        let after = samples[afterIdx]
        let span = after.offsetSeconds - before.offsetSeconds
        let t = span > 0 ? (playbackTime - before.offsetSeconds) / span : 0

        return CLLocationCoordinate2D(
            latitude: before.latitude + (after.latitude - before.latitude) * t,
            longitude: before.longitude + (after.longitude - before.longitude) * t
        )
    }

    /// The portion of the route already travelled, drawn brighter than the rest.
    /// Built from the downsampled draw list — see drawSamples.
    private var travelledCoordinates: [CLLocationCoordinate2D] {
        let count = (drawSamples.lastIndex { $0.offsetSeconds <= playbackTime } ?? 0) + 1
        guard count > 1 else { return [] }
        return Array(drawCoords.prefix(count))
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
            // Full route, dimmed. Downsampled — see drawSamples.
            MapPolyline(coordinates: drawCoords)
                .stroke(settings.accent.color.opacity(0.25), lineWidth: 5)

            // Route covered so far, solid.
            if travelledCoordinates.count > 1 {
                MapPolyline(coordinates: travelledCoordinates)
                    .stroke(settings.accent.color, lineWidth: 5)
            }

            if let first = drawCoords.first {
                Marker("Start", coordinate: first)
                    .tint(.green)
            }

            // The moving dot, at the interpolated position for smooth motion.
            if let coordinate = interpolatedCoordinate {
                Annotation("", coordinate: coordinate) {
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
        .mapControls {
            // Compass appears once the map is rotated off north — tap it to snap back.
            MapCompass()
            MapPitchToggle()
        }
        // Continuous, so the values track a rotation gesture as it happens rather than only
        // when it finishes. Without that, the next follow update would fight the gesture and
        // snap the map back mid-rotate.
        .onMapCameraChange(frequency: .continuous) { context in
            // If the camera differs from what recenter() last applied, the change came from
            // the rider's fingers, not from us. Remember when — recenter() backs off briefly
            // so a 20-per-second stream of programmatic camera sets doesn't cancel the
            // gesture mid-pinch or mid-rotate.
            let cam = context.camera
            let isUserGesture =
                abs(cam.heading - lastAppliedHeading) > 1.0 ||
                abs(cam.pitch - lastAppliedPitch) > 1.0 ||
                abs(cam.distance - lastAppliedDistance) > max(lastAppliedDistance * 0.02, 5)
            if isUserGesture {
                lastUserCameraGestureAt = Date()
            }

            cameraHeading = cam.heading
            cameraPitch = cam.pitch
            cameraDistance = cam.distance
        }
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
                Text(elapsedLabel(playbackTime))
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

                RuleMark(x: .value("Now", playbackTime))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
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
                    get: { playbackTime },
                    set: { newValue in
                        playbackTime = newValue
                        recenter()
                    }
                ),
                in: 0...max(totalDuration, 1)
            )

            HStack(spacing: 24) {
                Button {
                    Haptics.tap()
                    playbackTime = 0
                    recenter()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }

                Button {
                    Haptics.tap()
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(settings.accent.color)
                }

                // Lets the camera be released from the marker so the map can be explored
                // while the replay keeps running.
                Button {
                    Haptics.tap()
                    followMarker.toggle()
                    if followMarker { recenter() }
                } label: {
                    Image(systemName: followMarker ? "location.fill.viewfinder" : "location.viewfinder")
                        .font(.title3)
                        .foregroundStyle(followMarker ? settings.accent.color : .secondary)
                }

                Menu {
                    ForEach([0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { rate in
                        Button {
                            Haptics.selection()
                            speedMultiplier = rate
                        } label: {
                            Text(rateLabel(rate))
                        }
                    }
                } label: {
                    Text(rateLabel(speedMultiplier))
                        .font(.headline)
                        .frame(width: 70)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    /// 1× is labeled "Real-time" since that's what the rider asked to be able to watch.
    private func rateLabel(_ rate: Double) -> String {
        if rate == 1.0 { return "Real-time" }
        if rate == 0.5 { return "0.5×" }
        return "\(Int(rate))×"
    }

    // MARK: - Playback

    private func togglePlayback() {
        // Restarting from the end should replay from the beginning.
        if !isPlaying && playbackTime >= totalDuration {
            playbackTime = 0
        }
        isPlaying.toggle()
    }

    private func advanceIfPlaying() {
        guard isPlaying, !samples.isEmpty else { return }

        // 0.05s tick × multiplier = ride-seconds to advance this frame.
        // At 1× (Real-time), one real second of watching = one second of the ride.
        playbackTime += 0.05 * speedMultiplier

        if playbackTime >= totalDuration {
            playbackTime = totalDuration
            isPlaying = false
        }
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

        // Seed the follow camera's zoom from how far the ride ranged, so the first follow
        // update doesn't snap to an arbitrary distance.
        let spread = max(span.latitudeDelta, span.longitudeDelta)
        cameraDistance = min(max(spread * 40_000, 400), 1_500)

        // Seed the gesture-detection baseline too. The initial region set above makes the
        // map report a camera that differs from the defaults these started at, which would
        // register as a phantom "user gesture" the moment the view opens.
        lastAppliedHeading = cameraHeading
        lastAppliedPitch = cameraPitch
        lastAppliedDistance = cameraDistance
    }

    /// Keeps the camera pointed at the marker without touching how it's oriented.
    ///
    /// Builds a MapCamera from the heading/pitch/distance the rider last left the map at,
    /// changing only the centre. The previous version constructed a north-up region here,
    /// which reset any rotation on every frame and made the map impossible to turn during
    /// playback.
    private func recenter() {
        guard followMarker, let coordinate = interpolatedCoordinate else { return }

        // Back off while the rider's fingers are on the map. A programmatic camera set can
        // cancel an in-progress gesture, so recentering 20 times a second while they rotate
        // would make the map judder and fight them. Following resumes moments after the
        // gesture settles, keeping whatever orientation they left it at.
        if let last = lastUserCameraGestureAt, Date().timeIntervalSince(last) < 0.7 {
            return
        }

        lastAppliedHeading = cameraHeading
        lastAppliedPitch = cameraPitch
        lastAppliedDistance = cameraDistance

        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: cameraDistance,
                heading: cameraHeading,
                pitch: cameraPitch
            )
        )
    }
}

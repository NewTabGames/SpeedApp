import Foundation
import CoreLocation
import Combine
import QuartzCore

/// One GPS reading during a recording.
/// `offsetSeconds` is unique within a recording, so it doubles as the identity —
/// no need to store a UUID per sample (at 1 sample/sec that adds up fast).
struct SpeedSample: Codable, Identifiable, Equatable, Sendable {
    let offsetSeconds: Double
    let mph: Double
    let latitude: Double
    let longitude: Double
    var altitudeMeters: Double = 0

    var id: Double { offsetSeconds }

    init(offsetSeconds: Double, mph: Double, latitude: Double, longitude: Double, altitudeMeters: Double = 0) {
        self.offsetSeconds = offsetSeconds
        self.mph = mph
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
    }

    // Hand-written for the same reason as SpeedRecording: `altitudeMeters` was added after
    // rides were already being saved, and the synthesized decoder throws on a missing key
    // rather than using the default. Every sample of every older ride lacks it.
    enum CodingKeys: String, CodingKey {
        case offsetSeconds, mph, latitude, longitude, altitudeMeters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offsetSeconds = try c.decode(Double.self, forKey: .offsetSeconds)
        mph = try c.decode(Double.self, forKey: .mph)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        altitudeMeters = try c.decodeIfPresent(Double.self, forKey: .altitudeMeters) ?? 0
    }
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published state
    @Published var speedMph: Double = 0
    @Published var maxSpeedMph: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var signalQuality: SignalQuality = .acquiring
    @Published var currentLocation: CLLocation?

    /// The speed shown in the UI. GPS only reports about once per second, so instead of
    /// snapping straight to each new reading, this eases toward it every display frame.
    /// The underlying `speedMph` stays the true value used for recording and alerts.
    @Published var displaySpeedMph: Double = 0

    // Recording session
    @Published var isRecording: Bool = false
    @Published var pauseState: PauseState = .running
    @Published var recordingElapsed: Double = 0
    @Published var recordingSamples: [SpeedSample] = []
    @Published var recordingMaxMph: Double = 0
    @Published var recordingAvgMph: Double = 0
    @Published var recordingDistanceMiles: Double = 0
    @Published var recordingElevationGainFt: Double = 0
    @Published var recordingElevationLossFt: Double = 0

    enum SignalQuality {
        case acquiring, weak, good
    }

    /// Manual pause and auto-pause are tracked separately: auto-pause resumes on its own
    /// when you start moving, but a manual pause should stay paused until you say otherwise.
    enum PauseState: Equatable {
        case running
        case manuallyPaused
        case autoPaused
    }

    var isPaused: Bool { pauseState != .running }

    // MARK: - Permission state

    /// No location at all — nothing works.
    var isLocationDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Location works while you're looking at the app, but iOS will cut GPS off the moment
    /// the screen locks. Recording will freeze mid-ride without this being obvious, so it's
    /// worth telling the rider before they set off rather than after they've lost a ride.
    var needsAlwaysPermission: Bool {
        authorizationStatus == .authorizedWhenInUse
    }

    var hasAlwaysPermission: Bool {
        authorizationStatus == .authorizedAlways
    }

    // MARK: - Settings-driven config
    /// Controls how fast the EMA reacts to new readings.
    var smoothingAlpha: Double = 0.6
    /// When true, recording automatically pauses while you're stopped and resumes when you move.
    var autoPauseEnabled: Bool = false

    /// Below this speed you're considered stopped rather than moving. Set from Settings.
    var autoPauseSpeedThreshold: Double = 1.5   // mph
    /// How long you must be under the threshold before auto-pause kicks in. Set from Settings.
    var autoPauseDelay: TimeInterval = 4.0

    /// Speed that counts as moving again after an auto-pause. Deliberately a bit above the
    /// pause threshold — without that gap it would flicker on and off while you creep
    /// forward at a light.
    private var autoResumeSpeedThreshold: Double {
        autoPauseSpeedThreshold + 1.0
    }

    private let manager = CLLocationManager()
    private var displayLink: CADisplayLink?

    // Recording state
    private var recordingStartDate: Date?
    private var recordingSpeedSum: Double = 0
    private var recordingSampleCount: Int = 0
    private var lastDistanceLocation: CLLocation?
    private var lastAltitudeMeters: Double?

    // Pause bookkeeping
    private var pausedAccumulated: TimeInterval = 0
    private var pauseBeganAt: Date?
    private var stoppedSince: Date?

    // Exponential moving average smoothing
    private var emaSpeed: Double? = nil

    // GPS-gap watchdog
    /// When the last usable fix arrived. The display link checks this every frame.
    private var lastFixAt: Date?
    /// How long without a fix before the speed is zeroed and the signal shows "acquiring".
    private let gpsGapTimeout: TimeInterval = 4.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        // Keeps the little arrow in the status bar while recording in the background, which
        // iOS requires for background location. Nothing pops up unexpectedly.
        manager.showsBackgroundLocationIndicator = true
        // Don't let iOS auto-pause updates when it thinks you've stopped — we handle pausing
        // ourselves, and its heuristic is tuned for walking/driving, not scooters.
        manager.pausesLocationUpdatesAutomatically = false
        // Start from the real status rather than assuming notDetermined, so any permission
        // warning is correct on the very first frame instead of flickering in.
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        // "Always" is what allows recording to continue while the phone is locked. iOS first
        // grants "When In Use" and later prompts to upgrade to Always after seeing background use.
        manager.requestAlwaysAuthorization()
    }

    /// Re-reads the current authorization. Called when the app returns to the foreground, so
    /// that changing the setting in iOS Settings is reflected immediately rather than showing
    /// a stale warning.
    func refreshAuthorizationStatus() {
        authorizationStatus = manager.authorizationStatus
    }

    deinit {
        displayLink?.invalidate()
    }

    func start() {
        manager.startUpdatingLocation()
        startDisplayLink()
    }

    func stop() {
        manager.stopUpdatingLocation()
        stopDisplayLink()
    }

    func resetMaxSpeed() {
        maxSpeedMph = 0
    }

    /// Tells CoreLocation what kind of movement to expect. Walking and driving have very
    /// different motion profiles, and this tunes its internal filtering accordingly.
    func applyVehicleMode(_ mode: VehicleMode) {
        manager.activityType = mode.activityType
    }

    /// Battery saver trades some precision/update frequency for meaningfully less power draw.
    func applyAccuracyMode(_ mode: GPSAccuracyMode) {
        switch mode {
        case .highAccuracy:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
        case .batterySaver:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 5
        }
    }

    // MARK: - Smooth display interpolation

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepDisplaySpeed))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Runs every display frame (~60fps). Eases the shown number toward the real GPS
    /// speed so it counts up/down smoothly rather than jumping once per second.
    ///
    /// Also doubles as the GPS watchdog, since it ticks whether or not fixes arrive:
    /// - If no fix has come in for a few seconds (tunnel, indoors), the speed is zeroed and
    ///   the signal indicator drops to "acquiring". Without this the speedometer freezes at
    ///   the last value forever — showing a confident 17 mph while standing still inside.
    /// - The ride timer is recomputed here too. It used to advance only on GPS fixes, so a
    ///   signal gap stalled the clock even though the ride was very much still happening.
    ///
    /// Only assigns when the value actually changes — `displaySpeedMph` is @Published, and
    /// assigning fires a change notification even for an identical value, which would
    /// re-render every observing view 60x/sec forever while parked.
    @objc private func stepDisplaySpeed() {
        // GPS-gap watchdog.
        if let last = lastFixAt, Date().timeIntervalSince(last) > gpsGapTimeout {
            if speedMph != 0 {
                speedMph = 0
                // Reset the average so the first fix after the gap starts fresh rather than
                // being blended with a stale pre-gap speed.
                emaSpeed = nil
            }
            if signalQuality != .acquiring {
                signalQuality = .acquiring
            }
        }

        // Keep the ride timer honest through GPS gaps. Throttled to ~4 updates/sec — it's a
        // whole-second label, and assigning a @Published 60x/sec re-renders for nothing.
        if isRecording, !isPaused, let start = recordingStartDate {
            let openPause = pauseBeganAt.map { Date().timeIntervalSince($0) } ?? 0
            let elapsed = max(Date().timeIntervalSince(start) - pausedAccumulated - openPause, 0)
            if elapsed - recordingElapsed >= 0.25 {
                recordingElapsed = elapsed
            }
        }

        let target = speedMph
        let delta = target - displaySpeedMph

        if abs(delta) < 0.05 {
            if displaySpeedMph != target {
                displaySpeedMph = target
            }
            return
        }
        displaySpeedMph += delta * 0.12
    }

    // MARK: - Recording

    func startRecording() {
        // Allow GPS to keep flowing while the phone is locked or the app is backgrounded.
        // Only enabled during recording so it's not draining the battery the rest of the time.
        manager.allowsBackgroundLocationUpdates = true

        isRecording = true
        pauseState = .running
        recordingStartDate = Date()
        recordingElapsed = 0
        recordingSamples = []
        recordingMaxMph = 0
        recordingAvgMph = 0
        recordingDistanceMiles = 0
        recordingElevationGainFt = 0
        recordingElevationLossFt = 0
        recordingSpeedSum = 0
        recordingSampleCount = 0
        lastDistanceLocation = nil
        lastAltitudeMeters = nil
        pausedAccumulated = 0
        pauseBeganAt = nil
        stoppedSince = nil
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        beginPause(state: .manuallyPaused)
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        endPause()
    }

    private func beginPause(state: PauseState) {
        pauseState = state
        pauseBeganAt = Date()
    }

    private func endPause() {
        if let began = pauseBeganAt {
            pausedAccumulated += Date().timeIntervalSince(began)
        }
        pauseBeganAt = nil
        pauseState = .running
        stoppedSince = nil

        // Drop the pre-pause anchor so the gap you may have travelled while paused
        // isn't counted as distance or elevation. The route polyline will simply draw a
        // straight line from the last point before the pause to the first one after it.
        lastDistanceLocation = nil
        lastAltitudeMeters = nil
    }

    @discardableResult
    func stopRecording() -> RecordingResult? {
        guard isRecording, let start = recordingStartDate else { return nil }

        // Fold in any time still sitting in an open pause.
        if let began = pauseBeganAt {
            pausedAccumulated += Date().timeIntervalSince(began)
            pauseBeganAt = nil
        }

        isRecording = false
        pauseState = .running
        // Ride's over — stop keeping the GPS awake in the background.
        manager.allowsBackgroundLocationUpdates = false

        let duration = Date().timeIntervalSince(start) - pausedAccumulated
        let result = RecordingResult(
            samples: recordingSamples,
            maxMph: recordingMaxMph,
            avgMph: recordingAvgMph,
            duration: max(duration, 0),
            distanceMiles: recordingDistanceMiles,
            elevationGainFt: recordingElevationGainFt,
            elevationLossFt: recordingElevationLossFt
        )
        recordingStartDate = nil
        return result
    }

    struct RecordingResult {
        let samples: [SpeedSample]
        let maxMph: Double
        let avgMph: Double
        let duration: Double
        let distanceMiles: Double
        let elevationGainFt: Double
        let elevationLossFt: Double
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            start()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Ignore cached fixes. Right after startUpdatingLocation, iOS replays the last known
        // location — which can be minutes old and from wherever you last had signal. Letting
        // one through puts a bogus first point in a recording (and a long phantom line from
        // there to your real position).
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }

        // Reject clearly invalid fixes outright (negative accuracy = no fix).
        if location.horizontalAccuracy < 0 {
            signalQuality = .weak
            return
        }

        currentLocation = location
        lastFixAt = Date()

        // CLLocation.speed is -1 when the device couldn't work out a speed for this fix
        // (common under bridges and in tunnels). The old code clamped that to 0, feeding a
        // false "0 mph" into the smoothing — the speedometer would randomly dip toward zero
        // mid-ride, and a couple of such fixes in a row could trigger a false auto-pause.
        // An invalid speed now just holds the previous value instead.
        let speedIsValid = location.speed >= 0
        // speedAccuracy is the reading's uncertainty in m/s (negative = unknown). Above
        // ~4 m/s (~9 mph of slop) the number is too mushy to trust for records.
        let speedIsTrustworthy = speedIsValid
            && (location.speedAccuracy < 0 || location.speedAccuracy <= 4)

        signalQuality = speedIsTrustworthy ? .good : .weak

        if speedIsValid {
            let mph = location.speed * 2.236936
            let smoothed: Double
            if let previous = emaSpeed {
                smoothed = smoothingAlpha * mph + (1 - smoothingAlpha) * previous
            } else {
                smoothed = mph
            }
            emaSpeed = smoothed

            // The live speedometer always updates from a valid reading, even a mushy one —
            // but only trustworthy readings are allowed to set the max-speed record, so a
            // single glitchy fix can't hand you a fake 70 mph personal best (or a false
            // speed-limit alert).
            speedMph = smoothed
            if speedIsTrustworthy, smoothed > maxSpeedMph {
                maxSpeedMph = smoothed
            }
        }

        handleAutoPause(currentMph: speedMph)

        // Always call this so the ride timer keeps advancing. Whether this fix is precise
        // enough to add to the route is decided inside, so a loose-GPS patch doesn't stall
        // the clock — it just leaves a small gap in the drawn path.
        handleRecordingLogic(currentMph: speedMph, location: location)
    }

    /// Watches for you sitting still and pauses the recording, then unpauses when you move again.
    /// Only touches `.autoPaused` — a manual pause is left alone.
    private func handleAutoPause(currentMph: Double) {
        guard isRecording, autoPauseEnabled else { return }

        switch pauseState {
        case .running:
            if currentMph < autoPauseSpeedThreshold {
                if let since = stoppedSince {
                    if Date().timeIntervalSince(since) >= autoPauseDelay {
                        beginPause(state: .autoPaused)
                    }
                } else {
                    stoppedSince = Date()
                }
            } else {
                stoppedSince = nil
            }

        case .autoPaused:
            if currentMph >= autoResumeSpeedThreshold {
                endPause()
            }

        case .manuallyPaused:
            break
        }
    }

    private func handleRecordingLogic(currentMph: Double, location: CLLocation) {
        guard isRecording, let start = recordingStartDate else { return }

        // Elapsed excludes any time spent paused. Updated on every fix so the timer never
        // stalls, even during a low-accuracy GPS patch.
        let openPause = pauseBeganAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingElapsed = max(Date().timeIntervalSince(start) - pausedAccumulated - openPause, 0)

        // While paused we stop collecting entirely — no samples, no distance, no elevation.
        guard !isPaused else { return }

        // Only add high-confidence fixes to the route. On a path near a parallel road, loose
        // fixes (>30 m error) are what make the drawn line jump onto the street. The live
        // speedometer already updated from this fix regardless; this only gates the recording.
        guard location.horizontalAccuracy <= 30 else { return }

        recordingSamples.append(SpeedSample(
            offsetSeconds: recordingElapsed,
            mph: currentMph,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitudeMeters: location.altitude
        ))

        recordingSampleCount += 1
        recordingSpeedSum += currentMph
        recordingAvgMph = recordingSpeedSum / Double(recordingSampleCount)
        if currentMph > recordingMaxMph {
            recordingMaxMph = currentMph
        }

        accumulateDistance(to: location)
        accumulateElevation(from: location)
    }

    private func accumulateDistance(to location: CLLocation) {
        defer { lastDistanceLocation = location }
        guard let previous = lastDistanceLocation else { return }

        let meters = location.distance(from: previous)
        // GPS drifts a few metres even when stationary. Ignoring tiny hops keeps a parked
        // scooter from slowly racking up distance.
        guard meters > 1.0 else { return }
        recordingDistanceMiles += meters / 1609.34
    }

    /// GPS altitude is much noisier than horizontal position, so this only counts a change
    /// once it exceeds a threshold. Without that, normal jitter would inflate both numbers.
    private func accumulateElevation(from location: CLLocation) {
        guard location.verticalAccuracy >= 0, location.verticalAccuracy < 10 else { return }
        let altitude = location.altitude

        guard let previous = lastAltitudeMeters else {
            lastAltitudeMeters = altitude
            return
        }

        let change = altitude - previous
        let thresholdMeters = 1.5
        guard abs(change) >= thresholdMeters else { return }

        let feet = abs(change) * 3.28084
        if change > 0 {
            recordingElevationGainFt += feet
        } else {
            recordingElevationLossFt += feet
        }
        lastAltitudeMeters = altitude
    }
}

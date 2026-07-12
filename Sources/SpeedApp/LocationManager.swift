import Foundation
import CoreLocation
import Combine
import QuartzCore

/// One GPS reading during a recording.
/// `offsetSeconds` is unique within a recording, so it doubles as the identity —
/// no need to store a UUID per sample (at 1 sample/sec that adds up fast).
struct SpeedSample: Codable, Identifiable, Equatable {
    let offsetSeconds: Double
    let mph: Double
    let latitude: Double
    let longitude: Double

    var id: Double { offsetSeconds }
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published state
    @Published var speedMph: Double = 0
    @Published var maxSpeedMph: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var signalQuality: SignalQuality = .acquiring
    @Published var currentLocation: CLLocation?

    // Recording session
    @Published var isRecording: Bool = false
    @Published var recordingElapsed: Double = 0
    @Published var recordingSamples: [SpeedSample] = []
    @Published var recordingMaxMph: Double = 0
    @Published var recordingAvgMph: Double = 0
    @Published var recordingDistanceMiles: Double = 0

    enum SignalQuality {
        case acquiring, weak, good
    }

    /// Set by SettingsStore; controls how fast the EMA reacts to new readings.
    var smoothingAlpha: Double = 0.6

    /// The speed shown in the UI. GPS only reports about once per second, so instead of
    /// snapping straight to each new reading, this eases toward it every display frame.
    /// The underlying `speedMph` stays the true value used for recording and alerts.
    @Published var displaySpeedMph: Double = 0
    private var displayLink: CADisplayLink?

    private let manager = CLLocationManager()

    // Recording state
    private var recordingStartDate: Date?
    private var recordingSpeedSum: Double = 0
    private var recordingSampleCount: Int = 0
    private var recordingDistanceMeters: Double = 0
    private var lastRecordingLocation: CLLocation?

    // Exponential moving average smoothing
    private var emaSpeed: Double? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
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
    /// Important: this only assigns when the value actually changes. `displaySpeedMph` is
    /// @Published, and assigning to it fires a change notification even if the new value is
    /// identical — which would re-render every observing view 60x/sec forever while parked.
    @objc private func stepDisplaySpeed() {
        let target = speedMph
        let delta = target - displaySpeedMph

        if abs(delta) < 0.05 {
            if displaySpeedMph != target {
                displaySpeedMph = target
            }
            return
        }
        // ~12% of the gap per frame lands on the target in roughly a second,
        // which matches the GPS update interval without lagging behind it.
        displaySpeedMph += delta * 0.12
    }

    func resetMaxSpeed() {
        maxSpeedMph = 0
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

    // MARK: - Recording

    func startRecording() {
        isRecording = true
        recordingStartDate = Date()
        recordingElapsed = 0
        recordingSamples = []
        recordingMaxMph = 0
        recordingAvgMph = 0
        recordingSpeedSum = 0
        recordingSampleCount = 0
        recordingDistanceMeters = 0
        recordingDistanceMiles = 0
        lastRecordingLocation = nil
    }

    @discardableResult
    func stopRecording() -> (samples: [SpeedSample], maxMph: Double, avgMph: Double, duration: Double, distanceMiles: Double)? {
        guard isRecording, let start = recordingStartDate else { return nil }
        isRecording = false
        let duration = Date().timeIntervalSince(start)
        let result = (recordingSamples, recordingMaxMph, recordingAvgMph, duration, recordingDistanceMiles)
        recordingStartDate = nil
        return result
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

        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 65 {
            signalQuality = .weak
            return
        }

        let rawSpeedMps = max(location.speed, 0)
        let mph = rawSpeedMps * 2.236936

        if location.speedAccuracy >= 0 && location.speedAccuracy > 4 {
            signalQuality = .weak
        } else {
            signalQuality = .good
        }
        currentLocation = location

        let smoothed: Double
        if let previous = emaSpeed {
            smoothed = smoothingAlpha * mph + (1 - smoothingAlpha) * previous
        } else {
            smoothed = mph
        }
        emaSpeed = smoothed

        speedMph = smoothed
        if smoothed > maxSpeedMph {
            maxSpeedMph = smoothed
        }

        handleRecordingLogic(currentMph: smoothed, location: location)
    }

    private func handleRecordingLogic(currentMph: Double, location: CLLocation) {
        guard isRecording, let start = recordingStartDate else { return }
        let elapsed = Date().timeIntervalSince(start)
        recordingElapsed = elapsed

        recordingSamples.append(SpeedSample(
            offsetSeconds: elapsed,
            mph: currentMph,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))
        recordingSampleCount += 1
        recordingSpeedSum += currentMph
        recordingAvgMph = recordingSpeedSum / Double(recordingSampleCount)
        if currentMph > recordingMaxMph {
            recordingMaxMph = currentMph
        }

        if let last = lastRecordingLocation {
            let deltaMeters = location.distance(from: last)
            // Ignore GPS jitter while stationary so distance doesn't creep up when parked
            if deltaMeters > 1 {
                recordingDistanceMeters += deltaMeters
                recordingDistanceMiles = recordingDistanceMeters / 1609.34
            }
        }
        lastRecordingLocation = location
    }
}

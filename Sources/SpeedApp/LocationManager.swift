import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published state
    @Published var speedMph: Double = 0
    @Published var maxSpeedMph: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Timer results, published so views update live
    @Published var zeroToSixtySeconds: Double? = nil
    @Published var zeroToHundredSeconds: Double? = nil
    @Published var isTiming: Bool = false

    private let manager = CLLocationManager()

    // Timing state machine
    private var timingStartDate: Date?
    private var hitSixty = false
    private var hitHundred = false

    // Smoothing: raw GPS speed can jitter, so we lightly average
    private var recentSpeeds: [Double] = []
    private let smoothingWindow = 3

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func resetMaxSpeed() {
        maxSpeedMph = 0
    }

    /// Arms the timer; it will automatically start counting once speed crosses above ~1 mph from a stop.
    func armTimer() {
        isTiming = true
        hitSixty = false
        hitHundred = false
        zeroToSixtySeconds = nil
        zeroToHundredSeconds = nil
        timingStartDate = nil
    }

    func cancelTimer() {
        isTiming = false
        timingStartDate = nil
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

        // CLLocation.speed is meters/second, negative when invalid
        let rawSpeedMps = max(location.speed, 0)
        let mph = rawSpeedMps * 2.236936

        recentSpeeds.append(mph)
        if recentSpeeds.count > smoothingWindow {
            recentSpeeds.removeFirst()
        }
        let smoothed = recentSpeeds.reduce(0, +) / Double(recentSpeeds.count)

        speedMph = smoothed
        if smoothed > maxSpeedMph {
            maxSpeedMph = smoothed
        }

        handleTimingLogic(currentMph: smoothed)
    }

    private func handleTimingLogic(currentMph: Double) {
        guard isTiming else { return }

        // Wait for a rolling start: begin the clock once we leave a near-stop
        if timingStartDate == nil {
            if currentMph < 1.0 {
                // still stopped, waiting to launch
                return
            } else {
                timingStartDate = Date()
            }
        }

        guard let start = timingStartDate else { return }
        let elapsed = Date().timeIntervalSince(start)

        if !hitSixty && currentMph >= 60 {
            hitSixty = true
            zeroToSixtySeconds = elapsed
        }
        if !hitHundred && currentMph >= 100 {
            hitHundred = true
            zeroToHundredSeconds = elapsed
            isTiming = false // run complete
        }
    }
}

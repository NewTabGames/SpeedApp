import Foundation
import MapKit
import Combine
import AVFoundation

/// Handles destination search, route calculation, spoken turn-by-turn guidance,
/// and rerouting when you leave the planned route.
final class NavigationStore: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    // Search
    @Published var searchQuery: String = "" {
        didSet { completer.queryFragment = searchQuery }
    }
    @Published var suggestions: [MKLocalSearchCompletion] = []

    // Destination + route
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    @Published var destinationName: String = ""
    @Published var route: MKRoute?
    @Published var isCalculatingRoute: Bool = false

    // Active navigation state
    @Published var isNavigating: Bool = false
    @Published var isRerouting: Bool = false
    @Published var isOffRoute: Bool = false
    @Published var currentInstruction: String = "Continue"
    @Published var distanceToNextManeuverMeters: Double = 0
    @Published var distanceRemainingMeters: Double = 0
    @Published var etaMinutes: Double = 0
    @Published var arrived: Bool = false
    @Published var voiceEnabled: Bool = true

    /// Set externally from SettingsStore; 0.3 (slow/clear) to 0.6 (fast/natural).
    var speechRate: Float = 0.5

    private let completer = MKLocalSearchCompleter()
    private let synthesizer = AVSpeechSynthesizer()

    // Guidance state
    private var stepIndex: Int = 0
    /// Which steps we've already given the early "in 500 feet…" warning for.
    private var earlyAnnouncedSteps: Set<Int> = []
    /// Which steps we've already given the final "turn now" call for.
    private var finalAnnouncedSteps: Set<Int> = []

    // Off-route detection
    /// Cached route geometry, so we're not pulling points out of the polyline on every fix.
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var consecutiveOffRouteFixes: Int = 0
    private var lastRerouteAt: Date?

    // MARK: - Tuning
    /// How far off the line you can be before it counts as off-route. GPS in a city drifts
    /// a fair bit, and roads are wide, so this can't be tight or it'd reroute constantly.
    private let offRouteThresholdMeters: Double = 55
    /// How many consecutive off-route fixes before rerouting. Requiring several in a row
    /// means one bad GPS reading can't trigger a reroute on its own.
    private let offRouteFixesBeforeReroute: Int = 3
    /// Minimum gap between reroutes, so a bad GPS patch can't cause a storm of them.
    private let rerouteCooldown: TimeInterval = 8

    /// Distance at which you get the heads-up announcement ("in 500 feet, turn right").
    private let earlyWarningMeters: Double = 150
    /// Distance at which you get the final call ("turn right").
    private let finalCallMeters: Double = 35
    /// Distance at which the maneuver counts as done and we move to the next one.
    private let maneuverPassedMeters: Double = 20

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Biases search suggestions toward wherever the rider actually is.
    func updateSearchRegion(around coordinate: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    }

    // MARK: - Search

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }

    func clearSearch() {
        searchQuery = ""
        suggestions = []
    }

    // MARK: - Destination selection

    func selectSuggestion(_ suggestion: MKLocalSearchCompletion, currentCoordinate: CLLocationCoordinate2D?) {
        let request = MKLocalSearch.Request(completion: suggestion)
        isCalculatingRoute = true
        MKLocalSearch(request: request).start { [weak self] response, _ in
            guard let self else { return }
            guard let item = response?.mapItems.first else {
                self.isCalculatingRoute = false
                return
            }
            self.destinationCoordinate = item.placemark.coordinate
            self.destinationName = suggestion.title
            self.clearSearch()

            if let currentCoordinate {
                self.calculateRoute(from: currentCoordinate, to: item.placemark.coordinate)
            } else {
                self.isCalculatingRoute = false
            }
        }
    }

    /// Sets a destination straight from a coordinate the rider tapped or long-pressed.
    func setDestination(coordinate: CLLocationCoordinate2D,
                        name: String? = nil,
                        currentCoordinate: CLLocationCoordinate2D?) {
        destinationCoordinate = coordinate
        clearSearch()

        if let name, !name.isEmpty {
            destinationName = name
        } else {
            destinationName = "Dropped Pin"
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                guard let self, let placemark = placemarks?.first else { return }
                let label = placemark.name
                    ?? [placemark.thoroughfare, placemark.locality].compactMap { $0 }.joined(separator: ", ")
                if !label.isEmpty {
                    self.destinationName = label
                }
            }
        }

        if let currentCoordinate {
            calculateRoute(from: currentCoordinate, to: coordinate)
        }
    }

    func cancelDestination() {
        route = nil
        routeCoordinates = []
        destinationCoordinate = nil
        destinationName = ""
        isNavigating = false
        isRerouting = false
        isOffRoute = false
        arrived = false
        resetGuidanceState()
    }

    // MARK: - Routing

    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        isCalculatingRoute = true
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile

        MKDirections(request: request).calculate { [weak self] response, _ in
            guard let self else { return }
            self.isCalculatingRoute = false
            guard let route = response?.routes.first else { return }
            self.apply(route: route)
        }
    }

    private func apply(route: MKRoute) {
        self.route = route
        self.routeCoordinates = route.polyline.coordinates
        self.distanceRemainingMeters = route.distance
        self.etaMinutes = route.expectedTravelTime / 60
        resetGuidanceState()
    }

    private func resetGuidanceState() {
        stepIndex = 0
        earlyAnnouncedSteps = []
        finalAnnouncedSteps = []
        consecutiveOffRouteFixes = 0
    }

    // MARK: - Turn-by-turn

    func startNavigation() {
        guard route != nil else { return }
        isNavigating = true
        arrived = false
        resetGuidanceState()
        advanceToFirstRealStep()
        announceCurrentStep(prefix: nil)
    }

    func stopNavigation() {
        synthesizer.stopSpeaking(at: .immediate)
        cancelDestination()
    }

    /// MapKit's first step is usually a filler like "Proceed to X" with the maneuver point
    /// sitting right on top of you. Skip past anything that isn't a real instruction.
    private func advanceToFirstRealStep() {
        guard let route else { return }
        while stepIndex < route.steps.count,
              route.steps[stepIndex].instructions.trimmingCharacters(in: .whitespaces).isEmpty {
            stepIndex += 1
        }
    }

    /// Call on every fresh GPS fix while navigating.
    func updateProgress(currentLocation: CLLocation) {
        guard isNavigating, let route, !isRerouting else { return }

        checkOffRoute(currentLocation: currentLocation)
        guard !isRerouting else { return }

        guard stepIndex < route.steps.count else { return }
        let step = route.steps[stepIndex]
        guard step.polyline.pointCount > 0 else {
            advanceStep()
            return
        }

        let maneuverCoordinate = step.polyline.points()[0].coordinate
        let maneuverLocation = CLLocation(
            latitude: maneuverCoordinate.latitude,
            longitude: maneuverCoordinate.longitude
        )
        let distance = currentLocation.distance(from: maneuverLocation)
        distanceToNextManeuverMeters = distance

        // Remaining distance: how far to the end of the route along the remaining steps.
        distanceRemainingMeters = distance + route.steps
            .dropFirst(stepIndex + 1)
            .reduce(0) { $0 + $1.distance }

        // Two announcements per turn, like a real nav app: a heads-up, then the final call.
        if distance <= earlyWarningMeters, !earlyAnnouncedSteps.contains(stepIndex) {
            earlyAnnouncedSteps.insert(stepIndex)
            announceCurrentStep(prefix: "In \(spokenDistance(distance)),")
        }
        if distance <= finalCallMeters, !finalAnnouncedSteps.contains(stepIndex) {
            finalAnnouncedSteps.insert(stepIndex)
            announceCurrentStep(prefix: nil)
        }
        if distance <= maneuverPassedMeters {
            advanceStep()
        }
    }

    private func advanceStep() {
        guard let route else { return }
        stepIndex += 1

        if stepIndex >= route.steps.count {
            arrived = true
            isNavigating = false
            speak("You have arrived at your destination.")
        } else if route.steps[stepIndex].instructions.trimmingCharacters(in: .whitespaces).isEmpty {
            advanceStep()
        } else {
            currentInstruction = route.steps[stepIndex].instructions
        }
    }

    private func announceCurrentStep(prefix: String?) {
        guard let route, stepIndex < route.steps.count else { return }
        let instruction = route.steps[stepIndex].instructions
        guard !instruction.isEmpty else { return }

        currentInstruction = instruction
        if let prefix {
            speak("\(prefix) \(instruction)")
        } else {
            speak(instruction)
        }
    }

    // MARK: - Off-route detection and rerouting

    /// Measures how far the rider is from the planned route, and kicks off a recalculation
    /// once they've been clearly off it for several fixes in a row.
    private func checkOffRoute(currentLocation: CLLocation) {
        guard !routeCoordinates.isEmpty, let destination = destinationCoordinate else { return }

        let distanceFromRoute = distanceToRoute(from: currentLocation)
        isOffRoute = distanceFromRoute > offRouteThresholdMeters

        guard isOffRoute else {
            consecutiveOffRouteFixes = 0
            return
        }

        consecutiveOffRouteFixes += 1
        guard consecutiveOffRouteFixes >= offRouteFixesBeforeReroute else { return }

        // Don't reroute again immediately after the last one.
        if let last = lastRerouteAt, Date().timeIntervalSince(last) < rerouteCooldown {
            return
        }

        reroute(from: currentLocation.coordinate, to: destination)
    }

    private func reroute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        isRerouting = true
        lastRerouteAt = Date()
        consecutiveOffRouteFixes = 0
        speak("Recalculating.")

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile

        MKDirections(request: request).calculate { [weak self] response, _ in
            guard let self else { return }
            self.isRerouting = false

            guard let newRoute = response?.routes.first else {
                // Routing failed (no signal, etc). Keep the old route rather than dropping
                // guidance entirely, and let the next off-route streak try again.
                return
            }

            self.apply(route: newRoute)
            self.isOffRoute = false
            self.advanceToFirstRealStep()
            self.announceCurrentStep(prefix: nil)
        }
    }

    /// Shortest distance from a point to the route line.
    ///
    /// Measured against line segments, not just the vertices. Polyline points can be tens of
    /// metres apart on a straight road, so nearest-vertex alone would report you as far off
    /// route while you're driving straight down the middle of it.
    private func distanceToRoute(from location: CLLocation) -> Double {
        let point = MKMapPoint(location.coordinate)
        var shortest = Double.greatestFiniteMagnitude

        for i in 0..<(routeCoordinates.count - 1) {
            let a = MKMapPoint(routeCoordinates[i])
            let b = MKMapPoint(routeCoordinates[i + 1])
            shortest = min(shortest, distance(from: point, toSegment: a, b))
        }

        // MKMapPoint distances are in map units; convert to metres at this latitude.
        return shortest * MKMetersPerMapPointAtLatitude(location.coordinate.latitude)
    }

    /// Perpendicular distance from a point to a line segment, in map points.
    private func distance(from point: MKMapPoint, toSegment a: MKMapPoint, _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y

        if dx == 0 && dy == 0 {
            return hypot(point.x - a.x, point.y - a.y)
        }

        // How far along the segment the closest point lies, clamped to the segment itself.
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)
        t = max(0, min(1, t))

        let closestX = a.x + t * dx
        let closestY = a.y + t * dy
        return hypot(point.x - closestX, point.y - closestY)
    }

    // MARK: - Speech

    private func spokenDistance(_ meters: Double) -> String {
        let feet = meters * 3.28084
        if feet < 1000 {
            // Round to the nearest 50 ft — "in 347 feet" sounds robotic.
            let rounded = (feet / 50).rounded() * 50
            return "\(Int(rounded)) feet"
        }
        let miles = meters / 1609.34
        return String(format: "%.1f miles", miles)
    }

    private func speak(_ text: String) {
        guard voiceEnabled, !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = speechRate
        synthesizer.speak(utterance)
    }
}

// MARK: - Polyline helpers

extension MKPolyline {
    /// Pulls the coordinates out of a polyline. MapKit only exposes them as a raw buffer.
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

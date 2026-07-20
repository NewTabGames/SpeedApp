import Foundation
import MapKit
import Combine
import AVFoundation

/// Handles destination search, route calculation, spoken turn-by-turn guidance,
/// and rerouting when you leave the planned route.
final class NavigationStore: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, AVSpeechSynthesizerDelegate {

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
    @Published var voiceEnabled: Bool = true {
        didSet {
            // Muting should shut up mid-sentence and hand the audio session straight back,
            // not wait for the current direction to finish reading out over the music.
            if !voiceEnabled {
                synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    /// Set externally from SettingsStore; 0.3 (slow/clear) to 0.6 (fast/natural).
    var speechRate: Float = 0.5
    /// Whether spoken distances use metres/kilometres. The on-screen banner already follows
    /// the chosen unit; without this the voice said "in 500 feet" to km/h users.
    var usesMetricUnits: Bool = false
    /// Chosen voice identifier; resolved to an actual voice at speak time.
    var voiceIdentifier: String = VoiceCatalog.systemDefaultID
    /// Routing profile for the current vehicle. Walking gets footpath routes; everything
    /// else uses road routing (MapKit has no scooter or motorcycle profile).
    var transportType: MKDirectionsTransportType = .automobile

    private let completer = MKLocalSearchCompleter()
    private let synthesizer = AVSpeechSynthesizer()

    // Guidance state
    private var stepIndex: Int = 0
    /// Which steps we've already given the early "in 500 feet…" warning for.
    private var earlyAnnouncedSteps: Set<Int> = []
    /// Which steps we've already given the final "turn now" call for.
    private var finalAnnouncedSteps: Set<Int> = []
    /// Nearest we've been to the current step's maneuver point. Used to detect passing a
    /// turn during a GPS gap (see updateProgress). Reset on every step change.
    private var closestApproachMeters: Double = .greatestFiniteMagnitude

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
        synthesizer.delegate = self
    }

    private var lastSearchRegionCenter: CLLocationCoordinate2D?

    /// Biases search suggestions toward wherever the rider actually is.
    ///
    /// Called on every GPS fix, but only actually updates after ~250 m of movement.
    /// Re-setting the completer's region can restart its suggestion fetch, and doing that
    /// once a second while someone is mid-typing makes the suggestions list flicker.
    func updateSearchRegion(around coordinate: CLLocationCoordinate2D) {
        if let last = lastSearchRegionCenter {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard moved > 250 else { return }
        }
        lastSearchRegionCenter = coordinate
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
        // Releasing here (not only in stopNavigation) matters because arrival ends
        // navigation through this path: the "You've Arrived" alert's OK button calls
        // cancelDestination directly, and without this the audio session claimed at
        // navigation start would be held forever after arriving.
        releaseAudioSession()
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
        request.transportType = transportType

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
        closestApproachMeters = .greatestFiniteMagnitude
        consecutiveOffRouteFixes = 0
    }

    // MARK: - Turn-by-turn

    func startNavigation() {
        guard route != nil else { return }
        // Claimed for the whole navigation session so speech keeps working with the screen
        // off. iOS won't let a backgrounded app activate a session from cold.
        activateAudioSession()
        isNavigating = true
        arrived = false
        resetGuidanceState()
        advanceToFirstRealStep()
        announceCurrentStep(prefix: nil, priority: .critical)
    }

    func stopNavigation() {
        synthesizer.stopSpeaking(at: .immediate)
        releaseAudioSession()
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
            // Critical: this is the "turn now" call. Suppressing it to respect a cooldown
            // would mean silently letting the rider miss the turn.
            announceCurrentStep(prefix: nil, priority: .critical)
        }

        // Step advance, two ways:
        // 1. The normal case — we got a fix within a few metres of the maneuver point.
        // 2. The GPS-gap case — the fix stream skipped right over the turn (an overpass or
        //    tunnel at exactly the wrong moment), so no fix ever landed inside that window.
        //    Detect it by closest approach, in two tiers: if we got genuinely close (the
        //    final call fired around 35 m, so ≤40 m means it was announced) a modest move
        //    away confirms we passed it; if we only got moderately close, demand a much
        //    bigger overshoot before concluding that, so a curving approach road can't
        //    false-trigger an early advance. Without any of this, navigation wedges on the
        //    old step forever, with the distance counting up instead of down.
        closestApproachMeters = min(closestApproachMeters, distance)
        let passedDirectly = distance <= maneuverPassedMeters
        let passedCleanly = closestApproachMeters <= 40
            && distance > closestApproachMeters + 30
        let passedWithGap = closestApproachMeters <= 80
            && distance > closestApproachMeters + 60
        if passedDirectly || passedCleanly || passedWithGap {
            advanceStep()
        }
    }

    private func advanceStep() {
        guard let route else { return }
        stepIndex += 1
        closestApproachMeters = .greatestFiniteMagnitude

        if stepIndex >= route.steps.count {
            arrived = true
            isNavigating = false
            speak("You have arrived at your destination.", priority: .critical)
        } else if route.steps[stepIndex].instructions.trimmingCharacters(in: .whitespaces).isEmpty {
            advanceStep()
        } else {
            currentInstruction = route.steps[stepIndex].instructions
        }
    }

    private func announceCurrentStep(prefix: String?, priority: SpeechPriority = .normal) {
        guard let route, stepIndex < route.steps.count else { return }
        let instruction = route.steps[stepIndex].instructions
        guard !instruction.isEmpty else { return }

        // The banner shows the original ("Bull Run Dr" reads fine and fits better on screen).
        // Only the spoken version gets abbreviations expanded, so the synthesizer says
        // "Drive" instead of spelling out "D, R".
        currentInstruction = instruction
        let spokenInstruction = SpeechText.spoken(instruction)

        if let prefix {
            speak("\(prefix) \(spokenInstruction)", priority: priority)
        } else {
            speak(spokenInstruction, priority: priority)
        }
    }

    // MARK: - Off-route detection and rerouting

    /// Measures how far the rider is from the planned route, and kicks off a recalculation
    /// once they've been clearly off it for several fixes in a row.
    private func checkOffRoute(currentLocation: CLLocation) {
        guard !routeCoordinates.isEmpty, let destination = destinationCoordinate else { return }

        // A loose fix can't tell us whether we're off route — with 60+ metres of error, a
        // rider dead-centre on the road can read as 50 m away from it. Don't count these
        // fixes either way: don't increment the off-route streak, but don't reset it either,
        // so a genuine off-route detection isn't cancelled by one mushy reading.
        guard currentLocation.horizontalAccuracy <= 30 else { return }

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
        speak("Recalculating.", priority: .critical)

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = transportType

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
            self.announceCurrentStep(prefix: nil, priority: .critical)
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
        if usesMetricUnits {
            if meters < 950 {
                // Round to the nearest 50 m — "in 347 meters" sounds robotic.
                let rounded = max((meters / 50).rounded() * 50, 50)
                return "\(Int(rounded)) meters"
            }
            return String(format: "%.1f kilometers", meters / 1000)
        }

        let feet = meters * 3.28084
        if feet < 1000 {
            // Round to the nearest 50 ft, minimum 50 so it never says "0 feet".
            let rounded = max((feet / 50).rounded() * 50, 50)
            return "\(Int(rounded)) feet"
        }
        return String(format: "%.1f miles", meters / 1609.34)
    }

    /// How urgent an announcement is. The cooldown only silences the chatty stuff — anything
    /// you'd actually be annoyed to miss ignores it.
    private enum SpeechPriority {
        /// Ordinary guidance. Suppressed if we spoke in the last few seconds.
        case normal
        /// Must be heard now — the final turn call, arrival, rerouting. Never suppressed,
        /// and cuts off anything already being said.
        case critical
    }

    /// Minimum gap between ordinary announcements, so the voice stops narrating every small
    /// thing back-to-back. Critical announcements ignore this entirely.
    private let speechCooldown: TimeInterval = 5.0

    private var lastSpokeAt: Date?

    private func speak(_ text: String, priority: SpeechPriority = .normal) {
        guard voiceEnabled, !text.isEmpty else { return }

        switch priority {
        case .critical:
            // Always speak. If something else is mid-sentence, cut it off — a stale
            // "in 500 feet" is worse than useless when the turn is happening right now.
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }

        case .normal:
            // Drop it if we've only just finished saying something, rather than queueing it
            // up — a queued direction would arrive too late to be useful anyway.
            let sinceLast = lastSpokeAt.map { Date().timeIntervalSince($0) }
                ?? .greatestFiniteMagnitude
            guard sinceLast >= speechCooldown, !synthesizer.isSpeaking else { return }
        }

        lastSpokeAt = Date()

        let alreadyActive = audioSessionActive
        activateAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = VoiceCatalog.voice(for: voiceIdentifier)
        utterance.rate = speechRate
        // If the session was just activated from cold, it needs a beat to engage the audio
        // route (especially when ducking music). Speaking instantly clips the first word.
        utterance.preUtteranceDelay = alreadyActive ? 0 : 0.25

        synthesizer.speak(utterance)
    }

    // MARK: - Audio session
    //
    // Two competing requirements:
    //   1. Music must not stay quiet the whole time (that was the original Spotify bug).
    //   2. Speech must still work with the screen off — and iOS won't let a backgrounded app
    //      activate an audio session from scratch, so tearing it down between turns meant
    //      guidance went silent as soon as the phone locked.
    //
    // The resolution is `.duckOthers` combined with `.mixWithOthers`: the session can be held
    // for the whole navigation session without permanently suppressing other audio. iOS only
    // ducks while something is actually being spoken, and restores the volume by itself in
    // between. So the session is claimed when navigation starts and released when it ends —
    // not around each individual utterance.

    private var audioSessionActive = false

    /// Claims the audio session for the duration of navigation.
    private func activateAudioSession() {
        guard !audioSessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers]
            )
            try session.setActive(true)
            audioSessionActive = true
        } catch {
            // If the session can't be claimed, directions just won't duck over music.
            // Not worth interrupting navigation over.
        }
    }

    /// Hands the audio session back. `.notifyOthersOnDeactivation` is what tells Spotify to
    /// ramp back up to full volume — without it, music can stay quiet.
    private func releaseAudioSession() {
        guard audioSessionActive else { return }
        audioSessionActive = false

        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Deliberately does NOT release the session — it's held for the whole navigation
        // session so speech survives the screen locking. Released in stopNavigation().
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Same as above.
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

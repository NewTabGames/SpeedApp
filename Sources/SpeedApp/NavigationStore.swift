import Foundation
import MapKit
import Combine
import AVFoundation

/// Handles destination search, route calculation, and spoken turn-by-turn guidance.
///
/// Note on scope: this drives guidance off Apple's MKDirections road routing and
/// announces each step as you approach it. It does not recalculate a brand new
/// route if you go off-path mid-ride (real turn-by-turn apps constantly reroute) —
/// it keeps guiding you along the original route. Good enough for "get me there
/// with voice prompts," not a full Apple Maps replacement.
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
    private var stepIndex: Int = 0

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Biases search suggestions toward wherever the rider actually is, so "gas station"
    /// or a partial street name returns nearby matches instead of generic/global ones.
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

    // MARK: - Destination selection + routing

    func selectSuggestion(_ suggestion: MKLocalSearchCompletion, currentCoordinate: CLLocationCoordinate2D?) {
        let request = MKLocalSearch.Request(completion: suggestion)
        let search = MKLocalSearch(request: request)
        isCalculatingRoute = true
        search.start { [weak self] response, error in
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

    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        isCalculatingRoute = true
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self else { return }
            self.isCalculatingRoute = false
            guard let route = response?.routes.first else { return }
            self.route = route
            self.distanceRemainingMeters = route.distance
            self.etaMinutes = route.expectedTravelTime / 60
        }
    }

    func cancelDestination() {
        route = nil
        destinationCoordinate = nil
        destinationName = ""
        isNavigating = false
        arrived = false
    }

    // MARK: - Turn-by-turn

    func startNavigation() {
        guard route != nil else { return }
        isNavigating = true
        arrived = false
        stepIndex = 0
        announceCurrentStep()
    }

    func stopNavigation() {
        isNavigating = false
        synthesizer.stopSpeaking(at: .immediate)
        cancelDestination()
    }

    /// Call on every fresh GPS fix while navigating to advance guidance.
    func updateProgress(currentLocation: CLLocation) {
        guard isNavigating, let route, stepIndex < route.steps.count else { return }
        let step = route.steps[stepIndex]

        guard step.polyline.pointCount > 0 else {
            advanceStep()
            return
        }
        let maneuverCoordinate = step.polyline.points()[0].coordinate
        let maneuverLocation = CLLocation(latitude: maneuverCoordinate.latitude, longitude: maneuverCoordinate.longitude)
        let distance = currentLocation.distance(from: maneuverLocation)
        distanceToNextManeuverMeters = distance

        // Rough remaining-distance estimate: proportion of steps completed
        let progress = Double(stepIndex) / Double(max(route.steps.count, 1))
        distanceRemainingMeters = max(route.distance * (1 - progress), 0)

        if distance < 25 {
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
        } else {
            announceCurrentStep()
        }
    }

    private func announceCurrentStep() {
        guard let route, stepIndex < route.steps.count else { return }
        let step = route.steps[stepIndex]
        let text = step.instructions.isEmpty ? "Continue straight" : step.instructions
        currentInstruction = text
        speak(text)
    }

    private func speak(_ text: String) {
        guard voiceEnabled, !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = speechRate
        synthesizer.speak(utterance)
    }
}

import Foundation
import SwiftUI
import UIKit
import MapKit
import Combine

enum SpeedUnit: String, CaseIterable, Codable, Identifiable {
    case mph = "MPH"
    case kmh = "KM/H"
    var id: String { rawValue }

    func convert(fromMph mph: Double) -> Double {
        switch self {
        case .mph: return mph
        case .kmh: return mph * 1.60934
        }
    }

    var distanceUnitLabel: String {
        switch self {
        case .mph: return "mi"
        case .kmh: return "km"
        }
    }

    func convertDistance(fromMiles miles: Double) -> Double {
        switch self {
        case .mph: return miles
        case .kmh: return miles * 1.60934
        }
    }
}

enum AccentTheme: String, CaseIterable, Codable, Identifiable {
    case orange = "Orange"
    case green = "Green"
    case blue = "Blue"
    case red = "Red"
    case purple = "Purple"
    case teal = "Teal"
    case pink = "Pink"
    case indigo = "Indigo"
    case mint = "Mint"
    case yellow = "Gold"
    case crimson = "Crimson"
    case sky = "Sky"
    var id: String { rawValue }

    /// Base RGB for each theme. Explicit values (rather than the system colors) so the
    /// light-to-dark route gradient below has a consistent hue to shade.
    private var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .orange:  return (1.00, 0.58, 0.00)
        case .green:   return (0.30, 0.85, 0.39)
        case .blue:    return (0.00, 0.48, 1.00)
        case .red:     return (1.00, 0.23, 0.19)
        case .purple:  return (0.75, 0.35, 0.95)
        case .teal:    return (0.19, 0.78, 0.78)
        case .pink:    return (1.00, 0.18, 0.55)
        case .indigo:  return (0.35, 0.34, 0.84)
        case .mint:    return (0.24, 0.87, 0.67)
        case .yellow:  return (1.00, 0.80, 0.00)
        case .crimson: return (0.86, 0.08, 0.24)
        case .sky:     return (0.35, 0.78, 0.98)
        }
    }

    var color: Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Core Graphics drawing (like the route image export) needs a UIColor.
    var uiColor: UIColor {
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    /// A shade of this accent for the speed-colored route: `t` from 0 (slowest, pale) to
    /// 1 (fastest, deep). Interpolates from a light tint of the hue toward a darkened
    /// version of it, so the whole route stays recognisably "your color" while still
    /// showing where you were fast or slow.
    /// Speed shading for the colored route, 0 (slowest, pale) to 1 (fastest, deep).
    ///
    /// Piecewise ramp through three zones so speeds are visually distinct: the slow half
    /// runs very-pale → the vivid pure accent, the fast half runs vivid → near-black.
    /// A single pale→dark lerp left the whole midrange looking like the same color.
    func speedShade(_ t: Double) -> Color {
        let (r, g, b) = shadeComponents(t)
        return Color(red: r, green: g, blue: b)
    }

    func speedShadeUIColor(_ t: Double) -> UIColor {
        let (r, g, b) = shadeComponents(t)
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Maps a normalized speed (0 = slowest, 1 = fastest) to a color.
    ///
    /// Built in HSB rather than by scaling RGB channels. The previous version pushed
    /// brightness to 1.15 and then clamped each channel to 1.0 — which meant everything above
    /// roughly 80% of the range clipped to the *same* colour. On a fast car ride, where much
    /// of the route sits in that upper band, the whole line came out one flat shade.
    ///
    /// Here saturation and brightness both ramp within legal bounds, so every point on the
    /// scale is a distinct colour: dark and grey when slow, vivid and bright when fast.
    private func shadeComponents(_ t: Double) -> (Double, Double, Double) {
        let clamped = max(0, min(1, t))
        let (h, baseSat, _) = hsb

        // Wide, non-clipping spread. Both channels move together so the difference reads
        // clearly even on satellite imagery.
        let saturation = lerp(0.10, max(baseSat, 0.85), clamped)  // grey → full colour
        let brightness = lerp(0.42, 1.00, clamped)                // dark → bright

        return hsbToRGB(h: h, s: saturation, b: brightness)
    }

    private func lerp(_ from: Double, _ to: Double, _ t: Double) -> Double {
        from + (to - from) * t
    }

    /// The accent expressed as hue/saturation/brightness.
    private var hsb: (Double, Double, Double) {
        let (r, g, b) = rgb
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var hue: Double = 0
        if delta > 0 {
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        let saturation = maxC == 0 ? 0 : delta / maxC
        return (hue, saturation, maxC)
    }

    private func hsbToRGB(h: Double, s: Double, b: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (b, b, b) }

        let sector = (h.truncatingRemainder(dividingBy: 1)) * 6
        let i = floor(sector)
        let f = sector - i

        let p = b * (1 - s)
        let q = b * (1 - s * f)
        let t = b * (1 - s * (1 - f))

        switch Int(i) % 6 {
        case 0:  return (b, t, p)
        case 1:  return (q, b, p)
        case 2:  return (p, b, t)
        case 3:  return (p, q, b)
        case 4:  return (t, p, b)
        default: return (b, p, q)
        }
    }
}

enum SmoothingLevel: String, CaseIterable, Codable, Identifiable, Equatable {
    case responsive = "Responsive"
    case balanced = "Balanced"
    case smooth = "Smooth"
    var id: String { rawValue }

    /// Higher alpha = reacts faster to new readings, lower = smoother but more lag
    var alpha: Double {
        switch self {
        case .responsive: return 0.8
        case .balanced: return 0.6
        case .smooth: return 0.35
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum MapStyleOption: String, CaseIterable, Codable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"
    var id: String { rawValue }

    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard
        case .satellite: return .imagery
        case .hybrid: return .hybrid
        }
    }

    /// MKMapSnapshotter (used for the route image export) predates MapStyle and takes MKMapType.
    var mkMapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        }
    }
}

/// How you're travelling. This is the app's central mode switch: it changes routing, GPS
/// tuning, which features appear, and which set of saved settings is active.
///
/// Each mode keeps its own independent settings (speed alert, auto-pause, GPS mode,
/// smoothing), so tuning the car doesn't disturb the scooter.
enum VehicleMode: String, CaseIterable, Codable, Identifiable, Equatable, Sendable {
    case scooter = "Scooter"
    case car = "Car"
    case motorcycle = "Motorcycle"
    case walking = "Walking"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scooter:    return "scooter"
        case .car:        return "car.fill"
        case .motorcycle: return "motorcycle"
        case .walking:    return "figure.walk"
        }
    }

    /// Only electric vehicles have a battery percentage worth logging. Cars and motorcycles
    /// already report their own fuel economy, and walking has no energy source to track.
    var usesBattery: Bool {
        self == .scooter
    }

    /// Walking gets pedestrian routes (footpaths, crossings). Everything else uses road
    /// routing — MapKit has no scooter or motorcycle profile, so they share the car's.
    var transportType: MKDirectionsTransportType {
        self == .walking ? .walking : .automobile
    }

    /// Tells CoreLocation what kind of movement to expect, which tunes its filtering.
    var activityType: CLActivityType {
        switch self {
        // Deliberately NOT .automotiveNavigation. That activity type lets iOS snap fixes to
        // the road network — great for a turn-by-turn app, but it means a ride on a sidewalk
        // or bike path gets dragged onto the parallel road before the app ever sees the
        // points. .otherNavigation gives vehicle-appropriate GPS handling without that
        // road-snapping, so the recorded track follows where you actually went.
        case .car, .motorcycle, .scooter: return .otherNavigation
        case .walking:                    return .fitness
        }
    }

    // MARK: Sensible starting points for each mode's own settings

    var defaultAlertMph: Double {
        switch self {
        case .scooter:    return 20
        case .car:        return 70
        case .motorcycle: return 70
        case .walking:    return 8
        }
    }

    /// Below this speed you count as stopped. A car idling at a light still creeps;
    /// a walker stopping is much closer to truly zero.
    var defaultAutoPauseMph: Double {
        switch self {
        case .scooter:    return 1.5
        case .car:        return 3.0
        case .motorcycle: return 3.0
        case .walking:    return 0.5
        }
    }

    var defaultAutoPauseDelay: Double {
        switch self {
        case .car, .motorcycle: return 6   // traffic lights are long
        case .scooter:          return 4
        case .walking:          return 3
        }
    }

    var defaultSmoothing: SmoothingLevel {
        switch self {
        // Cars change speed smoothly at higher velocity, so a steadier reading looks right.
        case .car, .motorcycle: return .smooth
        case .scooter:          return .balanced
        // Walking speeds are small; a laggy average would barely move.
        case .walking:          return .responsive
        }
    }
}

enum GPSAccuracyMode: String, CaseIterable, Codable, Identifiable, Equatable {
    case highAccuracy = "High Accuracy"
    case batterySaver = "Battery Saver"
    var id: String { rawValue }
}

enum ChartLineStyle: String, CaseIterable, Codable, Identifiable, Equatable {
    case smooth = "Smooth Curve"
    case straight = "Straight Lines"
    var id: String { rawValue }
}

final class SettingsStore: ObservableObject {

    // MARK: - Vehicle mode

    /// The active vehicle. Changing this swaps in that vehicle's own saved settings.
    @Published var vehicleMode: VehicleMode {
        didSet {
            guard oldValue != vehicleMode else { return }
            UserDefaults.standard.set(vehicleMode.rawValue, forKey: Keys.vehicleMode)
            loadPerModeSettings()
        }
    }

    // MARK: - Global settings (shared across every vehicle)

    @Published var unit: SpeedUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: Keys.unit) }
    }
    @Published var accent: AccentTheme {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Keys.accent) }
    }
    @Published var keepScreenAwake: Bool {
        didSet { UserDefaults.standard.set(keepScreenAwake, forKey: Keys.keepAwake) }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var mapStyle: MapStyleOption {
        didSet { UserDefaults.standard.set(mapStyle.rawValue, forKey: Keys.mapStyle) }
    }
    @Published var chartLineStyle: ChartLineStyle {
        didSet { UserDefaults.standard.set(chartLineStyle.rawValue, forKey: Keys.chartLineStyle) }
    }
    /// When true, route maps color the line by speed (muted = slow, vivid = fast) instead of
    /// drawing it in a single flat accent color.
    @Published var colorRouteBySpeed: Bool {
        didSet { UserDefaults.standard.set(colorRouteBySpeed, forKey: Keys.colorRoute) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    @Published var confirmBeforeClearing: Bool {
        didSet { UserDefaults.standard.set(confirmBeforeClearing, forKey: Keys.confirmClear) }
    }
    /// 0.3 (slow/clear) to 0.6 (fast/natural). AVSpeechUtterance default is ~0.5.
    @Published var voiceSpeechRate: Double {
        didSet { UserDefaults.standard.set(voiceSpeechRate, forKey: Keys.voiceRate) }
    }
    /// Chosen navigation voice, stored as an AVSpeechSynthesisVoice identifier.
    @Published var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: Keys.voiceIdentifier) }
    }

    // MARK: - Per-vehicle settings
    //
    // These are saved under a key namespaced by vehicle, so each mode keeps its own copy.
    // Setting the car's speed alert to 70 doesn't touch the scooter's 20.

    @Published var smoothing: SmoothingLevel {
        didSet { setPerMode(smoothing.rawValue, Keys.smoothing) }
    }
    @Published var gpsAccuracy: GPSAccuracyMode {
        didSet { setPerMode(gpsAccuracy.rawValue, Keys.gpsAccuracy) }
    }
    @Published var maxSpeedAlertEnabled: Bool {
        didSet { setPerMode(maxSpeedAlertEnabled, Keys.alertEnabled) }
    }
    @Published var maxSpeedAlertMph: Double {
        didSet { setPerMode(maxSpeedAlertMph, Keys.alertValue) }
    }
    @Published var autoPauseEnabled: Bool {
        didSet { setPerMode(autoPauseEnabled, Keys.autoPause) }
    }
    /// Speed below which you're considered stopped, in mph.
    @Published var autoPauseSpeedMph: Double {
        didSet { setPerMode(autoPauseSpeedMph, Keys.autoPauseSpeed) }
    }
    /// How many seconds below that speed before the recording pauses itself.
    @Published var autoPauseDelaySeconds: Double {
        didSet { setPerMode(autoPauseDelaySeconds, Keys.autoPauseDelay) }
    }
    /// Only meaningful for electric vehicles; hidden entirely for the others.
    @Published var batteryTrackingEnabled: Bool {
        didSet { setPerMode(batteryTrackingEnabled, Keys.batteryTracking) }
    }

    // MARK: - Keys

    private enum Keys {
        // Global
        static let vehicleMode = "settings.vehicleMode"
        static let unit = "settings.unit"
        static let accent = "settings.accent"
        static let keepAwake = "settings.keepAwake"
        static let appearance = "settings.appearance"
        static let mapStyle = "settings.mapStyle"
        static let chartLineStyle = "settings.chartLineStyle"
        static let colorRoute = "settings.colorRoute"
        static let haptics = "settings.haptics"
        static let confirmClear = "settings.confirmClear"
        static let voiceRate = "settings.voiceRate"
        static let voiceIdentifier = "settings.voiceIdentifier"

        // Per-vehicle (these get prefixed with the mode — see perModeKey)
        static let smoothing = "smoothing"
        static let gpsAccuracy = "gpsAccuracy"
        static let alertEnabled = "alertEnabled"
        static let alertValue = "alertValue"
        static let autoPause = "autoPause"
        static let autoPauseSpeed = "autoPauseSpeed"
        static let autoPauseDelay = "autoPauseDelay"
        static let batteryTracking = "batteryTracking"
    }

    /// e.g. "settings.Car.alertValue" — one slot per vehicle per setting.
    private func perModeKey(_ base: String, mode: VehicleMode? = nil) -> String {
        "settings.\((mode ?? vehicleMode).rawValue).\(base)"
    }

    private func setPerMode(_ value: Any, _ base: String) {
        // Skipped while loading, otherwise reloading a mode would immediately write the
        // values straight back — harmless, but noisy and easy to get wrong later.
        guard !isLoadingMode else { return }
        UserDefaults.standard.set(value, forKey: perModeKey(base))
    }

    private var isLoadingMode = false

    // MARK: - Init

    init() {
        let d = UserDefaults.standard

        let mode = VehicleMode(rawValue: d.string(forKey: Keys.vehicleMode) ?? "") ?? .scooter
        vehicleMode = mode

        // Global
        unit = SpeedUnit(rawValue: d.string(forKey: Keys.unit) ?? "") ?? .mph
        accent = AccentTheme(rawValue: d.string(forKey: Keys.accent) ?? "") ?? .orange
        keepScreenAwake = d.object(forKey: Keys.keepAwake) as? Bool ?? true
        appearance = AppearanceMode(rawValue: d.string(forKey: Keys.appearance) ?? "") ?? .dark
        mapStyle = MapStyleOption(rawValue: d.string(forKey: Keys.mapStyle) ?? "") ?? .standard
        chartLineStyle = ChartLineStyle(rawValue: d.string(forKey: Keys.chartLineStyle) ?? "") ?? .smooth
        colorRouteBySpeed = d.object(forKey: Keys.colorRoute) as? Bool ?? true
        hapticsEnabled = d.object(forKey: Keys.haptics) as? Bool ?? true
        confirmBeforeClearing = d.object(forKey: Keys.confirmClear) as? Bool ?? true
        voiceSpeechRate = d.object(forKey: Keys.voiceRate) as? Double ?? 0.5
        voiceIdentifier = d.string(forKey: Keys.voiceIdentifier) ?? VoiceCatalog.systemDefaultID

        // Per-vehicle — read this mode's slot, falling back to the mode's sensible default.
        // Property initialisers can't call instance methods, so the key is built inline here.
        func key(_ base: String) -> String { "settings.\(mode.rawValue).\(base)" }

        smoothing = SmoothingLevel(rawValue: d.string(forKey: key(Keys.smoothing)) ?? "")
            ?? mode.defaultSmoothing
        gpsAccuracy = GPSAccuracyMode(rawValue: d.string(forKey: key(Keys.gpsAccuracy)) ?? "")
            ?? .highAccuracy
        maxSpeedAlertEnabled = d.object(forKey: key(Keys.alertEnabled)) as? Bool ?? false
        maxSpeedAlertMph = d.object(forKey: key(Keys.alertValue)) as? Double ?? mode.defaultAlertMph
        autoPauseEnabled = d.object(forKey: key(Keys.autoPause)) as? Bool ?? false
        autoPauseSpeedMph = d.object(forKey: key(Keys.autoPauseSpeed)) as? Double
            ?? mode.defaultAutoPauseMph
        autoPauseDelaySeconds = d.object(forKey: key(Keys.autoPauseDelay)) as? Double
            ?? mode.defaultAutoPauseDelay
        batteryTrackingEnabled = d.object(forKey: key(Keys.batteryTracking)) as? Bool ?? false
    }

    // MARK: - Mode switching

    /// Swaps in the newly-selected vehicle's saved settings. Anything it hasn't been
    /// configured with yet falls back to a default that suits that vehicle.
    private func loadPerModeSettings() {
        let d = UserDefaults.standard
        isLoadingMode = true
        defer { isLoadingMode = false }

        smoothing = SmoothingLevel(rawValue: d.string(forKey: perModeKey(Keys.smoothing)) ?? "")
            ?? vehicleMode.defaultSmoothing
        gpsAccuracy = GPSAccuracyMode(rawValue: d.string(forKey: perModeKey(Keys.gpsAccuracy)) ?? "")
            ?? .highAccuracy
        maxSpeedAlertEnabled = d.object(forKey: perModeKey(Keys.alertEnabled)) as? Bool ?? false
        maxSpeedAlertMph = d.object(forKey: perModeKey(Keys.alertValue)) as? Double
            ?? vehicleMode.defaultAlertMph
        autoPauseEnabled = d.object(forKey: perModeKey(Keys.autoPause)) as? Bool ?? false
        autoPauseSpeedMph = d.object(forKey: perModeKey(Keys.autoPauseSpeed)) as? Double
            ?? vehicleMode.defaultAutoPauseMph
        autoPauseDelaySeconds = d.object(forKey: perModeKey(Keys.autoPauseDelay)) as? Double
            ?? vehicleMode.defaultAutoPauseDelay
        batteryTrackingEnabled = d.object(forKey: perModeKey(Keys.batteryTracking)) as? Bool ?? false
    }

    /// Resets the current vehicle's settings back to that vehicle's defaults.
    func resetCurrentModeSettings() {
        let d = UserDefaults.standard
        for base in [Keys.smoothing, Keys.gpsAccuracy, Keys.alertEnabled, Keys.alertValue,
                     Keys.autoPause, Keys.autoPauseSpeed, Keys.autoPauseDelay, Keys.batteryTracking] {
            d.removeObject(forKey: perModeKey(base))
        }
        loadPerModeSettings()
    }
}

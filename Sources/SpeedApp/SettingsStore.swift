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
    func speedShade(_ t: Double) -> Color {
        let clamped = max(0, min(1, t))
        let (r, g, b) = rgb

        // Pale end: mix heavily toward white. Deep end: scale the hue darker.
        let lightMix = 0.75   // how white the slow end is
        let darkScale = 0.55  // how dark the fast end is

        let startR = r + (1 - r) * lightMix
        let startG = g + (1 - g) * lightMix
        let startB = b + (1 - b) * lightMix

        let endR = r * darkScale
        let endG = g * darkScale
        let endB = b * darkScale

        return Color(
            red: startR + (endR - startR) * clamped,
            green: startG + (endG - startG) * clamped,
            blue: startB + (endB - startB) * clamped
        )
    }

    func speedShadeUIColor(_ t: Double) -> UIColor {
        let clamped = max(0, min(1, t))
        let (r, g, b) = rgb
        let lightMix = 0.75
        let darkScale = 0.55
        let startR = r + (1 - r) * lightMix
        let startG = g + (1 - g) * lightMix
        let startB = b + (1 - b) * lightMix
        let endR = r * darkScale
        let endG = g * darkScale
        let endB = b * darkScale
        return UIColor(
            red: startR + (endR - startR) * clamped,
            green: startG + (endG - startG) * clamped,
            blue: startB + (endB - startB) * clamped,
            alpha: 1
        )
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
    @Published var unit: SpeedUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: Keys.unit) }
    }
    @Published var accent: AccentTheme {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Keys.accent) }
    }
    @Published var smoothing: SmoothingLevel {
        didSet { UserDefaults.standard.set(smoothing.rawValue, forKey: Keys.smoothing) }
    }
    @Published var keepScreenAwake: Bool {
        didSet { UserDefaults.standard.set(keepScreenAwake, forKey: Keys.keepAwake) }
    }
    @Published var maxSpeedAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(maxSpeedAlertEnabled, forKey: Keys.alertEnabled) }
    }
    @Published var maxSpeedAlertMph: Double {
        didSet { UserDefaults.standard.set(maxSpeedAlertMph, forKey: Keys.alertValue) }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var mapStyle: MapStyleOption {
        didSet { UserDefaults.standard.set(mapStyle.rawValue, forKey: Keys.mapStyle) }
    }
    @Published var gpsAccuracy: GPSAccuracyMode {
        didSet { UserDefaults.standard.set(gpsAccuracy.rawValue, forKey: Keys.gpsAccuracy) }
    }
    @Published var chartLineStyle: ChartLineStyle {
        didSet { UserDefaults.standard.set(chartLineStyle.rawValue, forKey: Keys.chartLineStyle) }
    }
    /// When true, route maps color the line by speed (pale = slow, deep = fast) instead of
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
    @Published var autoPauseEnabled: Bool {
        didSet { UserDefaults.standard.set(autoPauseEnabled, forKey: Keys.autoPause) }
    }
    /// Speed below which you're considered stopped, in mph.
    @Published var autoPauseSpeedMph: Double {
        didSet { UserDefaults.standard.set(autoPauseSpeedMph, forKey: Keys.autoPauseSpeed) }
    }
    /// How many seconds below that speed before the recording pauses itself.
    @Published var autoPauseDelaySeconds: Double {
        didSet { UserDefaults.standard.set(autoPauseDelaySeconds, forKey: Keys.autoPauseDelay) }
    }
    @Published var batteryTrackingEnabled: Bool {
        didSet { UserDefaults.standard.set(batteryTrackingEnabled, forKey: Keys.batteryTracking) }
    }
    /// 0.3 (slow/clear) to 0.6 (fast/natural). AVSpeechUtterance default is ~0.5.
    @Published var voiceSpeechRate: Double {
        didSet { UserDefaults.standard.set(voiceSpeechRate, forKey: Keys.voiceRate) }
    }
    /// Chosen navigation voice, stored as an AVSpeechSynthesisVoice identifier.
    /// Defaults to VoiceCatalog.systemDefaultID (let iOS pick for the language).
    @Published var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: Keys.voiceIdentifier) }
    }

    private enum Keys {
        static let unit = "settings.unit"
        static let accent = "settings.accent"
        static let smoothing = "settings.smoothing"
        static let keepAwake = "settings.keepAwake"
        static let alertEnabled = "settings.alertEnabled"
        static let alertValue = "settings.alertValue"
        static let appearance = "settings.appearance"
        static let mapStyle = "settings.mapStyle"
        static let gpsAccuracy = "settings.gpsAccuracy"
        static let chartLineStyle = "settings.chartLineStyle"
        static let colorRoute = "settings.colorRoute"
        static let haptics = "settings.haptics"
        static let confirmClear = "settings.confirmClear"
        static let autoPause = "settings.autoPause"
        static let autoPauseSpeed = "settings.autoPauseSpeed"
        static let autoPauseDelay = "settings.autoPauseDelay"
        static let batteryTracking = "settings.batteryTracking"
        static let voiceRate = "settings.voiceRate"
        static let voiceIdentifier = "settings.voiceIdentifier"
    }

    init() {
        let d = UserDefaults.standard
        unit = SpeedUnit(rawValue: d.string(forKey: Keys.unit) ?? "") ?? .mph
        accent = AccentTheme(rawValue: d.string(forKey: Keys.accent) ?? "") ?? .orange
        smoothing = SmoothingLevel(rawValue: d.string(forKey: Keys.smoothing) ?? "") ?? .balanced
        keepScreenAwake = d.object(forKey: Keys.keepAwake) as? Bool ?? true
        maxSpeedAlertEnabled = d.object(forKey: Keys.alertEnabled) as? Bool ?? false
        maxSpeedAlertMph = d.object(forKey: Keys.alertValue) as? Double ?? 20
        appearance = AppearanceMode(rawValue: d.string(forKey: Keys.appearance) ?? "") ?? .dark
        mapStyle = MapStyleOption(rawValue: d.string(forKey: Keys.mapStyle) ?? "") ?? .standard
        gpsAccuracy = GPSAccuracyMode(rawValue: d.string(forKey: Keys.gpsAccuracy) ?? "") ?? .highAccuracy
        chartLineStyle = ChartLineStyle(rawValue: d.string(forKey: Keys.chartLineStyle) ?? "") ?? .smooth
        colorRouteBySpeed = d.object(forKey: Keys.colorRoute) as? Bool ?? true
        hapticsEnabled = d.object(forKey: Keys.haptics) as? Bool ?? true
        confirmBeforeClearing = d.object(forKey: Keys.confirmClear) as? Bool ?? true
        autoPauseEnabled = d.object(forKey: Keys.autoPause) as? Bool ?? false
        autoPauseSpeedMph = d.object(forKey: Keys.autoPauseSpeed) as? Double ?? 1.5
        autoPauseDelaySeconds = d.object(forKey: Keys.autoPauseDelay) as? Double ?? 4
        batteryTrackingEnabled = d.object(forKey: Keys.batteryTracking) as? Bool ?? false
        voiceSpeechRate = d.object(forKey: Keys.voiceRate) as? Double ?? 0.5
        voiceIdentifier = d.string(forKey: Keys.voiceIdentifier) ?? VoiceCatalog.systemDefaultID
    }
}

import Foundation
import SwiftUI
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
}

enum AccentTheme: String, CaseIterable, Codable, Identifiable {
    case orange = "Orange"
    case green = "Green"
    case blue = "Blue"
    case red = "Red"
    case purple = "Purple"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: return .orange
        case .green: return .green
        case .blue: return .blue
        case .red: return .red
        case .purple: return .purple
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

    private enum Keys {
        static let unit = "settings.unit"
        static let accent = "settings.accent"
        static let smoothing = "settings.smoothing"
        static let keepAwake = "settings.keepAwake"
        static let alertEnabled = "settings.alertEnabled"
        static let alertValue = "settings.alertValue"
    }

    init() {
        let d = UserDefaults.standard
        unit = SpeedUnit(rawValue: d.string(forKey: Keys.unit) ?? "") ?? .mph
        accent = AccentTheme(rawValue: d.string(forKey: Keys.accent) ?? "") ?? .orange
        smoothing = SmoothingLevel(rawValue: d.string(forKey: Keys.smoothing) ?? "") ?? .balanced
        keepScreenAwake = d.object(forKey: Keys.keepAwake) as? Bool ?? true
        maxSpeedAlertEnabled = d.object(forKey: Keys.alertEnabled) as? Bool ?? false
        maxSpeedAlertMph = d.object(forKey: Keys.alertValue) as? Double ?? 20
    }
}

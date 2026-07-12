import Foundation
import AVFoundation

/// Wraps the navigation voice options actually available on this device.
///
/// iOS voices aren't a fixed list — they depend on what the user has installed. Default
/// voices are always present; higher-quality "Enhanced" and "Premium" voices only show up
/// if the user has downloaded them (Settings › Accessibility › Spoken Content › Voices).
/// So this reads the live list at runtime rather than hardcoding anything.
enum VoiceCatalog {

    struct Voice: Identifiable, Hashable {
        let id: String          // AVSpeechSynthesisVoice.identifier
        let name: String        // e.g. "Samantha"
        let quality: String     // "Default" / "Enhanced" / "Premium"

        var label: String {
            quality == "Default" ? name : "\(name) (\(quality))"
        }
    }

    /// Identifier used to mean "let iOS pick the default for the current language."
    static let systemDefaultID = "system.default"

    /// English voices installed on this device, best quality first, then alphabetical.
    /// Filtered to English since the spoken directions are generated in English.
    static func availableVoices() -> [Voice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { voice in
                Voice(
                    id: voice.identifier,
                    name: voice.name,
                    quality: qualityLabel(voice.quality)
                )
            }

        let deduped = Dictionary(grouping: voices, by: \.name)
            .compactMapValues { group in
                // Prefer the highest-quality variant when a voice exists at several tiers.
                group.max { qualityRank($0.quality) < qualityRank($1.quality) }
            }
            .values
            .sorted { a, b in
                if qualityRank(a.quality) != qualityRank(b.quality) {
                    return qualityRank(a.quality) > qualityRank(b.quality)
                }
                return a.name < b.name
            }

        return Array(deduped)
    }

    /// Resolves a stored identifier to an actual voice. Falls back to the language default
    /// if the saved voice was uninstalled since it was chosen.
    static func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        if identifier == systemDefaultID {
            return AVSpeechSynthesisVoice(language: "en-US")
        }
        return AVSpeechSynthesisVoice(identifier: identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium:  return "Premium"
        case .enhanced: return "Enhanced"
        default:        return "Default"
        }
    }

    private static func qualityRank(_ label: String) -> Int {
        switch label {
        case "Premium":  return 2
        case "Enhanced": return 1
        default:         return 0
        }
    }
}

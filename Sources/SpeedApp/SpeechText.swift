import Foundation

/// Rewrites navigation instructions so the speech synthesizer says them properly.
///
/// MapKit returns street names with abbreviations ("Bull Run Dr", "N Main St"). The
/// synthesizer doesn't recognise these as words and spells them out letter by letter —
/// "Turn left onto Bull Run D, R". This expands them before speaking.
///
/// Only the *spoken* text is rewritten. The on-screen banner keeps the original, where
/// the abbreviations look correct and fit better.
enum SpeechText {

    /// Suffixes and directionals, longest first so multi-word forms match before short ones.
    private static let replacements: [(pattern: String, spoken: String)] = [
        // Street types
        ("Dr", "Drive"),
        ("St", "Street"),
        ("Ave", "Avenue"),
        ("Av", "Avenue"),
        ("Blvd", "Boulevard"),
        ("Rd", "Road"),
        ("Ln", "Lane"),
        ("Ct", "Court"),
        ("Cir", "Circle"),
        ("Pl", "Place"),
        ("Pkwy", "Parkway"),
        ("Pky", "Parkway"),
        ("Hwy", "Highway"),
        ("Trl", "Trail"),
        ("Ter", "Terrace"),
        ("Tpke", "Turnpike"),
        ("Sq", "Square"),
        ("Xing", "Crossing"),
        ("Expy", "Expressway"),
        ("Fwy", "Freeway"),
        ("Rte", "Route"),
        ("Ext", "Extension"),
        ("Byp", "Bypass"),
        ("Aly", "Alley"),
        ("Mt", "Mount"),
        ("Ft", "Fort"),

        // Directionals
        ("NE", "Northeast"),
        ("NW", "Northwest"),
        ("SE", "Southeast"),
        ("SW", "Southwest"),
        ("N", "North"),
        ("S", "South"),
        ("E", "East"),
        ("W", "West"),

        ("Jct", "Junction")
    ]

    /// Expands abbreviations in an instruction so it reads naturally aloud.
    static func spoken(_ instruction: String) -> String {
        var result = instruction

        // Interstates first, since a bare "I" replacement would wreck any other use of the
        // letter. Only "I-65" / "I 65" style — a letter followed by a number — is an interstate.
        result = result.replacingOccurrences(
            of: "\\bI[- ](\\d+)",
            with: "Interstate $1",
            options: [.regularExpression]
        )
        result = result.replacingOccurrences(
            of: "\\bUS[- ](\\d+)",
            with: "Highway $1",
            options: [.regularExpression]
        )

        for (pattern, spoken) in replacements {
            // \b...\b matches only whole words, so "Dr" in "Bull Run Dr" is replaced but the
            // "st" inside "Chestnut" is left alone. Case-sensitive, since street abbreviations
            // are capitalised and lowercase matches would mangle ordinary words.
            let regex = "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b\\.?"
            result = result.replacingOccurrences(
                of: regex,
                with: spoken,
                options: [.regularExpression],
                range: nil
            )
        }

        return result
    }
}

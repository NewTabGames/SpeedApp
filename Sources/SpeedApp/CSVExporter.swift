import Foundation

/// Writes ride data out as CSV files for opening in Excel, Numbers, or Google Sheets.
///
/// Two shapes, for two different jobs:
/// - `ridesSummary` — one row per ride. A spreadsheet of your riding history, good for
///   spotting trends over weeks or months.
/// - `rideSamples` — one row per GPS reading for a single ride. Raw data, for doing your
///   own analysis or charting outside the app.
enum CSVExporter {

    enum ExportError: Error {
        case noRides
        case noSamples
    }

    // MARK: - Summary of every ride

    static func ridesSummary(recordings: [SpeedRecording], unit: SpeedUnit) throws -> URL {
        guard !recordings.isEmpty else { throw ExportError.noRides }

        let speedUnit = unit.rawValue.lowercased()          // mph / km/h
        let distUnit = unit.distanceUnitLabel               // mi / km

        var rows: [String] = [
            [
                "date",
                "name",
                "duration_seconds",
                "distance_\(distUnit)",
                "max_speed_\(speedUnit)",
                "avg_speed_\(speedUnit)",
                "elevation_gain_ft",
                "elevation_loss_ft",
                "battery_start_percent",
                "battery_end_percent",
                "battery_used_percent",
                "gps_samples"
            ].joined(separator: ",")
        ]

        // Oldest first reads more naturally in a spreadsheet.
        for rec in recordings.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                isoDate(rec.date),
                escape(rec.name),
                fmt(rec.duration, places: 0),
                fmt(unit.convertDistance(fromMiles: rec.distanceMiles), places: 3),
                fmt(unit.convert(fromMph: rec.maxMph), places: 1),
                fmt(unit.convert(fromMph: rec.avgMph), places: 1),
                fmt(rec.elevationGainFt, places: 0),
                fmt(rec.elevationLossFt, places: 0),
                optional(rec.batteryStartPercent, places: 0),
                optional(rec.batteryEndPercent, places: 0),
                optional(rec.batteryUsedPercent, places: 0),
                String(rec.samples.count)
            ]
            rows.append(fields.joined(separator: ","))
        }

        return try write(rows.joined(separator: "\n"), filename: "rides-summary.csv")
    }

    // MARK: - Every GPS sample from one ride

    static func rideSamples(recording: SpeedRecording, unit: SpeedUnit) throws -> URL {
        guard !recording.samples.isEmpty else { throw ExportError.noSamples }

        let speedUnit = unit.rawValue.lowercased()

        var rows: [String] = [
            [
                "elapsed_seconds",
                "timestamp",
                "speed_\(speedUnit)",
                "latitude",
                "longitude",
                "altitude_m"
            ].joined(separator: ",")
        ]

        for sample in recording.samples {
            let timestamp = recording.date.addingTimeInterval(sample.offsetSeconds)
            let fields: [String] = [
                fmt(sample.offsetSeconds, places: 1),
                isoDate(timestamp),
                fmt(unit.convert(fromMph: sample.mph), places: 2),
                fmt(sample.latitude, places: 6),
                fmt(sample.longitude, places: 6),
                fmt(sample.altitudeMeters, places: 1)
            ]
            rows.append(fields.joined(separator: ","))
        }

        let slug = recording.displayName
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let name = slug.isEmpty ? "ride" : slug

        return try write(rows.joined(separator: "\n"), filename: "\(name)-data.csv")
    }

    // MARK: - Helpers

    private static func write(_ contents: String, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func fmt(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    private static func optional(_ value: Double?, places: Int) -> String {
        guard let value else { return "" }
        return fmt(value, places: places)
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Ride names are free text and can contain commas or quotes, which would otherwise
    /// break the column layout. RFC 4180 says wrap in quotes and double any inner quotes.
    private static func escape(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else {
            return text
        }
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

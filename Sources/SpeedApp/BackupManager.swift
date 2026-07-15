import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Export and restore your rides as a single backup file.
///
/// Why this exists: sideloaded apps have no iCloud sync (CloudKit needs a paid Apple
/// Developer account), and a free-signed app's data only survives if you install the new
/// build *over* the old one. Delete the app, change signing certificate, or wipe the phone,
/// and every ride is gone permanently. This is the safety net.
///
/// The backup is plain JSON — the same format the app stores internally — so it's readable,
/// portable, and future-proof.
enum BackupManager {

    /// Bumped if the ride format ever changes in a way that needs migrating on import.
    static let currentVersion = 1

    struct Backup: Codable {
        var version: Int
        var exportedAt: Date
        var recordings: [SpeedRecording]
    }

    enum BackupError: LocalizedError {
        case nothingToExport
        case unreadableFile
        case wrongFormat

        var errorDescription: String? {
            switch self {
            case .nothingToExport: return "There are no rides to back up yet."
            case .unreadableFile:  return "Couldn't read that file."
            case .wrongFormat:     return "That doesn't look like a rides backup file."
            }
        }
    }

    // MARK: - Export

    /// Writes every ride to a timestamped backup file and returns its URL for sharing.
    static func exportBackup(recordings: [SpeedRecording]) throws -> URL {
        guard !recordings.isEmpty else { throw BackupError.nothingToExport }

        let backup = Backup(
            version: currentVersion,
            exportedAt: Date(),
            recordings: recordings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "rides-backup-\(formatter.string(from: Date())).json"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    /// Reads a backup file. Doesn't apply it — the caller decides whether to merge or replace.
    static func readBackup(from url: URL) throws -> Backup {
        // Files picked from iCloud Drive / Files are security-scoped and must be unlocked
        // before reading, then released.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw BackupError.unreadableFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let backup = try? decoder.decode(Backup.self, from: data) else {
            throw BackupError.wrongFormat
        }
        return backup
    }
}

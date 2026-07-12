import Foundation
import Combine

struct SpeedRecording: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var duration: Double
    var maxMph: Double
    var avgMph: Double
    var distanceMiles: Double
    var samples: [SpeedSample]

    static func == (lhs: SpeedRecording, rhs: SpeedRecording) -> Bool {
        lhs.id == rhs.id
    }
}

final class RunStore: ObservableObject {
    @Published private(set) var recordings: [SpeedRecording] = []

    /// Recordings are stored as a JSON file rather than in UserDefaults.
    /// UserDefaults is for small preferences and is loaded into memory at launch —
    /// a handful of hour-long rides is megabytes of sample data, which does not belong there.
    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("recordings.json")
    }()

    private let legacyKey = "speedapp.recordings.v1"

    init() {
        load()
    }

    func addRecording(samples: [SpeedSample], maxMph: Double, avgMph: Double, duration: Double, distanceMiles: Double) {
        guard duration > 2 else { return } // skip accidental taps
        let recording = SpeedRecording(
            date: Date(),
            duration: duration,
            maxMph: maxMph,
            avgMph: avgMph,
            distanceMiles: distanceMiles,
            samples: samples
        )
        recordings.insert(recording, at: 0)
        save()
    }

    func deleteRecording(at offsets: IndexSet) {
        recordings.remove(atOffsets: offsets)
        save()
    }

    func clearAllRecordings() {
        recordings.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        let snapshot = recordings
        // Writing can be slow with lots of samples, so keep it off the main thread.
        DispatchQueue.global(qos: .utility).async { [fileURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SpeedRecording].self, from: data) {
            recordings = decoded
            return
        }

        // One-time migration: pull anything saved by the old UserDefaults-based version,
        // write it to the new file, then clear the old key.
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey),
           let decoded = try? JSONDecoder().decode([SpeedRecording].self, from: legacyData) {
            recordings = decoded
            save()
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }
}

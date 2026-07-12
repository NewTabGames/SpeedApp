import Foundation
import Combine

struct SpeedRecording: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var duration: Double
    var maxMph: Double
    var avgMph: Double
    var samples: [SpeedSample]

    static func == (lhs: SpeedRecording, rhs: SpeedRecording) -> Bool {
        lhs.id == rhs.id
    }
}

final class RunStore: ObservableObject {
    @Published private(set) var recordings: [SpeedRecording] = []

    private let recordingsKey = "speedapp.recordings.v1"

    init() {
        load()
    }

    func addRecording(samples: [SpeedSample], maxMph: Double, avgMph: Double, duration: Double) {
        guard duration > 2 else { return } // skip accidental taps
        let recording = SpeedRecording(date: Date(), duration: duration, maxMph: maxMph, avgMph: avgMph, samples: samples)
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

    private func save() {
        if let data = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(data, forKey: recordingsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: recordingsKey),
              let decoded = try? JSONDecoder().decode([SpeedRecording].self, from: data) else { return }
        recordings = decoded
    }
}

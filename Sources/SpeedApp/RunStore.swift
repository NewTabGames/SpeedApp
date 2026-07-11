import Foundation
import Combine

struct RunRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var zeroToSixty: Double?
    var zeroToHundred: Double?
    var topSpeedMph: Double
}

final class RunStore: ObservableObject {
    @Published private(set) var runs: [RunRecord] = []

    private let storageKey = "speedapp.runs.v1"

    init() {
        load()
    }

    func addRun(zeroToSixty: Double?, zeroToHundred: Double?, topSpeedMph: Double) {
        // Skip saving empty/noise runs
        guard zeroToSixty != nil || zeroToHundred != nil else { return }
        let record = RunRecord(date: Date(), zeroToSixty: zeroToSixty, zeroToHundred: zeroToHundred, topSpeedMph: topSpeedMph)
        runs.insert(record, at: 0)
        save()
    }

    func deleteRun(at offsets: IndexSet) {
        runs.remove(atOffsets: offsets)
        save()
    }

    func clearAll() {
        runs.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(runs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RunRecord].self, from: data) else { return }
        runs = decoded
    }
}

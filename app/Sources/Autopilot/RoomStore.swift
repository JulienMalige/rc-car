import Foundation
import RoomPlan

/// The last room scanned with the LiDAR (Apple's RoomPlan), kept as JSON in the app's documents: the autopilot's map
/// (v2, step 1, Julien 2026-10-31: "maybe I want to try the lidar first").
final class RoomStore: ObservableObject {
    static let shared = RoomStore()

    @Published private(set) var room: CapturedRoom?
    @Published private(set) var scannedAt: Date?
    @Published private(set) var problem: String?

    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("room.json")
    }

    private init() {
        load()
    }

    func save(_ room: CapturedRoom) {
        self.room = room
        scannedAt = Date()
        do {
            try JSONEncoder().encode(room).write(to: url, options: .atomic)
            problem = nil
        } catch {
            problem = "The room could not be saved: \(error.localizedDescription)"
        }
    }

    func forget() {
        room = nil
        scannedAt = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            room = try JSONDecoder().decode(CapturedRoom.self, from: data)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            scannedAt = attributes?[.modificationDate] as? Date
        } catch {
            problem = "The saved room could not be read: \(error.localizedDescription)"
        }
    }
}

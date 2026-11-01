import ARKit
import Foundation
import RoomPlan

/// The last room scanned with the LiDAR (Apple's RoomPlan), kept as JSON in the app's documents: the autopilot's map
/// (v2, step 1, Julien 2026-10-31: "maybe I want to try the lidar first"). With it, what the camera saw during the scan
/// (ARKit's world map): the autopilot finds the phone's place in the room from it, so the plan and the live camera share
/// their coordinates (step 2).
final class RoomStore: ObservableObject {
    static let shared = RoomStore()

    @Published private(set) var room: CapturedRoom?
    @Published private(set) var scannedAt: Date?
    @Published private(set) var problem: String?
    @Published private(set) var hasWorldMap = false

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var url: URL { documents.appendingPathComponent("room.json") }
    private var mapURL: URL { documents.appendingPathComponent("room.worldmap") }

    private init() {
        load()
    }

    func save(_ room: CapturedRoom, worldMap: ARWorldMap?) {
        self.room = room
        scannedAt = Date()
        do {
            try JSONEncoder().encode(room).write(to: url, options: .atomic)
            problem = nil
        } catch {
            problem = "The room could not be saved: \(error.localizedDescription)"
        }
        hasWorldMap = false
        try? FileManager.default.removeItem(at: mapURL)
        guard let worldMap else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
            try data.write(to: mapURL, options: .atomic)
            hasWorldMap = true
        } catch {
            problem = "What the camera saw could not be saved: \(error.localizedDescription)"
        }
    }

    /// Read when the autopilot starts (a few megabytes).
    func loadWorldMap() -> ARWorldMap? {
        guard let data = try? Data(contentsOf: mapURL) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }

    func forget() {
        room = nil
        scannedAt = nil
        hasWorldMap = false
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: mapURL)
    }

    private func load() {
        hasWorldMap = FileManager.default.fileExists(atPath: mapURL.path)
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

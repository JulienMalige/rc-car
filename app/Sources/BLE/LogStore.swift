import Foundation

/// Everything the app did on Bluetooth, newest last: connections, the services found, every frame that changed, every
/// notification. The debug screen shows it and shares it as text.
final class LogStore: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case info, tx, rx, error
        var id: String { rawValue }
        var title: String {
            switch self {
            case .info: return "Events"
            case .tx: return "Sent"
            case .rx: return "Received"
            case .error: return "Errors"
            }
        }
    }

    struct Entry: Identifiable {
        let id: Int
        let time: Date
        let kind: Kind
        let text: String
    }

    @Published private(set) var entries: [Entry] = []
    private var counter = 0
    private let limit = 4000

    func add(_ kind: Kind, _ text: String) {
        counter += 1
        entries.append(Entry(id: counter, time: Date(), kind: kind, text: text))
        if entries.count > limit { entries.removeFirst(entries.count - limit + 500) }
    }

    func clear() {
        entries.removeAll()
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func line(_ e: Entry) -> String {
        let mark: String
        switch e.kind {
        case .info: mark = " "
        case .tx: mark = ">"
        case .rx: mark = "<"
        case .error: mark = "!"
        }
        return "\(clock.string(from: e.time)) \(mark) \(e.text)"
    }

    func export() -> String {
        ([AppInfo.summary] + entries.map(LogStore.line)).joined(separator: "\n")
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var summary: String {
        "RC Car \(version), \(ISO8601DateFormatter().string(from: Date()))"
    }
}

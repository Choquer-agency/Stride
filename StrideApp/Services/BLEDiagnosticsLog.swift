import Foundation

/// Persistent, timestamped log of every BLE lifecycle event so a failed
/// treadmill run can be diagnosed AFTER the fact, without Xcode attached.
/// Survives app relaunches; keeps the most recent ~600 lines.
final class BLEDiagnosticsLog: ObservableObject {
    static let shared = BLEDiagnosticsLog()

    @Published private(set) var lines: [String] = []

    private let maxLines = 600
    private let queue = DispatchQueue(label: "com.stride.ble-log")
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("ble_diagnostics.log")
    }()

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            lines = text.split(separator: "\n").suffix(maxLines).map(String.init)
        }
    }

    func log(_ message: String) {
        let line = "\(timeFormatter.string(from: Date()))  \(message)"
        print("🔵 BLE: \(message)")
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
            let snapshot = self.lines.joined(separator: "\n")
            self.queue.async {
                try? snapshot.write(to: self.fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.lines = []
            self.queue.async { try? FileManager.default.removeItem(at: self.fileURL) }
        }
    }

    var fullText: String { lines.joined(separator: "\n") }
}

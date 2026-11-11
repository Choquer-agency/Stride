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

/// One CSV per indoor run. Capture happens before the display sample is throttled,
/// so the exported hex column contains every FTMS treadmill notification received.
final class TreadmillRawCapture {
    static let shared = TreadmillRawCapture()

    private let queue = DispatchQueue(label: "com.stride.ftms-raw-capture")
    private var handle: FileHandle?
    private var packetNumber = 0
    private let directory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Treadmill Captures", isDirectory: true)
    }()
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func begin(deviceName: String?) {
        queue.sync {
            closeCurrentFile()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let stamp = timestampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let url = directory.appendingPathComponent("stride-ftms-\(stamp)-\(UUID().uuidString.prefix(8)).csv")
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return }
                handle = try FileHandle(forWritingTo: url)
                packetNumber = 0
                write("timestamp_utc,uptime_seconds,packet,characteristic_uuid,raw_hex,flags,speed_kmh,distance_m,elapsed_seconds,heart_rate_bpm\n")
                BLEDiagnosticsLog.shared.log("raw FTMS capture START \(url.lastPathComponent) — \(deviceName ?? "unknown treadmill")")
            } catch {
                BLEDiagnosticsLog.shared.log("raw FTMS capture FAILED: \(error.localizedDescription)")
            }
        }
    }

    func record(_ sample: ParsedTreadmillSample) {
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async {
            guard self.handle != nil else { return }
            self.packetNumber += 1
            let fields = [
                self.timestampFormatter.string(from: sample.timestamp),
                String(format: "%.3f", uptime),
                String(self.packetNumber),
                "2ACD",
                sample.rawHex,
                String(sample.flags),
                sample.instantaneousSpeedKmh.map { String($0) } ?? "",
                sample.totalDistanceMeters.map { String($0) } ?? "",
                sample.elapsedTime.map { String($0) } ?? "",
                sample.heartRate.map { String($0) } ?? ""
            ]
            self.write(fields.joined(separator: ",") + "\n")
            if self.packetNumber % 10 == 0 { self.handle?.synchronizeFile() }
        }
    }

    func end() {
        queue.sync { closeCurrentFile() }
    }

    func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "csv" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    private func write(_ text: String) {
        guard let bytes = text.data(using: .utf8) else { return }
        do { try handle?.write(contentsOf: bytes) }
        catch { BLEDiagnosticsLog.shared.log("raw FTMS capture WRITE FAILED: \(error.localizedDescription)") }
    }

    private func closeCurrentFile() {
        guard let handle else { return }
        handle.synchronizeFile()
        try? handle.close()
        self.handle = nil
        BLEDiagnosticsLog.shared.log("raw FTMS capture END — \(packetNumber) packets")
    }
}

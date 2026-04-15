import Foundation

/// Tracks daily ElevenLabs API character usage (excludes pre-recorded clips).
struct TTSUsageEntry: Codable, Identifiable {
    let id: UUID
    let date: String          // "yyyy-MM-dd"
    var charactersUsed: Int   // Total characters sent to API this day

    init(date: String, charactersUsed: Int = 0) {
        self.id = UUID()
        self.date = date
        self.charactersUsed = charactersUsed
    }
}

/// Persistent log of daily ElevenLabs API usage stored in UserDefaults.
final class TTSUsageLog {
    static let shared = TTSUsageLog()
    private let key = "TTSUsageLog"

    private var entries: [TTSUsageEntry] = []

    private init() {
        load()
    }

    // MARK: - Public API

    /// Log characters used for an API TTS call.
    func logCharacters(_ count: Int) {
        let today = Self.todayString()

        if let index = entries.firstIndex(where: { $0.date == today }) {
            entries[index].charactersUsed += count
        } else {
            entries.append(TTSUsageEntry(date: today, charactersUsed: count))
        }

        save()
    }

    /// Get all usage entries sorted by date descending (most recent first).
    func allEntries() -> [TTSUsageEntry] {
        entries.sorted { $0.date > $1.date }
    }

    /// Get today's character count.
    func todayUsage() -> Int {
        let today = Self.todayString()
        return entries.first(where: { $0.date == today })?.charactersUsed ?? 0
    }

    /// Get total characters used across all days.
    func totalUsage() -> Int {
        entries.reduce(0) { $0 + $1.charactersUsed }
    }

    /// Clear all usage data.
    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TTSUsageEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Helpers

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

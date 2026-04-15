import SwiftUI

/// Settings page showing daily ElevenLabs API character usage.
/// Only counts real API calls — pre-recorded bundled clips are free.
struct TTSUsageView: View {
    @State private var entries: [TTSUsageEntry] = []
    @State private var cacheSize: Int = 0

    var body: some View {
        List {
            // Summary section
            Section {
                HStack {
                    Label("Today", systemImage: "calendar")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                    Spacer()
                    Text("\(TTSUsageLog.shared.todayUsage()) chars")
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }

                HStack {
                    Label("All Time", systemImage: "chart.bar")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                    Spacer()
                    Text("\(TTSUsageLog.shared.totalUsage()) chars")
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }

                HStack {
                    Label("Voice Cache", systemImage: "internaldrive")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                    Spacer()
                    Text(formatBytes(cacheSize))
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }
            } header: {
                Text("ElevenLabs API Usage")
            } footer: {
                Text("Characters sent to ElevenLabs API. Pre-recorded clips (bundled in app) are free and not counted here. Cached phrases also don't count after first use.")
            }

            // Daily log
            Section {
                if entries.isEmpty {
                    Text("No API calls yet")
                        .font(.inter(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Text(formatDate(entry.date))
                                .font(.inter(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(entry.charactersUsed) chars")
                                .font(.barlowCondensed(size: 18, weight: .medium))
                                .foregroundColor(.primary)
                            estimatedCost(entry.charactersUsed)
                        }
                    }
                }
            } header: {
                Text("Daily Log")
            }

            // Actions
            Section {
                Button(role: .destructive) {
                    VoiceCoachService().clearCache()
                    cacheSize = 0
                } label: {
                    Label("Clear Voice Cache", systemImage: "trash")
                }

                Button(role: .destructive) {
                    TTSUsageLog.shared.clearAll()
                    entries = []
                } label: {
                    Label("Clear Usage Log", systemImage: "xmark.circle")
                }
            }
        }
        .navigationTitle("Voice Usage")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            entries = TTSUsageLog.shared.allEntries()
            cacheSize = VoiceCoachService().cacheSize()
        }
    }

    // MARK: - Helpers

    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d"

        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return dateString
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    private func estimatedCost(_ characters: Int) -> some View {
        // ElevenLabs pricing: roughly $0.30 per 1000 characters
        let cost = Double(characters) / 1000.0 * 0.30
        return Text(String(format: "$%.2f", cost))
            .font(.inter(size: 12, weight: .regular))
            .foregroundColor(.secondary)
            .frame(width: 50, alignment: .trailing)
    }
}

import Foundation
import SwiftUI
import os.log

private let chatLog = Logger(subsystem: "com.stride.app", category: "CoachChat")

/// Backing view model for `CoachChatView`.
///
/// State machine:
///   idle → sending (athlete msg appended) → streaming (coach msg incrementally
///   filling) → idle. Errors return to idle and surface via `error`.
@MainActor
final class CoachChatViewModel: ObservableObject {
    @Published private(set) var messages: [DisplayMessage] = []
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var isLoadingHistory: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var historySummary: String?
    @Published private(set) var suggestions: [String] = []
    @Published var error: String?
    @Published var draftText: String = ""

    private(set) var trainingPlanId: UUID?
    private(set) var relatedEventId: UUID?

    /// Local 15s cooldown enforcement to keep the UI in sync with the server.
    private var lastSentAt: Date?

    init(trainingPlanId: UUID? = nil, relatedEventId: UUID? = nil) {
        self.trainingPlanId = trainingPlanId
        self.relatedEventId = relatedEventId
    }

    var canSend: Bool {
        guard !isStreaming else { return false }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let last = lastSentAt, Date().timeIntervalSince(last) < 15 { return false }
        return true
    }

    var cooldownRemainingSeconds: Int {
        guard let last = lastSentAt else { return 0 }
        return max(0, Int(15 - Date().timeIntervalSince(last)))
    }

    // MARK: - Loading

    func refresh() async {
        await loadHistory(reset: true)
        await loadSuggestions()
    }

    func loadHistory(reset: Bool = false) async {
        if reset { messages.removeAll() }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let history = try await APIService.shared.coachChatHistory(
                trainingPlanId: trainingPlanId,
                limit: 50,
                before: reset ? nil : messages.first?.sentAt
            )
            self.historySummary = history.summary
            self.hasMore = history.hasMore
            let mapped = history.items.map(DisplayMessage.init(dto:))
            // Server returns chronological asc — prepend oldest, append newest.
            if reset {
                self.messages = mapped
            } else {
                self.messages = mapped + self.messages
            }
        } catch {
            chatLog.error("loadHistory failed: \(error.localizedDescription)")
            self.error = "Couldn't load chat history."
        }
    }

    func loadSuggestions() async {
        do {
            self.suggestions = try await APIService.shared.coachChatSuggestions()
        } catch {
            // Silent — we just won't show chips
            self.suggestions = []
        }
    }

    // MARK: - Sending

    func send(messageOverride: String? = nil) async {
        let raw = (messageOverride ?? draftText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard !isStreaming else { return }

        // Optimistic athlete message
        let athleteMsg = DisplayMessage.athletePending(text: raw)
        messages.append(athleteMsg)
        if messageOverride == nil { draftText = "" }
        lastSentAt = Date()

        // Streaming coach placeholder
        let coachStreaming = DisplayMessage.coachStreaming()
        messages.append(coachStreaming)
        let coachIndex = messages.count - 1
        isStreaming = true

        await APIService.shared.coachChat(
            message: raw,
            trainingPlanId: trainingPlanId,
            relatedEventId: relatedEventId,
            onChunk: { [weak self] chunk in
                Task { @MainActor in
                    guard let self else { return }
                    self.appendChunk(at: coachIndex, chunk: chunk)
                }
            },
            onMeta: { [weak self] meta in
                Task { @MainActor in
                    guard let self else { return }
                    if let coachId = meta["coach_message_id"], let uuid = UUID(uuidString: coachId) {
                        self.messages[coachIndex].id = uuid
                    }
                    if let adjId = meta["related_adjustment_id"], let uuid = UUID(uuidString: adjId) {
                        self.messages[coachIndex].relatedAdjustmentId = uuid
                    }
                }
            },
            onComplete: { [weak self] full in
                Task { @MainActor in
                    guard let self else { return }
                    self.messages[coachIndex].content = full.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.messages[coachIndex].isStreaming = false
                    self.isStreaming = false
                }
            },
            onError: { [weak self] err in
                Task { @MainActor in
                    guard let self else { return }
                    self.messages[coachIndex].isStreaming = false
                    self.messages[coachIndex].content = "(couldn't stream — \(err.localizedDescription))"
                    self.isStreaming = false
                    self.error = err.localizedDescription
                }
            }
        )
    }

    func sendSuggestion(_ chip: String) async {
        await send(messageOverride: chip)
    }

    // MARK: - Helpers

    private func appendChunk(at index: Int, chunk: String) {
        guard messages.indices.contains(index) else { return }
        messages[index].content.append(chunk)
    }
}

// MARK: - DisplayMessage

/// View-local message model. Combines server DTOs with the streaming
/// placeholder that hasn't been assigned a server id yet.
struct DisplayMessage: Identifiable {
    var id: UUID
    var role: String
    var content: String
    var sentAt: Date
    var isStreaming: Bool
    var relatedEventId: UUID?
    var relatedAdjustmentId: UUID?

    var isAthlete: Bool { role == "athlete" }
    var isCoach: Bool { role == "coach" }

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        sentAt: Date,
        isStreaming: Bool = false,
        relatedEventId: UUID? = nil,
        relatedAdjustmentId: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.sentAt = sentAt
        self.isStreaming = isStreaming
        self.relatedEventId = relatedEventId
        self.relatedAdjustmentId = relatedAdjustmentId
    }

    init(dto: CoachChatMessageDTO) {
        self.id = dto.id
        self.role = dto.role
        self.content = dto.content
        self.sentAt = dto.sentAt
        self.isStreaming = false
        self.relatedEventId = dto.relatedEventId
        self.relatedAdjustmentId = dto.relatedAdjustmentId
    }

    static func athletePending(text: String) -> DisplayMessage {
        DisplayMessage(role: "athlete", content: text, sentAt: Date())
    }

    static func coachStreaming() -> DisplayMessage {
        DisplayMessage(role: "coach", content: "", sentAt: Date(), isStreaming: true)
    }
}

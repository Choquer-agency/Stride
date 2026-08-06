import Foundation
import SwiftUI

/// Drives the interactive weekly check-in flow:
/// fetch → one-question-per-screen answering → submit → poll for the review.
@MainActor
final class WeeklyCheckinViewModel: ObservableObject {

    enum Phase: Equatable {
        case loading
        case answering
        case submitting
        case awaitingReview      // "Coach is reviewing your week…"
        case reviewReady(eventId: UUID)
        case reviewDelayed       // poll timed out — "check your inbox shortly"
        case unavailable         // no open check-in
        case error(String)
    }

    @Published var phase: Phase = .loading
    @Published var checkin: WeeklyCheckinDTO?
    @Published var questionIndex: Int = 0
    @Published var answers: [String: CheckinAnswerValue] = [:]

    /// Flattened question list including a pain follow-up when answered yes.
    var visibleQuestions: [CheckinQuestion] {
        guard let checkin else { return [] }
        var result: [CheckinQuestion] = []
        for q in checkin.questionList {
            result.append(q)
            if let follow = q.followUpIfYes, case .bool(true)? = answers[q.id] {
                result.append(CheckinQuestion(
                    id: follow.id, type: follow.type, text: follow.text,
                    options: nil, lowLabel: nil, highLabel: nil,
                    optional: nil, targeted: nil, followUpIfYes: nil
                ))
            }
        }
        return result
    }

    var currentQuestion: CheckinQuestion? {
        let qs = visibleQuestions
        guard questionIndex >= 0 && questionIndex < qs.count else { return nil }
        return qs[questionIndex]
    }

    var progress: Double {
        let count = visibleQuestions.count
        guard count > 0 else { return 0 }
        return Double(min(questionIndex + 1, count)) / Double(count)
    }

    var isLastQuestion: Bool { questionIndex >= visibleQuestions.count - 1 }

    func canAdvance(from question: CheckinQuestion) -> Bool {
        if question.optional == true { return true }
        return answers[question.id] != nil
    }

    // MARK: - Lifecycle

    func load(checkinId: String? = nil) async {
        phase = .loading
        do {
            let dto = try await APIService.shared.fetchCurrentCheckin()
            guard dto.isOpen, dto.id != nil else {
                // A specific id from a deep link that's no longer open, or nothing this week.
                if let eventId = dto.reviewEventId.flatMap(UUID.init(uuidString:)) {
                    phase = .reviewReady(eventId: eventId)
                } else {
                    phase = .unavailable
                }
                return
            }
            checkin = dto
            answers = dto.answers ?? [:]
            questionIndex = 0
            phase = .answering
        } catch {
            phase = .error("Couldn't load your check-in. Pull to retry.")
        }
    }

    func advance() {
        if isLastQuestion { return }
        questionIndex += 1
        savePartial()
    }

    func goBack() {
        guard questionIndex > 0 else { return }
        questionIndex -= 1
    }

    /// Fire-and-forget partial save so a killed app resumes where it left off.
    private func savePartial() {
        guard let id = checkin?.id else { return }
        let snapshot = answers
        Task.detached { [snapshot] in
            _ = try? await APIService.shared.saveCheckinAnswers(id: id, answers: snapshot)
        }
    }

    func submit() async {
        guard let id = checkin?.id else { return }
        phase = .submitting
        do {
            _ = try await APIService.shared.submitCheckin(id: id, answers: answers)
            phase = .awaitingReview
            await pollForReview()
        } catch {
            phase = .error("Couldn't send your answers. Check your connection and try again.")
        }
    }

    /// Poll GET /checkin/current until review_event_id appears (~60s budget).
    private func pollForReview() async {
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            if let dto = try? await APIService.shared.fetchCurrentCheckin(),
               let eventIdString = dto.reviewEventId,
               let eventId = UUID(uuidString: eventIdString) {
                phase = .reviewReady(eventId: eventId)
                return
            }
        }
        phase = .reviewDelayed
    }
}

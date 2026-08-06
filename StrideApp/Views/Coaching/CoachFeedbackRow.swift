import SwiftUI

/// First-3-events trust-building feedback row.
///
/// Surfaced on the bottom of weekly-review sheets, post-run check sheets,
/// adjustment review sheets, and other coaching event surfaces. Lets the
/// athlete tap 👍 / 👎 / 🙏 (with optional note) — submission posts to
/// `/api/coach/feedback`.
///
/// Visibility is governed externally: the parent passes `seenCount` (the
/// server-side count of feedback already given for this loop type). When
/// `seenCount >= 3`, the parent should not render this row.
struct CoachFeedbackRow: View {
    let eventId: UUID
    /// The loop type (e.g. "weekly_review") — used by the server to bucket the
    /// feedback counter on `users.coaching_feedback_seen`.
    let loopName: String
    /// Optional callback fired after a successful submit. Parent can refresh
    /// the inbox or hide the row.
    var onSubmitted: (() -> Void)? = nil

    @State private var submitting = false
    @State private var submitted: Submission?
    @State private var error: String?
    @State private var showingNoteField = false
    @State private var note = ""

    enum Submission: String { case positive, negative, unclear }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let submitted {
                acknowledgement(for: submitted)
            } else {
                buttonRow
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if showingNoteField {
                    noteField
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: submitted)
        .animation(.easeInOut(duration: 0.2), value: showingNoteField)
    }

    // MARK: - Subviews

    private var buttonRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How did this land?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                feedbackButton(label: "👍", choice: .positive, accessibility: "Looks right")
                feedbackButton(label: "👎", choice: .negative, accessibility: "Missed the mark")
                feedbackButton(label: "🙏", choice: .unclear, accessibility: "Unclear")
                Spacer()
                Button(action: { showingNoteField.toggle() }) {
                    Image(systemName: showingNoteField ? "chevron.up" : "text.bubble")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Add note")
            }
        }
    }

    private func feedbackButton(label: String, choice: Submission, accessibility: String) -> some View {
        Button {
            Task { await submit(choice) }
        } label: {
            Text(label)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .disabled(submitting)
        .accessibilityLabel(accessibility)
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optional note")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("What worked or didn't?", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        }
    }

    private func acknowledgement(for choice: Submission) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(thankYouCopy(for: choice))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func thankYouCopy(for choice: Submission) -> String {
        switch choice {
        case .positive: return "Noted — keeping this kind of read."
        case .negative: return "Got it — I'll tune this."
        case .unclear: return "Noted — I'll be more specific."
        }
    }

    // MARK: - Submit

    private func submit(_ choice: Submission) async {
        submitting = true
        defer { submitting = false }
        do {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try await APIService.shared.submitCoachingFeedback(
                eventId: eventId,
                feedback: choice.rawValue,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            submitted = choice
            onSubmitted?()
        } catch {
            self.error = "Couldn't send. Try again."
        }
    }
}

#if DEBUG
#Preview {
    VStack {
        CoachFeedbackRow(
            eventId: UUID(),
            loopName: "weekly_review",
            onSubmitted: {}
        )
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}
#endif

import SwiftUI

/// Reusable text view that renders streaming coach output with a "writing"
/// affordance — used by WeeklyReviewCardView (Phase 2), AdjustmentReviewSheet
/// (Phase 3), and CoachChatView (Phase 5).
///
/// Pass the latest accumulated text via `text` and toggle `isStreaming` while
/// chunks are still arriving. While streaming, a subtle blinking caret appears
/// at the end of the rendered text.
struct StreamingTextView: View {
    let text: String
    var isStreaming: Bool = false

    @State private var caretVisible = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(attributedText)
                .font(.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            if isStreaming {
                Text("▍")
                    .font(.body)
                    .foregroundStyle(Color.stridePrimary)
                    .opacity(caretVisible ? 1 : 0)
                    .onAppear { startBlink() }
                    .accessibilityHidden(true)
            }
        }
    }

    /// Markdown-rendered when complete; plain when streaming (markdown
    /// re-parse on every chunk would thrash AttributedString allocations).
    private var attributedText: AttributedString {
        if isStreaming {
            return AttributedString(text)
        }
        if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(text)
    }

    private func startBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            DispatchQueue.main.async {
                if !isStreaming {
                    timer.invalidate()
                    caretVisible = true
                    return
                }
                caretVisible.toggle()
            }
        }
    }
}

#if DEBUG
#Preview("Streaming") {
    VStack {
        StreamingTextView(
            text: "Strong block — three quality sessions clean and your easy paces dropped a beat.",
            isStreaming: true
        )
        .padding()
    }
}

#Preview("Complete") {
    VStack {
        StreamingTextView(
            text: "Strong **block** — three quality sessions clean and your easy paces dropped a beat.\n\nNext week, focus on staying patient on Tuesday's tempo.",
            isStreaming: false
        )
        .padding()
    }
}
#endif

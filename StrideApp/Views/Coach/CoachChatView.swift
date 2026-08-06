import AVFoundation
import SwiftUI

/// Persistent "Ask Coach" chat. Bubble UI + SSE streaming + suggested-prompt
/// chips + dictation input + inline adjustment cards. Surfaced from:
///   - PlanView "Ask Coach" button
///   - "Reply in chat" buttons on weekly review / post-run / wellness sheets
///   - stride://coach/chat?event_id={id} push deep link
struct CoachChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CoachChatViewModel

    @FocusState private var inputFocused: Bool
    @State private var showAdjustment: UUID?
    @State private var scrollToBottomToken: Int = 0

    init(trainingPlanId: UUID? = nil, relatedEventId: UUID? = nil) {
        _viewModel = StateObject(wrappedValue: CoachChatViewModel(
            trainingPlanId: trainingPlanId,
            relatedEventId: relatedEventId,
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Divider()
                messagesScroll
                inputBar
            }
            .navigationTitle("Ask Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await viewModel.refresh() }
        .sheet(item: Binding(
            get: { showAdjustment.map { ChatAdjustmentTarget(id: $0) } },
            set: { showAdjustment = $0?.id }
        )) { target in
            AdjustmentReviewSheet(adjustmentId: target.id)
        }
    }

    // MARK: - Messages list

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.hasMore {
                        loadOlderButton
                    }
                    if let summary = viewModel.historySummary {
                        summaryRow(text: summary)
                    }
                    ForEach(viewModel.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                    if viewModel.messages.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollToBottomToken) { _, _ in
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var loadOlderButton: some View {
        Button {
            Task { await viewModel.loadHistory(reset: false) }
        } label: {
            HStack {
                Spacer()
                if viewModel.isLoadingHistory {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Load older messages").font(.caption.weight(.medium))
                }
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Earlier in this conversation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func bubble(for message: DisplayMessage) -> some View {
        if message.isAthlete {
            athleteBubble(message)
        } else {
            coachBubble(message)
        }
    }

    private func athleteBubble(_ m: DisplayMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(m.content)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.stridePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func coachBubble(_ m: DisplayMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                if m.content.isEmpty && m.isStreaming {
                    streamingPlaceholder
                } else {
                    StreamingTextView(text: m.content, isStreaming: m.isStreaming)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Spacer(minLength: 60)
            }

            if let adjId = m.relatedAdjustmentId {
                Button {
                    showAdjustment = adjId
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("Coach proposed a change — review")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.stridePrimary)
                    .background(Color.stridePrimary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            if !m.isStreaming && m.isCoach {
                Button {
                    speakMessage(m.content)
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
    }

    private var streamingPlaceholder: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15), value: viewModel.isStreaming)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask coach anything")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Recent runs, recovery, plan questions, race-day strategy. Coach has the full picture.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if !viewModel.suggestions.isEmpty && viewModel.messages.isEmpty {
                suggestionsRow
            }
            if let err = viewModel.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            HStack(alignment: .center, spacing: 8) {
                TextField("Message coach…", text: $viewModel.draftText, axis: .vertical)
                    .focused($inputFocused)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(viewModel.canSend ? Color.stridePrimary : Color.gray.opacity(0.4))
                }
                .disabled(!viewModel.canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .overlay(Divider(), alignment: .top)
        }
    }

    private var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.suggestions, id: \.self) { chip in
                    Button {
                        Task { await viewModel.sendSuggestion(chip) }
                    } label: {
                        Text(chip)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.stridePrimary.opacity(0.10))
                            .foregroundStyle(Color.stridePrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isStreaming)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - TTS for "Listen"

    private func speakMessage(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        let synth = AVSpeechSynthesizer()
        synth.speak(utterance)
    }
}

private struct ChatAdjustmentTarget: Identifiable {
    let id: UUID
}

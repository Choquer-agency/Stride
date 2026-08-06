import SwiftUI
import UIKit

/// Typeform-style weekly check-in: one question per screen with a progress bar,
/// then "Coach is reviewing your week…" resolving into the streamed review.
///
/// Surfaced from `stride://coach/checkin/{id}` deep links, the Plan-tab invite
/// card, and the coach inbox.
struct WeeklyCheckinFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = WeeklyCheckinViewModel()

    /// Optional deep-link id — the flow always loads the current week's check-in.
    var checkinId: String? = nil

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Weekly check-in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                            .font(.interBody(15))
                    }
                }
        }
        .task { await viewModel.load(checkinId: checkinId) }
        .interactiveDismissDisabled(viewModel.phase == .submitting)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

        case .answering:
            answeringView

        case .submitting:
            VStack(spacing: 16) {
                ProgressView()
                Text("Sending to your coach…").font(.interBody(15)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .awaitingReview:
            VStack(spacing: 20) {
                ProgressView().controlSize(.large)
                Text("Coach is reviewing your week…")
                    .font(.interSemibold(18))
                Text("Your answers plus this week's data. This takes a moment.")
                    .font(.interBody(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .reviewReady(let eventId):
            WeeklyReviewCardView(eventId: eventId)

        case .reviewDelayed:
            VStack(spacing: 16) {
                Image(systemName: "tray.full")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Your review is on its way")
                    .font(.interSemibold(18))
                Text("It's taking longer than usual — it'll land in your coach inbox shortly.")
                    .font(.interBody(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.stridePrimary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unavailable:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No open check-in right now")
                    .font(.interSemibold(18))
                Text("Your coach will invite you at the end of the training week.")
                    .font(.interBody(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.stridePrimary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message):
            VStack(spacing: 16) {
                Text(message)
                    .font(.interBody(15))
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await viewModel.load(checkinId: checkinId) } }
                    .buttonStyle(.borderedProminent)
                    .tint(.stridePrimary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Question flow

    private var answeringView: some View {
        VStack(spacing: 0) {
            ProgressView(value: viewModel.progress)
                .tint(.stridePrimary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if let question = viewModel.currentQuestion {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if question.targeted == true {
                            Label("Your coach noticed", systemImage: "eye")
                                .font(.interSemibold(12))
                                .foregroundStyle(Color.stridePrimary)
                        }
                        Text(question.text)
                            .font(.interSemibold(22))
                            .fixedSize(horizontal: false, vertical: true)

                        answerControl(for: question)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                }
                .id(question.id)   // reset scroll per question

                navigationButtons(for: question)
            }
        }
    }

    @ViewBuilder
    private func answerControl(for question: CheckinQuestion) -> some View {
        switch question.type {
        case "scale_1_5":
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { value in
                        let selected = viewModel.answers[question.id] == .int(value)
                        Button {
                            viewModel.answers[question.id] = .int(value)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text("\(value)")
                                .font(.barlowCondensed(size: 22, weight: .semibold))
                                .frame(width: 52, height: 52)
                                .background(selected ? Color.stridePrimary : Color(.systemGray6))
                                .foregroundStyle(selected ? .white : .primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let low = question.lowLabel, let high = question.highLabel {
                    HStack {
                        Text(low).font(.interBody(12)).foregroundStyle(.secondary)
                        Spacer()
                        Text(high).font(.interBody(12)).foregroundStyle(.secondary)
                    }
                }
            }

        case "multiple_choice":
            VStack(spacing: 10) {
                ForEach(question.options ?? [], id: \.self) { option in
                    let selected = viewModel.answers[question.id] == .string(option)
                    Button {
                        viewModel.answers[question.id] = .string(option)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(option)
                            .font(.interMedium(15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(selected ? Color.stridePrimary.opacity(0.12) : Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selected ? Color.stridePrimary : .clear, lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }

        case "yes_no":
            HStack(spacing: 12) {
                ForEach([true, false], id: \.self) { value in
                    let selected = viewModel.answers[question.id] == .bool(value)
                    Button {
                        viewModel.answers[question.id] = .bool(value)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(value ? "Yes" : "No")
                            .font(.interSemibold(15))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selected ? Color.stridePrimary : Color(.systemGray6))
                            .foregroundStyle(selected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

        default: // free_text
            TextField("Type your answer…", text: freeTextBinding(for: question.id), axis: .vertical)
                .font(.interBody(15))
                .lineLimit(4...8)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func freeTextBinding(for id: String) -> Binding<String> {
        Binding(
            get: {
                if case .string(let s)? = viewModel.answers[id] { return s }
                return ""
            },
            set: { viewModel.answers[id] = .string($0) }
        )
    }

    private func navigationButtons(for question: CheckinQuestion) -> some View {
        HStack(spacing: 12) {
            if viewModel.questionIndex > 0 {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 48, height: 48)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Button {
                if viewModel.isLastQuestion {
                    Task { await viewModel.submit() }
                } else {
                    viewModel.advance()
                }
            } label: {
                Text(viewModel.isLastQuestion ? "Send to coach" : "Next")
                    .font(.interSemibold(16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.stridePrimary)
            .disabled(!viewModel.canAdvance(from: question))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

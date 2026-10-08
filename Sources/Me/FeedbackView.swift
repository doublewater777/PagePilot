import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sendState: FeedbackSendState = .idle
    @FocusState private var isMessageFocused: Bool

    private var messageLength: Int {
        FeedbackPayloadBuilder.messageLength(message)
    }

    private var isMessageOverLimit: Bool {
        messageLength > FeedbackPayloadBuilder.maximumMessageLength
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text(NSLocalizedString("feedback_message_placeholder", comment: ""))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $message)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .focused($isMessageFocused)
                            .disabled(sendState == .sending || sendState == .sent)
                            .accessibilityLabel(NSLocalizedString("settings_feedback_section", comment: ""))
                            .onChange(of: message) { _, _ in
                                if case .failed = sendState {
                                    sendState = .idle
                                }
                            }
                    }
                    .font(.body)

                    HStack {
                        if isMessageOverLimit {
                            Text(NSLocalizedString("feedback_message_too_long", comment: ""))
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Text("\(messageLength) / \(FeedbackPayloadBuilder.maximumMessageLength)")
                            .foregroundStyle(isMessageOverLimit ? Color.red : Color.secondary)
                    }
                    .font(.caption)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                Button(action: submitFeedback) {
                    Group {
                        if sendState == .sending {
                            ProgressView().tint(.white)
                        } else {
                            Label(
                                NSLocalizedString(sendState == .sent ? "feedback_submitted" : "feedback_submit", comment: ""),
                                systemImage: sendState == .sent ? "checkmark.circle.fill" : "paperplane.fill"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    sendState == .sending || sendState == .sent ||
                    message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    isMessageOverLimit
                )

                switch sendState {
                case .sent:
                    Label(NSLocalizedString("feedback_received", comment: ""), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failed(let error):
                    Label(NSLocalizedString(error.localizationKey, comment: ""), systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                case .idle, .sending:
                    EmptyView()
                }
            }
            .frame(maxWidth: 600)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("settings_feedback_section", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func submitFeedback() {
        guard let payload = try? FeedbackPayloadBuilder().build(message: message) else { return }
        isMessageFocused = false
        sendState = .sending

        Task { @MainActor in
            do {
                try await FeedbackSubmissionService().submit(payload)
                sendState = .sent
                message = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .milliseconds(1200))
                dismiss()
            } catch let error as FeedbackSubmissionError {
                sendState = .failed(error)
            } catch {
                sendState = .failed(.rejected)
            }
        }
    }
}

private enum FeedbackSendState: Equatable {
    case idle
    case sending
    case sent
    case failed(FeedbackSubmissionError)
}

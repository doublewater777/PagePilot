import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sendState: FeedbackSendState = .idle
    @State private var isToastVisible = false
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
                            Label(NSLocalizedString("feedback_submit", comment: ""), systemImage: "paperplane.fill")
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
        .overlay(alignment: .bottom) {
            if isToastVisible, let result = sendState.toastResult {
                Label(NSLocalizedString(result.messageKey, comment: ""), systemImage: result.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isToastVisible)
        .task(id: sendState) {
            guard let result = sendState.toastResult else {
                isToastVisible = false
                return
            }
            isToastVisible = true
            UIAccessibility.post(notification: .announcement, argument: NSLocalizedString(result.messageKey, comment: ""))
            do {
                try await Task.sleep(for: .seconds(sendState == .sent ? 2 : 3))
            } catch {
                return
            }
            isToastVisible = false
            if sendState == .sent { dismiss() }
        }
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

    var toastResult: (messageKey: String, icon: String)? {
        switch self {
        case .sent: return ("feedback_received", "checkmark.circle.fill")
        case .failed(let error): return (error.localizationKey, "exclamationmark.circle.fill")
        case .idle, .sending: return nil
        }
    }
}

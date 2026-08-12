import SwiftUI
import AnumCore

/// Lightweight compose surface for `ExchangeFacade.sendManualMessageToTrustedNode` (Trust tab + thread detail).
struct SecretaryDirectMessageComposeSheet: View {
    let displayName: String
    let nodeID: String
    let onSend: (String) async throws -> ExchangeThread.ID
    let onSuccess: (ExchangeThread.ID) -> Void
    let onCancel: () -> Void

    @State private var messageBody: String = ""
    @State private var isSending = false
    @State private var sendFailed = false

    private var trimmedBody: String {
        messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSendDisabled: Bool {
        trimmedBody.isEmpty || isSending
    }

    var body: some View {
        NavigationStack {
            ZStack {
                UnifyIceShellBackground()

                VStack(alignment: .leading, spacing: 16) {
                    Text("To \(displayName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Text(
                        "This sends using your saved path to this contact when their public coordination surface allows direct messages."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                    if sendFailed {
                        Text("Could\u{2019}t send this message.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.85))
                    }

                    TextField("Write your message…", text: $messageBody, axis: .vertical)
                        .font(.system(size: 17))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .tint(SecretaryTheme.darkOrange)
                        .lineLimit(3...8)
                        .padding(14)
                        .background {
                            UnifyGlassTextFieldChrome(cornerRadius: 16, strokeOpacity: 0.88)
                        }
                        .disabled(isSending)

                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Message \(displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                // Match `SecretaryStyleSettingsView` leading/trailing toolbar controls (text-only, no capsule chrome).
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .disabled(isSending)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Sending…" : "Send") {
                        sendFailed = false
                        Task { @MainActor in
                            isSending = true
                            defer { isSending = false }
                            do {
                                let threadID = try await onSend(trimmedBody)
                                onSuccess(threadID)
                            } catch {
                                #if DEBUG
                                Swift.print("[ConversationCardSend][uiFailed] error=\(error)")
                                #endif
                                sendFailed = true
                            }
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSendDisabled ? SecretaryTheme.darkMutedText : SecretaryTheme.darkOrange)
                    .disabled(isSendDisabled)
                }
            }
        }
        .tint(SecretaryTheme.darkOrange)
    }
}

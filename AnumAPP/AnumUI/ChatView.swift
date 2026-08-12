import SwiftUI
import InnerSelfCore
import AnumCore

struct ChatView: View {
    let companionName: String
    let userName: String
    let showComposer: Bool
    let isSecretaryMode: Bool
    let onOpenSecretaryWorkspace: ((SecretaryWorkspaceView.Route) -> Void)?

    private let headerReserveTop: CGFloat = 72

    @EnvironmentObject private var chat: ChatViewModel
    @FocusState private var inputFocused: Bool

    @State private var didInitialAutoScroll: Bool = false
    private let bottomAnchorId: String = "__BOTTOM__"

    private var lastMessageSignature: String {
        guard let last = chat.messages.last else { return "" }
        return "\(last.id.uuidString)|\(last.role)|\(last.text.count)"
    }

    var body: some View {
        VStack(spacing: 10) {
            if isSecretaryMode {
                secretaryModeEntry
            } else {
                messageList

                if showComposer {
                    companionComposer
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .onAppear {
            inputFocused = false
        }
    }

    private var secretaryModeEntry: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 12)

            VStack(spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))

                VStack(spacing: 8) {
                    Text("Secretary mode")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Move into the workspace to review threads, approvals, trusted paths, and next actions.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                }

                Button {
                    inputFocused = false
                    onOpenSecretaryWorkspace?(.dashboard)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 18, weight: .semibold))

                        Text("Open Secretary")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            if #available(iOS 17.0, *) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(chat.messages) { msg in
                            bubble(msg)
                                .id(msg.id)
                        }

                        Color.clear
                            .frame(height: 6)
                            .id(bottomAnchorId)
                    }
                    .padding(.top, headerReserveTop)
                }
                .scrollDismissesKeyboard(.never)
                .onAppear {
                    didInitialAutoScroll = false
                }
                .onChange(of: chat.messages.count) { _, _ in
                    guard let last = chat.messages.last else { return }

                    if !didInitialAutoScroll {
                        didInitialAutoScroll = true
                        proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                        return
                    }

                    if last.role == .user {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .top)
                        }
                    } else {
                        proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                    }
                }
                .onChange(of: lastMessageSignature) { _, _ in
                    guard chat.isBusy, let last = chat.messages.last, last.role == .assistant else { return }
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(chat.messages) { msg in
                            bubble(msg)
                                .id(msg.id)
                        }

                        Color.clear
                            .frame(height: 6)
                            .id(bottomAnchorId)
                    }
                    .padding(.top, headerReserveTop)
                }
                .scrollDismissesKeyboard(.never)
                .onAppear {
                    didInitialAutoScroll = false
                }
                .onChange(of: chat.messages.count) { _ in
                    guard let last = chat.messages.last else { return }

                    if !didInitialAutoScroll {
                        didInitialAutoScroll = true
                        proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                        return
                    }

                    if last.role == .user {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .top)
                        }
                    } else {
                        proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                    }
                }
                .onChange(of: lastMessageSignature) { _ in
                    guard chat.isBusy, let last = chat.messages.last, last.role == .assistant else { return }
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: 340)
        .padding(.bottom, 4)
    }

    private func bubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.role == .assistant {
                let isPrefillEmpty = chat.isBusy && msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                VStack(alignment: .leading, spacing: 4) {
                    Text(companionName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                    if isPrefillEmpty {
                        TypingDots()
                            .padding(.top, 2)
                    } else {
                        markdownText(msg.text)
                            .foregroundStyle(.white.opacity(0.92))
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
            } else {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(userName.isEmpty ? "You" : userName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    markdownText(msg.text)
                        .foregroundStyle(.white.opacity(0.92))
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var companionComposer: some View {
        HStack(spacing: 10) {
            TextField("Say something…", text: $chat.input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)

            if chat.isBusy {
                Button {
                    chat.cancelGeneration()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                }
                .tint(.white.opacity(0.9))
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(chat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .tint(.white.opacity(0.9))
            }
        }
    }

    private func send() {
        let trimmed = chat.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputFocused = false
        chat.send()
    }

    private func markdownText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(markdown: raw) {
            return Text(attributed)
        }
        return Text(raw)
    }
}

private struct TypingDots: View {
    @State private var anim: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.white.opacity(0.90))
                    .scaleEffect(anim ? 0.70 : 1.0)
                    .opacity(anim ? 0.35 : 0.90)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.14),
                        value: anim
                    )
            }
        }
        .onAppear { anim = true }
        .accessibilityLabel("Typing")
    }
}

#Preview {
    let orch = AppOrchestrator(model: StubModelProvider())
    let services = AppServices(orchestrator: orch)

    return ChatView(
        companionName: "Uni",
        userName: "Kai",
        showComposer: true,
        isSecretaryMode: false,
        onOpenSecretaryWorkspace: nil
    )
    .environmentObject(services)
    .environmentObject(services.chat)
    .background(Color.black)
}

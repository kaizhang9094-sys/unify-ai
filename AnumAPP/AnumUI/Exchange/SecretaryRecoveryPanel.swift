import SwiftUI
import AnumCore

struct SecretaryRecoveryPanel: View {
    typealias Display = SecretaryRecoveryPanelDisplay

    let display: Display
    let onPrimaryAction: () async -> Void
    let onSecondaryAction: () async -> Void
    let onOpenThread: ((ExchangeThread.ID?) -> Void)?

    @State private var isBusy = false

    init(
        display: Display,
        onPrimaryAction: @escaping () async -> Void,
        onSecondaryAction: @escaping () async -> Void,
        onOpenThread: ((ExchangeThread.ID?) -> Void)? = nil
    ) {
        self.display = display
        self.onPrimaryAction = onPrimaryAction
        self.onSecondaryAction = onSecondaryAction
        self.onOpenThread = onOpenThread
    }

    var body: some View {
        ZStack(alignment: .top) {
            UnifyDarkBackground(showsSubtleVignette: true)

            LinearGradient(
                colors: [
                    SecretaryTheme.darkOrange.opacity(0.10),
                    SecretaryTheme.darkOrange.opacity(0.03),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    anatomyCard
                    actionCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Dark chrome

    @ViewBuilder
    private func recoveryDarkCard<Content: View>(
        cornerRadius: CGFloat = SecretaryTheme.Layout.radiusLarge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func recoverySectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SecretaryTheme.darkOrangeSoft.opacity(0.38))
                )
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
            Spacer(minLength: 0)
        }
    }

    private func recoveryAttentionChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkOrange)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkOrangeSoft.opacity(0.48))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkOrange.opacity(0.38), lineWidth: 1)
            )
    }

    private func recoveryMutedChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
            )
    }

    private func recoveryPrimaryButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.92)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(disabled ? SecretaryTheme.darkSurfaceStrong : SecretaryTheme.darkOrange)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(disabled ? 0.75 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func recoverySecondaryButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(SecretaryTheme.darkPrimaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var heroCard: some View {
        recoveryDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    recoveryAttentionChip(display.recoveryType)

                    recoveryMutedChip("Recovery")
                }

                Text(display.title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Recovery turns hidden failure into visible state and a recommended next move.")
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var anatomyCard: some View {
        recoveryDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                recoverySectionHeader(
                    title: "Recovery anatomy",
                    systemImage: "arrow.clockwise"
                )

                block(label: "What happened", value: display.whatHappened)
                block(label: "What did not happen", value: display.whatDidNotHappen)
                block(label: "External effect", value: display.externalEffect)
                block(label: "Best next move", value: display.bestNextMove)
            }
        }
    }

    private func block(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionCard: some View {
        recoveryDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                recoverySectionHeader(
                    title: "Choose the recovery path",
                    systemImage: "exclamationmark.shield"
                )

                Text("Use the recommended next move as the default, or hold the thread if you do not want recovery to continue yet.")
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 10) {
                    recoverySecondaryButton(
                        title: display.secondaryTitle,
                        systemImage: "pause",
                        disabled: isBusy
                    ) {
                        runAction(onSecondaryAction)
                    }
                    .opacity(isBusy ? 0.55 : 1.0)
                    .frame(maxWidth: .infinity)

                    recoveryPrimaryButton(
                        title: isBusy ? "Working…" : display.primaryTitle,
                        systemImage: "arrow.clockwise",
                        disabled: isBusy,
                        isLoading: isBusy
                    ) {
                        runAction(onPrimaryAction)
                    }
                    .opacity(isBusy ? 0.72 : 1.0)
                    .frame(maxWidth: .infinity)
                }

                if let onOpenThread {
                    recoverySecondaryButton(
                        title: "Open full thread",
                        systemImage: "rectangle.stack",
                        disabled: isBusy
                    ) {
                        guard !isBusy else { return }
                        onOpenThread(display.threadID)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func runAction(_ action: @escaping () async -> Void) {
        guard !isBusy else { return }

        Task {
            isBusy = true
            defer { isBusy = false }
            await action()
        }
    }
}

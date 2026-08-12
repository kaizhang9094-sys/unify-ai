import SwiftUI

struct SecretaryTrustedPathPanel: View {
    typealias Display = SecretaryTrustedPathPanelDisplay

    let display: Display
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

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
                    relationshipCard
                    examplesCard
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
    private func trustedPathDarkCard<Content: View>(
        cornerRadius: CGFloat = SecretaryTheme.Layout.radiusLarge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func trustedPathSectionHeader(title: String, systemImage: String) -> some View {
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

    private func trustedPathAttentionChip(_ title: String) -> some View {
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

    private func trustedPathMutedChip(_ title: String) -> some View {
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

    private func trustedPathPrimaryButton(
        title: String,
        systemImage: String,
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
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkOrange)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func trustedPathSecondaryButton(
        title: String,
        systemImage: String,
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
    }

    private var heroCard: some View {
        trustedPathDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    trustedPathAttentionChip(display.relationshipLabel)

                    trustedPathMutedChip(display.activityLabel)
                }

                Text(display.title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(display.summary)
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var relationshipCard: some View {
        trustedPathDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                trustedPathSectionHeader(
                    title: "Relationship context",
                    systemImage: "person.2"
                )

                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(SecretaryTheme.darkOrangeSoft.opacity(0.22))
                            .frame(width: 56, height: 56)

                        Image(systemName: "person.2.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        infoBlock(label: "Path type", value: display.relationshipLabel)
                        infoBlock(label: "Trust read", value: display.trustLabel)
                        infoBlock(
                            label: "What this is",
                            value: "This is still a thread-derived trust view. It explains the currently visible relationship path, not a canonical trust-record surface."
                        )
                    }
                }
            }
        }
    }

    private var examplesCard: some View {
        trustedPathDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                trustedPathSectionHeader(
                    title: "What you can do from here",
                    systemImage: "arrow.triangle.branch"
                )

                if display.examples.isEmpty {
                    Text("No actions or examples are visible yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(display.examples.indices, id: \.self) { index in
                            exampleRow(display.examples[index])
                        }
                    }
                }
            }
        }
    }

    private func exampleRow(_ example: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(SecretaryTheme.darkOrange.opacity(0.72))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            Text(example)
                .font(.system(size: 15))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionCard: some View {
        trustedPathDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                trustedPathSectionHeader(
                    title: "Next move",
                    systemImage: "arrow.right.circle"
                )

                Text(
                    display.trustComposerFallback
                        ? "There isn’t an open thread for this trusted contact yet. Ask your secretary for guidance, or send a short note through the usual channel."
                        : display.sendPreparedDraftAvailable
                        ? "A prepared message is ready to send on this thread, or you can open the full thread first."
                        : "Open the thread to continue through this path, or back out without changing anything."
                )
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    trustedPathSecondaryButton(
                        title: display.secondaryTitle,
                        systemImage: display.sendPreparedDraftAvailable ? "bubble.left.and.bubble.right" : "xmark",
                        action: onSecondaryAction
                    )
                    .frame(maxWidth: .infinity)

                    trustedPathPrimaryButton(
                        title: display.primaryTitle,
                        systemImage: display.sendPreparedDraftAvailable ? "paperplane.fill" : "arrow.right",
                        action: onPrimaryAction
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func infoBlock(label: String, value: String) -> some View {
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
}

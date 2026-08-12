import SwiftUI
import AnumCore

struct SecretaryThreadTimelineView: View {
    let detail: ExchangeModels.ThreadDetail

    private var timelineItems: [ExchangeModels.ThreadTimelineItem] {
        detail.timelineItems
    }

    var body: some View {
        UnifyDarkCard(cornerRadius: SecretaryTheme.Layout.radiusLarge) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if timelineItems.isEmpty {
                    emptyTimeline
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                            let presented = SecretaryProjectionEngine.presentedThreadTimelineRow(item: item)
                            timelineRow(
                                item,
                                presented: presented,
                                index: index,
                                isLatest: index == 0,
                                isLast: index == timelineItems.count - 1
                            )
                        }
                    }
                }
            }
            .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.85))
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .frame(width: 40, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("What happened")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
            }

            Spacer(minLength: 0)

            if !timelineItems.isEmpty {
                Text("\(timelineItems.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SecretaryTheme.darkOrange)
                    )
            }
        }
    }

    private var emptyTimeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.85))
                Image(systemName: "clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing here yet.")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text("Updates will show as the exchange moves forward.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineSpacing(1.25)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(SecretaryTheme.darkSurface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
        )
    }

    // MARK: - Row

    private func timelineRow(
        _ item: ExchangeModels.ThreadTimelineItem,
        presented: SecretaryProjectionEngine.ThreadTimelinePresentedRow,
        index: Int,
        isLatest: Bool,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            rail(
                item: item,
                isLatest: isLatest,
                isLast: isLast
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            toneLabel(for: item)

                            if isLatest {
                                Text("Latest")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(SecretaryTheme.darkOrange)
                                    )
                            }
                        }

                        Text(presented.title)
                            .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(timeText(item.date))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if let summary = cleanSecondary(presented.summary) {
                    Text(summary)
                        .font(.system(size: 14.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineSpacing(1.25)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let secondary = cleanSecondary(presented.secondary) {
                    secondaryNote(secondary, isAttention: item.tone == .warning || item.tone == .blocked)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isAttention: item.tone == .warning || item.tone == .blocked))
            .overlay(rowStroke(isAttention: item.tone == .warning || item.tone == .blocked))
        }
    }

    private func rail(
        item: ExchangeModels.ThreadTimelineItem,
        isLatest: Bool,
        isLast: Bool
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isLatest ? SecretaryTheme.darkOrange : SecretaryTheme.darkSurfaceStrong.opacity(0.92))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(
                                isLatest
                                ? SecretaryTheme.darkOrange.opacity(0.85)
                                : SecretaryTheme.darkStroke.opacity(0.8),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: isLatest ? SecretaryTheme.darkOrange.opacity(0.22) : SecretaryTheme.darkShadow.opacity(0.2),
                        radius: isLatest ? 10 : 6,
                        x: 0,
                        y: isLatest ? 5 : 3
                    )

                Image(systemName: icon(for: item.tone))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isLatest ? Color.white : iconColor(for: item.tone))
            }

            if !isLast {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                lineColor(for: item.tone).opacity(0.5),
                                SecretaryTheme.darkStroke.opacity(0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1.4)
                    .frame(minHeight: 74)
                    .padding(.top, 8)
            }
        }
        .frame(width: 32)
    }

    // MARK: - Small components

    private func toneLabel(for item: ExchangeModels.ThreadTimelineItem) -> some View {
        Text(label(for: item.tone))
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(iconColor(for: item.tone))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(labelFill(for: item.tone))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(lineColor(for: item.tone).opacity(0.42), lineWidth: 1)
            )
    }

    private func secondaryNote(_ text: String, isAttention: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isAttention ? SecretaryTheme.darkOrange : SecretaryTheme.darkMutedText)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .lineSpacing(1.2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isAttention ? SecretaryTheme.darkOrangeSoft.opacity(0.45) : SecretaryTheme.darkSurface.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isAttention ? SecretaryTheme.darkOrange.opacity(0.35) : SecretaryTheme.darkStroke.opacity(0.72),
                    lineWidth: 1
                )
        )
    }

    private func rowBackground(isAttention: Bool) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(isAttention ? SecretaryTheme.darkOrangeSoft.opacity(0.35) : SecretaryTheme.darkSurface.opacity(0.9))
            .overlay(
                LinearGradient(
                    colors: [
                        SecretaryTheme.darkSurfaceStrong.opacity(0.35),
                        SecretaryTheme.darkBackground.opacity(0.08),
                        isAttention ? SecretaryTheme.darkOrange.opacity(0.06) : Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
    }

    private func rowStroke(isAttention: Bool) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(
                isAttention ? SecretaryTheme.darkOrange.opacity(0.38) : SecretaryTheme.darkStroke.opacity(0.72),
                lineWidth: 1
            )
    }

    // MARK: - Tone mapping

    private func label(for tone: ExchangeModels.ThreadTimelineItem.Tone) -> String {
        switch tone {
        case .neutral:
            return "Noted"
        case .active:
            return "Moved"
        case .success:
            return "Settled"
        case .warning:
            return "Needs you"
        case .blocked:
            return "Care"
        }
    }

    private func icon(for tone: ExchangeModels.ThreadTimelineItem.Tone) -> String {
        switch tone {
        case .neutral:
            return "circle"
        case .active:
            return "sparkles"
        case .success:
            return "checkmark"
        case .warning:
            return "exclamationmark"
        case .blocked:
            return "xmark"
        }
    }

    private func iconColor(for tone: ExchangeModels.ThreadTimelineItem.Tone) -> Color {
        switch tone {
        case .warning, .blocked:
            return SecretaryTheme.darkOrange
        case .active:
            return SecretaryTheme.darkOrange
        case .success:
            return SecretaryTheme.darkPrimaryText
        case .neutral:
            return SecretaryTheme.darkMutedText
        }
    }

    private func labelFill(for tone: ExchangeModels.ThreadTimelineItem.Tone) -> Color {
        switch tone {
        case .warning, .blocked:
            return SecretaryTheme.darkOrangeSoft.opacity(0.5)
        case .active, .success:
            return SecretaryTheme.darkSurfaceStrong.opacity(0.75)
        case .neutral:
            return SecretaryTheme.darkSurfaceStrong.opacity(0.55)
        }
    }

    private func lineColor(for tone: ExchangeModels.ThreadTimelineItem.Tone) -> Color {
        switch tone {
        case .warning, .blocked:
            return SecretaryTheme.darkOrange
        case .active, .success:
            return SecretaryTheme.darkStroke
        case .neutral:
            return SecretaryTheme.darkStroke.opacity(0.85)
        }
    }

    // MARK: - Text helpers

    private func cleanSecondary(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func timeText(_ date: Date) -> String {
        let relative = SecretaryRelativeTime.string(from: date)
        let clock = date.formatted(date: .omitted, time: .shortened)
        return "\(relative)\n\(clock)"
    }
}

import SwiftUI
import AnumCore

struct SecretaryFocusDisplay {
    enum Mode {
        case idle
        case clarification
        case failure
        case found
        case active
        case waiting
    }

    let mode: Mode
    let isLive: Bool

    let headerEyebrow: String
    let headerSubeyebrow: String
    let badgeTitle: String

    let title: String
    let summary: String

    let boundaryTitle: String
    let boundaryText: String

    let primaryCTA: String
    let primaryIcon: String
    let secondaryCTA: String
    let secondaryIcon: String

    let clarificationQuestion: String?
    let clarificationWhy: String?

    let failureSummary: String?
    let failureReason: String?
    let failureNext: String?

    let foundHeading: String?
    let foundPrimary: String?
    let foundSecondary: String?
    let draftPreview: String?
    let foundNext: String?

    let nextTitle: String
    let nextText: String

    let trace: ExchangeModels.WorkTraceCard?
    let execution: SecretaryExecutionDisplay?
}

struct SecretaryFocusStage: View {
    let display: SecretaryFocusDisplay
    let onOpenPrimary: () -> Void
    let onOpenSecondary: () -> Void

    private let maxVisibleTraceRows = 5

    var body: some View {
        SecretarySurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                header
                titleBlock
                contentBlock
                boundaryBlock
                actionRow
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SecretaryLiveGlyph(isActive: display.isLive)

            VStack(alignment: .leading, spacing: 2) {
                Text(display.headerEyebrow)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SecretaryTheme.ink.opacity(0.86))

                Text(display.headerSubeyebrow)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SecretaryTheme.ink.opacity(0.54))
            }

            Spacer(minLength: 8)

            SecretaryThreadStateBadge(title: display.badgeTitle)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.title)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(SecretaryTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(display.summary)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SecretaryTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var contentBlock: some View {
        switch display.mode {
        case .clarification:
            clarificationBlock

        case .failure:
            failureBlock

        case .found:
            foundResultBlock

        case .active, .waiting:
            if let trace = display.trace, !trace.steps.isEmpty {
                progressBlock(trace)
            } else if let execution = display.execution {
                SecretaryExecutionStageView(display: execution)
            } else {
                nextBlock
            }

        case .idle:
            nextBlock
        }
    }

    private func progressBlock(_ trace: ExchangeModels.WorkTraceCard) -> some View {
        let rows = traceRows(trace)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Progress")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.ink.opacity(0.72))

                Spacer(minLength: 0)

                Text(traceStatusText(trace))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(traceStatusColor(trace.status))
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { step in
                    traceRow(
                        step: step,
                        isLast: step.id == rows.last?.id
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SecretaryTheme.secondaryFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SecretaryTheme.stroke, lineWidth: 1)
            )
        }
    }

    private var nextBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.nextTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.72))

            Text(display.nextText)
                .font(.system(size: 15))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SecretaryTheme.secondaryFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SecretaryTheme.stroke, lineWidth: 1)
        )
    }

    private var foundResultBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display.foundHeading ?? "Result")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.72))

            VStack(alignment: .leading, spacing: 12) {
                if let foundPrimary = nonEmpty(display.foundPrimary) {
                    Text(foundPrimary)
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.ink.opacity(0.80))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let foundSecondary = nonEmpty(display.foundSecondary) {
                    Text(foundSecondary)
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.softText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let draftPreview = nonEmpty(display.draftPreview) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Draft preview")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.ink.opacity(0.62))

                        Text(draftPreview)
                            .font(.system(size: 14))
                            .foregroundStyle(SecretaryTheme.ink.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(SecretaryTheme.stroke.opacity(0.9), lineWidth: 1)
                            )
                    }
                }

                if let foundNext = nonEmpty(display.foundNext) {
                    Divider()
                        .overlay(SecretaryTheme.stroke.opacity(0.85))
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.ink.opacity(0.62))

                        Text(foundNext)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SecretaryTheme.secondaryFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SecretaryTheme.stroke, lineWidth: 1)
            )
        }
    }

    private var failureBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happened")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.72))

            VStack(alignment: .leading, spacing: 10) {
                Text(display.failureSummary ?? "This thread needs recovery.")
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.ink.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)

                if let failureReason = nonEmpty(display.failureReason) {
                    Text(failureReason)
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.softText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let failureNext = nonEmpty(display.failureNext) {
                    Divider()
                        .overlay(SecretaryTheme.stroke.opacity(0.85))
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.ink.opacity(0.62))

                        Text(failureNext)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SecretaryTheme.secondaryFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SecretaryTheme.stroke, lineWidth: 1)
            )
        }
    }

    private var clarificationBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Still needed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.72))

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.ink.opacity(0.62))

                    Text(display.clarificationQuestion ?? "A bit more detail is needed.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SecretaryTheme.ink.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let clarificationWhy = nonEmpty(display.clarificationWhy) {
                    Divider()
                        .overlay(SecretaryTheme.stroke.opacity(0.85))
                        .padding(.vertical, 2)

                    Text(clarificationWhy)
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.softText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SecretaryTheme.secondaryFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SecretaryTheme.stroke, lineWidth: 1)
            )
        }
    }

    private func traceRow(
        step: ExchangeModels.WorkTraceCard.Step,
        isLast: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                traceGlyph(for: step)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(step.title)
                            .font(.system(size: 14, weight: step.isActive ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(SecretaryTheme.ink)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        Text(SecretaryRelativeTime.string(from: step.updatedAt))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(SecretaryTheme.softText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if let detail = nonEmpty(step.detail) {
                        Text(detail)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(SecretaryTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !isLast {
                Divider()
                    .overlay(SecretaryTheme.stroke.opacity(0.85))
                    .padding(.leading, 40)
            }
        }
    }

    @ViewBuilder
    private func traceGlyph(for step: ExchangeModels.WorkTraceCard.Step) -> some View {
        if step.isActive {
            Circle()
                .fill(SecretaryTheme.gold)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(SecretaryTheme.gold.opacity(0.32), lineWidth: 6)
                        .frame(width: 18, height: 18)
                )
                .padding(.top, 5)
        } else if step.isComplete {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.gold)
                .padding(.top, 3)
        } else {
            Circle()
                .stroke(SecretaryTheme.ink.opacity(0.28), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
        }
    }

    private var boundaryBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.boundaryTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.72))

            Text(display.boundaryText)
                .font(.system(size: 14))
                .foregroundStyle(SecretaryTheme.softText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            SecretaryActionButton(
                title: display.primaryCTA,
                systemImage: display.primaryIcon,
                prominent: true,
                action: onOpenPrimary
            )

            SecretaryActionButton(
                title: display.secondaryCTA,
                systemImage: display.secondaryIcon,
                prominent: false,
                action: onOpenSecondary
            )
        }
    }

    private func traceRows(_ trace: ExchangeModels.WorkTraceCard) -> [ExchangeModels.WorkTraceCard.Step] {
        if trace.steps.count <= maxVisibleTraceRows {
            return trace.steps.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                return lhs.createdAt < rhs.createdAt
            }
        }

        let sorted = trace.steps.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.createdAt < rhs.createdAt
        }

        return Array(sorted.suffix(maxVisibleTraceRows))
    }

    private func traceStatusText(_ trace: ExchangeModels.WorkTraceCard) -> String {
        switch trace.status {
        case .idle: return "Idle"
        case .running: return "Live"
        case .completed: return "Done"
        case .blocked: return "Blocked"
        }
    }

    private func traceStatusColor(_ status: ExchangeModels.WorkTraceCard.Status) -> Color {
        switch status {
        case .idle:
            return SecretaryTheme.softText
        case .running:
            return SecretaryTheme.gold
        case .completed, .blocked:
            return SecretaryTheme.ink.opacity(0.72)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

import SwiftUI
import AnumCore

struct SecretaryApprovalSheet: View {
    typealias Display = SecretaryApprovalPanelDisplay

    let display: Display
    let isSubmitting: Bool
    let onApprove: () async -> Void
    let onReject: () async -> Void
    let onOpenThread: ((ExchangeThread.ID?) -> Void)?

    @State private var localSubmitting = false

    init(
        display: Display,
        isSubmitting: Bool = false,
        onApprove: @escaping () async -> Void,
        onReject: @escaping () async -> Void,
        onOpenThread: ((ExchangeThread.ID?) -> Void)? = nil
    ) {
        self.display = display
        self.isSubmitting = isSubmitting
        self.onApprove = onApprove
        self.onReject = onReject
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
                    headerCard

                    if hasDecisionPacket {
                        decisionPacketCard
                    }

                    if hasCommitmentBoundary {
                        commitmentBoundaryCard
                    }

                    if showsPersistedDraftPreview {
                        draftCard
                    }

                    if hasFactFrame {
                        factFrameCard
                    }

                    if hasExtraSections {
                        extraSectionsCard
                    }

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
    private func approvalDarkCard<Content: View>(
        cornerRadius: CGFloat = SecretaryTheme.Layout.radiusLarge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func approvalPanelSectionHeader(title: String, systemImage: String) -> some View {
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

    private func approvalAttentionChip(_ title: String) -> some View {
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

    private func approvalMutedChip(_ title: String) -> some View {
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

    private func approvalPrimaryButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        isLoading: Bool = false,
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
                    .stroke(
                        SecretaryTheme.darkStroke.opacity(disabled ? 0.75 : 0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func approvalSecondaryButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(SecretaryTheme.darkPrimaryText)
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

    private var isBusy: Bool {
        isSubmitting || localSubmitting
    }

    private var hasDecisionPacket: Bool {
        cleaned(display.decisionSummary) != nil ||
        cleaned(display.recommendation) != nil
    }

    private var hasCommitmentBoundary: Bool {
        display.hasCommitmentBoundary
    }

    /// Derived from projection fields that are only populated for persisted actionable outbound drafts (or explicit preview text).
    private var showsPersistedDraftPreview: Bool {
        cleaned(display.draftSubject) != nil ||
        cleaned(display.draftBody) != nil
    }

    private var hasFactFrame: Bool {
        !cleanedList(display.clarifiedFacts).isEmpty ||
        !cleanedList(display.unresolvedIssues).isEmpty ||
        !cleanedList(display.tradeoffs).isEmpty ||
        !cleanedList(display.whatChanged).isEmpty ||
        !cleanedList(display.approvalReasons).isEmpty
    }

    private var hasExtraSections: Bool {
        display.extraSections.contains(where: \.isRenderable)
    }

    // MARK: - Header

    private var headerCard: some View {
        approvalDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    approvalAttentionChip(display.decisionType)

                    approvalMutedChip(
                        display.requiresHumanApproval
                            ? "Approval required"
                            : (display.prefersSecondHalfPreparedSend && display.approvalID == nil
                                ? "Ready to send"
                                : "Review needed")
                    )
                }

                Text(display.title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(display.summary)
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                let boundaryTrimmed = display.boundary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !boundaryTrimmed.isEmpty,
                   SecretaryProjectionEngine.passesApprovalSheetBoundaryPublicCopy(boundaryTrimmed) {
                    infoBlock(
                        label: "Boundary",
                        value: boundaryTrimmed,
                        valueStyle: .soft
                    )
                }

                if let rationale = cleaned(display.rationale),
                   SecretaryProjectionEngine.passesApprovalSheetBoundaryPublicCopy(rationale) {
                    infoBlock(
                        label: "Why the secretary stopped here",
                        value: rationale,
                        valueStyle: .soft
                    )
                }
            }
        }
    }

    // MARK: - Decision Packet

    private var decisionPacketCard: some View {
        approvalDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                approvalPanelSectionHeader(
                    title: "Decision Packet",
                    systemImage: "checkmark.seal"
                )

                if let summary = cleaned(display.decisionSummary) {
                    infoBlock(
                        label: "Decision summary",
                        value: summary
                    )
                }

                if let recommendation = cleaned(display.recommendation) {
                    infoBlock(
                        label: "Recommendation",
                        value: recommendation
                    )
                }

                if cleaned(display.decisionSummary) == nil,
                   cleaned(display.recommendation) == nil {
                    Text("This approval is decision-aware, but no decision packet detail is available yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Commitment Boundary

    private var commitmentBoundaryCard: some View {
        approvalDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                approvalPanelSectionHeader(
                    title: "Commitment Boundary",
                    systemImage: "lock.shield"
                )

                if let boundaryDetail = commitmentBoundaryDetailTextForCard(), !boundaryDetail.isEmpty {
                    infoBlock(
                        label: cleaned(display.commitmentBoundaryTitle) ?? "Approval boundary",
                        value: boundaryDetail,
                        valueStyle: .soft
                    )
                } else if display.requiresHumanApproval {
                    infoBlock(
                        label: cleaned(display.commitmentBoundaryTitle) ?? "Approval boundary",
                        value: "Your approval is required before anything moves outward on this path.",
                        valueStyle: .soft
                    )
                }

                HStack(spacing: 10) {
                    if display.prefersSecondHalfPreparedSend, !display.requiresHumanApproval {
                        boundaryPill(
                            value: "Ready to send",
                            label: "Send readiness"
                        )
                    } else if display.shouldShowHumanApprovalPill {
                        boundaryPill(
                            value: "Required",
                            label: "Human approval"
                        )
                    }

                    boundaryPill(
                        value: showsPersistedDraftPreview ? "Prepared" : "No draft",
                        label: "Draft"
                    )
                }
            }
        }
    }

    /// Body copy for the commitment card, excluding adapter placeholder strings.
    private func commitmentBoundaryDetailTextForCard() -> String? {
        if let r = cleaned(display.commitmentBoundaryReason),
           !SecretaryApprovalPanelDisplay.isPlaceholderCommitmentBoundaryText(r) {
            return r
        }
        let trimmedBoundary = display.boundary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBoundary.isEmpty,
           !SecretaryApprovalPanelDisplay.isPlaceholderCommitmentBoundaryText(trimmedBoundary) {
            return trimmedBoundary
        }
        return nil
    }

    // MARK: - Prepared Draft

    private var draftCard: some View {
        approvalDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                approvalPanelSectionHeader(
                    title: "Prepared Draft",
                    systemImage: "square.and.pencil"
                )

                if let subject = cleaned(display.draftSubject) {
                    Text(subject)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let body = cleaned(display.draftBody) {
                    Text(body)
                        .font(.system(size: 14))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Facts / Tradeoffs

    private var factFrameCard: some View {
        approvalDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                approvalPanelSectionHeader(
                    title: "Summary",
                    systemImage: "list.bullet.rectangle"
                )

                listSection(
                    title: "Key details",
                    systemImage: "checkmark.circle",
                    values: display.clarifiedFacts
                )

                listSection(
                    title: "What changed",
                    systemImage: "arrow.triangle.2.circlepath",
                    values: display.whatChanged
                )

                listSection(
                    title: "Unresolved issues",
                    systemImage: "questionmark.circle",
                    values: display.unresolvedIssues
                )

                listSection(
                    title: "Tradeoffs",
                    systemImage: "scale.3d",
                    values: display.tradeoffs
                )

                listSection(
                    title: "Approval reasons",
                    systemImage: "exclamationmark.shield",
                    values: display.approvalReasons
                )
            }
        }
    }

    // MARK: - Extra Sections

    private var extraSectionsCard: some View {
        approvalDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                approvalPanelSectionHeader(
                    title: "Additional Context",
                    systemImage: "square.stack.3d.up"
                )

                ForEach(display.extraSections.filter(\.isRenderable)) { section in
                    infoLineSection(
                        title: section.title,
                        systemImage: section.systemImage,
                        lines: section.lines
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private var actionCard: some View {
        approvalDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                approvalPanelSectionHeader(
                    title: "Choose what happens next",
                    systemImage: "checkmark.seal"
                )

                Text(actionExplanation)
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if display.canRunPrimaryAction || display.canRunRejectAction {
                    HStack(alignment: .center, spacing: 10) {
                        if display.canRunRejectAction {
                            approvalSecondaryButton(
                                title: display.secondaryTitle,
                                systemImage: "xmark",
                                disabled: isBusy
                            ) {
                                runAction(onReject)
                            }
                            .opacity(isBusy ? 0.55 : 1.0)
                            .frame(maxWidth: .infinity)
                        }

                        if display.canRunPrimaryAction {
                            approvalPrimaryButton(
                                title: isBusy ? "Working…" : display.resolvedPrimaryActionTitle,
                                systemImage: "checkmark",
                                disabled: isBusy,
                                isLoading: isBusy
                            ) {
                                runAction(onApprove)
                            }
                            .opacity(isBusy ? 0.72 : 1.0)
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    Text(
                        "Nothing here can be approved, rejected, or sent yet. Pull to refresh on the thread, or try again after sync."
                    )
                    .font(.system(size: 14.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let onOpenThread {
                    approvalSecondaryButton(
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

    private var actionExplanation: String {
        if !display.canRunPrimaryAction, !display.canRunRejectAction {
            return "Nothing on this sheet can be sent or approved right now. Close the sheet or open the full thread and try again after a refresh."
        }

        if display.prefersSecondHalfPreparedSend, display.approvalID == nil {
            return "Sending queues the prepared outbound message using the same path as inline Send."
        }

        if display.requiresHumanApproval {
            return "Approving allows the secretary to continue past this human boundary. Rejecting keeps the thread bounded and visible for revision."
        }

        if hasDecisionPacket {
            if display.canRunRejectAction {
                return "Approving accepts the current decision frame. Rejecting keeps the thread open for more clarification or revision."
            }
            return "Approving accepts the current decision frame."
        }

        if showsPersistedDraftPreview {
            if display.canRunRejectAction {
                return "Approving lets the prepared draft continue. Rejecting keeps the move local for later revision."
            }
            return "Approving lets the prepared draft continue."
        }

        if display.canRunRejectAction {
            return "Approving lets the prepared move continue. Rejecting keeps the thread bounded and visible for later revision."
        }
        return "Approving lets the prepared move continue."
    }

    // MARK: - Shared UI

    private enum InfoValueStyle {
        case normal
        case soft
    }

    private func infoBlock(
        label: String,
        value: String,
        valueStyle: InfoValueStyle = .normal
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(
                    valueStyle == .soft
                        ? SecretaryTheme.darkSecondaryText
                        : SecretaryTheme.darkPrimaryText.opacity(0.92)
                )
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func miniHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func listSection(
        title: String,
        systemImage: String,
        values: [String]
    ) -> some View {
        let cleanedValues = cleanedList(values)

        if !cleanedValues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                miniHeader(title: title, systemImage: systemImage)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(cleanedValues.enumerated()), id: \.offset) { _, value in
                        bulletLine(value)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func infoLineSection(
        title: String,
        systemImage: String,
        lines: [SecretaryPanelInfoLineDisplay]
    ) -> some View {
        let renderableLines = lines.filter(\.isRenderable).filter { line in
            SecretaryProjectionEngine.passesApprovalSheetBoundaryPublicCopy(line.value)
                && SecretaryProjectionEngine.passesApprovalSheetBoundaryPublicCopy(line.label)
        }

        if !renderableLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                miniHeader(title: title, systemImage: systemImage)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(renderableLines) { line in
                        infoBlock(label: line.label, value: line.value)
                    }
                }
            }
        }
    }

    private func bulletLine(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(SecretaryTheme.darkOrange.opacity(0.72))
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func boundaryPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func runAction(_ action: @escaping () async -> Void) {
        guard !isBusy else { return }

        Task {
            localSubmitting = true
            defer { localSubmitting = false }
            await action()
        }
    }

    // MARK: - Cleaning

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            output.append(trimmed)
        }

        return output
    }
}

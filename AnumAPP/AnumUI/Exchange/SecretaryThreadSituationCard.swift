import SwiftUI
import AnumCore

/// Read-only substrate surface: canonical `ExchangeThreadSituation` for skim / future agency.
struct SecretaryThreadSituationCard: View {
    let situation: ExchangeThreadSituation?

    private var subtitle: String {
        guard let s = situation else { return "" }
        let phase = trim(s.agencyPhaseTitle ?? s.phaseLabel)
        return "\(phase) · \(trim(s.stateSummary))"
    }

    var body: some View {
        UnifyDarkCard(cornerRadius: SecretaryTheme.Layout.radiusMedium) {
            VStack(alignment: .leading, spacing: 0) {
                if let situation {
                    briefingSectionHeader("Why this matters")
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(situation.title)
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineSpacing(1.25)
                    }

                    briefingDivider()
                        .padding(.vertical, 10)

                    briefingSectionHeader("What I know")
                        .padding(.bottom, 8)

                    let movement = SecretaryProjectionEngine.secretaryMovementLine(for: situation)
                    if !shouldOmitSituationMovementRow(situation: situation, subtitle: subtitle, movement: movement) {
                        labeledRow(
                            title: movement.title,
                            icon: movement.systemImage,
                            text: movement.detail
                        )
                    }

                    offerProfileLine(for: situation)

                    labeledRow(
                        title: "Delivery",
                        icon: "antenna.radiowaves.left.and.right",
                        text: trim(situation.deliveryLine)
                    )

                    trustAndRouteSection(situation)

                    DisclosureGroup {
                        whatIKnowPass2(for: situation)
                            .padding(.top, 6)
                    } label: {
                        Text("Supporting context")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                    }
                    .padding(.top, 6)
                    .tint(SecretaryTheme.darkOrange)

                    briefingDivider()
                        .padding(.vertical, 10)

                    briefingSectionHeader("Still needed")
                        .padding(.bottom, 8)

                    if situation.hasPendingApproval {
                        compactNotice(
                            text: "A prepared move is waiting on your judgment.",
                            accent: SecretaryTheme.darkOrange
                        )
                        .padding(.bottom, 8)
                    }

                    if !situation.missingFacts.isEmpty {
                        briefingSubheading("Missing facts")
                        briefingBulletList(situation.missingFacts, maxCount: 5)
                    }

                    if !situation.whatChanged.isEmpty {
                        briefingSubheading("What changed")
                        briefingBulletList(situation.whatChanged, maxCount: 5)
                    }

                    if !situation.decisionNeedLines.isEmpty {
                        briefingSubheading("Decision gaps")
                        briefingBulletList(situation.decisionNeedLines, maxCount: 5)
                    }

                    if !trim(situation.nextMoveLine).isEmpty {
                        labeledRow(
                            title: "Next step",
                            icon: "arrow.forward.circle",
                            text: trim(situation.nextMoveLine)
                        )
                    }

                    if !trim(situation.boundaryLine).isEmpty {
                        labeledRow(
                            title: "Private",
                            icon: "lock.shield",
                            text: trim(situation.boundaryLine)
                        )
                    }

                    autonomyHoldSection(situation)

                    briefingDivider()
                        .padding(.vertical, 10)

                    briefingSectionHeader("Suggested next steps")
                        .padding(.bottom, 8)

                    Group {
                        let suggestedQuestionLabels = situation.safeActionLabels.filter { label in
                            let lowered = label.lowercased()
                            return lowered.contains("suggested question") || lowered.hasPrefix("suggested:")
                        }
                        let affordanceLabels = filteredSafeActionLabels(situation.safeActionLabels)
                        let combinedSteps = Array(
                            (suggestedQuestionLabels + affordanceLabels)
                                .map { trim($0) }
                                .filter { !$0.isEmpty }
                                .prefix(8)
                        )
                        briefingBulletList(Array(combinedSteps), maxCount: 8)

                        agencySuggestedMovesSection(for: situation)

                        if !combinedSteps.isEmpty || !situation.agencySuggestions.isEmpty {
                            compactNotice(
                                text:
                                    "Reminders only — this card stays read-only. Use the thread actions above.",
                                accent: SecretaryTheme.darkSecondaryText.opacity(0.92)
                            )
                            .padding(.top, 8)
                        }
                    }

                    #if DEBUG
                    threadSituationDebugStrip(situation)
                    #endif
                } else {
                    Text("Loading situation…")
                        .font(.system(size: 14))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func briefingSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkOrange)
    }

    private func briefingSubheading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkMutedText)
            .padding(.top, 6)
    }

    private func briefingDivider() -> some View {
        Rectangle()
            .fill(SecretaryTheme.darkStroke.opacity(0.55))
            .frame(height: 1)
    }

    @ViewBuilder
    private func briefingBulletList(_ items: [String], maxCount: Int) -> some View {
        let rows = Array(items.prefix(maxCount))
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(rows, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("·")
                            .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.88))
                            .font(.system(size: 13, weight: .bold))
                        Text(line)
                            .font(.system(size: 13.5))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func offerProfileLine(for situation: ExchangeThreadSituation) -> some View {
        Group {
            if let offerTitle = situation.selectedOfferTitle {
                let extra = situation.selectedOfferSummary.map { ". \($0)" } ?? ""
                labeledRow(title: "Selected offer", icon: "tag", text: "\(offerTitle)\(extra)")
            }
            if let profileTitle = situation.selectedPublicProfileTitle {
                labeledRow(title: "Public surface", icon: "person.crop.circle", text: profileTitle)
            }
        }
    }

    private func labeledRow(title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.82))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .frame(width: 26, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.65), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func bulletSection(title: String, items: [String]) -> some View {
        Group {
            if !items.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.85))
                            Text(line)
                                .font(.system(size: 13.5))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    /// Commercial / answerability / grounding (read-only), under Supporting context.
    private func whatIKnowPass2(for situation: ExchangeThreadSituation) -> some View {
        let commercial = Array(situation.commercialSurfaceFactLines.prefix(4))
        let groundedDistinct = Array(
            distinctGroundingLines(
                situation.groundedFactLines,
                commercial: situation.commercialSurfaceFactLines
            )
            .prefix(5)
        )

        return Group {
            bulletSection(title: "Commercial surface", items: commercial)

            if let line = situation.answerabilityLine, !trim(line).isEmpty {
                labeledRow(title: "Answerability", icon: "checkmark.seal", text: trim(line))
            }

            bulletSection(title: "Grounding", items: groundedDistinct)
        }
    }

    private func distinctGroundingLines(_ grounded: [String], commercial: [String]) -> [String] {
        let commercialKeys = Set(commercial.map { normalizeSituationLine($0) })
        return grounded.filter { line in
            !commercialKeys.contains(normalizeSituationLine(line))
        }
    }

    private func normalizeSituationLine(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    #if DEBUG
    @ViewBuilder
    private func threadSituationDebugStrip(_ situation: ExchangeThreadSituation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SecretaryTheme.darkMutedText.opacity(0.65))

            if !situation.agencySuggestions.isEmpty {
                let kinds = situation.agencySuggestions.map(\.kind.rawValue).prefix(4)
                Text("Agency kinds: \(kinds.joined(separator: ", "))")
                    .debugFactLine()
            }

            if let first = situation.agencySuggestions.first, let r = first.reasons.first {
                Text("Agency note: \(r)")
                    .debugFactLine()
            }

            if let sample = situation.explanationLines.first {
                Text("Context: \(sample)")
                    .debugFactLine()
            }
        }
        .padding(.top, 6)
    }
    #endif

    private func agencySuggestionMetaLine(_ suggestion: ExchangeAgencySuggestion) -> String {
        var parts: [String] = ["Risk: \(suggestion.riskLevel)"]
        if suggestion.requiresUserApproval {
            parts.append("Needs your approval")
        }
        if suggestion.canRunAutonomously {
            parts.append("May continue safely on its own")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func agencySuggestedMovesSection(for situation: ExchangeThreadSituation) -> some View {
        if situation.agencySuggestions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Secretary reasoning")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.55)
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(situation.agencySuggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(suggestion.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(suggestion.summary)
                                .font(.system(size: 13.5))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(agencySuggestionMetaLine(suggestion))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkMutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: SecretaryTheme.Layout.radiusSmall, style: .continuous)
                                .fill(SecretaryTheme.darkSurface.opacity(0.92))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SecretaryTheme.Layout.radiusSmall, style: .continuous)
                                .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trustAndRouteSection(_ situation: ExchangeThreadSituation) -> some View {
        let title = trim(situation.trustPostureTitle ?? "")
        let summary = trim(situation.trustPostureSummary ?? "")
        let route = trim(situation.trustRouteLabel ?? "")

        if !title.isEmpty || !summary.isEmpty || !route.isEmpty || !situation.trustEvidenceLines.isEmpty || !situation.trustCautionLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                let mode = situation.trustIsLedgerBacked ? "Relationship ledger" : "Path context"
                labeledRow(title: "Trust & route", icon: "person.2", text: mode)

                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !route.isEmpty {
                    compactNotice(
                        text: "How this is connected: \(route)",
                        accent: SecretaryTheme.darkSecondaryText
                    )
                }

                bulletSection(title: "Evidence", items: Array(situation.trustEvidenceLines.prefix(2)))
                bulletSection(title: "Cautions", items: Array(situation.trustCautionLines.prefix(2)))
            }
        }
    }

    private func compactNotice(text: String, accent: Color) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func autonomyHoldSection(_ situation: ExchangeThreadSituation) -> some View {
        if let rawLine = situation.autonomyHoldLine {
            let line = trim(rawLine)
            if !line.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Secretary held back")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.55)
                        .foregroundStyle(SecretaryTheme.darkOrange)

                    Text(line)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)

                    if let rawReason = situation.autonomyHoldReason {
                        let reason = trim(rawReason)
                        if !reason.isEmpty {
                            Text(reason)
                                .font(.system(size: 13))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SecretaryTheme.Layout.radiusSmall, style: .continuous)
                        .fill(SecretaryTheme.darkOrangeSoft.opacity(0.42))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SecretaryTheme.Layout.radiusSmall, style: .continuous)
                        .stroke(SecretaryTheme.darkOrange.opacity(0.42), lineWidth: 1)
                )
            }
        }
    }

    private func trim(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops labels that mirror primary thread CTAs so this card stays explanatory, not a second action bar.
    private func filteredSafeActionLabels(_ labels: [String]) -> [String] {
        let blockedSubstrings = [
            "review", "approve", "recover", "answer", "activity", "open thread", "clarify",
            "compare", "reject", "dismiss", "send", "queue"
        ]
        return labels.filter { raw in
            let low = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if low.isEmpty { return false }
            return !blockedSubstrings.contains { low == $0 || low.hasPrefix($0 + " ") || low.hasPrefix($0 + ":") }
        }
    }

    /// Hides the movement row when it repeats the situation subtitle or state summary (trimmed).
    private func shouldOmitSituationMovementRow(
        situation: ExchangeThreadSituation,
        subtitle: String,
        movement: SecretaryProjectionEngine.SecretaryMovementLine
    ) -> Bool {
        let detail = trim(movement.detail)
        let sub = trim(subtitle)
        if detail.isEmpty { return false }
        if detail == sub { return true }
        let state = trim(situation.stateSummary)
        if !state.isEmpty, detail == state, sub.contains(state) { return true }
        return false
    }
}

private extension Text {
    func debugFactLine() -> some View {
        self
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(SecretaryTheme.darkSecondaryText.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }
}

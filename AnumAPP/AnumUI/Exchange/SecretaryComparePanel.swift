import SwiftUI
import AnumCore

struct SecretaryComparePanel: View {
    typealias Display = SecretaryComparePanelDisplay
    typealias Option = SecretaryCompareOptionDisplay

    let display: Display
    let onChooseOption: (Option) async -> Void
    let onSecondaryAction: () async -> Void
    let onOpenThread: ((ExchangeThread.ID?) -> Void)?

    @State private var isBusy = false
    @State private var expandedExtraSectionIDs = Set<SecretaryPanelSectionDisplay.ID>()
    @State private var expandedOptionIDs = Set<SecretaryCompareOptionDisplay.ID>()

    private var isMultiPathCompare: Bool {
        display.options.count > 1
    }

    init(
        display: Display,
        onChooseOption: @escaping (Option) async -> Void,
        onSecondaryAction: @escaping () async -> Void,
        onOpenThread: ((ExchangeThread.ID?) -> Void)? = nil
    ) {
        self.display = display
        self.onChooseOption = onChooseOption
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

            if display.options.count <= 1 {
                singlePathFallbackScroll
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard

                        if !isMultiPathCompare, showAggregateReviewSummary {
                            reviewSummaryCard
                        }

                        optionsCard

                        if hasExtraSections, !isMultiPathCompare {
                            extraSectionsCard
                        }

                        if !isMultiPathCompare {
                            actionCard
                        } else {
                            openThreadFooterCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Dark chrome

    @ViewBuilder
    private func compareDarkCard<Content: View>(
        cornerRadius: CGFloat = SecretaryTheme.Layout.radiusLarge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func comparePanelSectionHeader(title: String, systemImage: String) -> some View {
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

    private func compareAttentionChip(_ title: String) -> some View {
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

    private func compareMutedChip(_ title: String) -> some View {
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

    private func comparePrimaryButton(
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

    private func compareSecondaryButton(
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

    private var singlePathFallbackScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                compareDarkCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Path comparison needs at least two options. Open the thread to review this exchange.")
                            .font(.system(size: 15))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if let onOpenThread {
                            comparePrimaryButton(
                                title: "Open thread",
                                systemImage: "arrow.right",
                                disabled: false
                            ) {
                                onOpenThread(display.threadID)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var openThreadFooterCard: some View {
        Group {
            if let onOpenThread {
                compareDarkCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Need the full transcript, draft, or approval flow?")
                            .font(.system(size: 14))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        compareSecondaryButton(
                            title: "Open thread",
                            systemImage: "arrow.right",
                            disabled: false
                        ) {
                            onOpenThread(display.threadID)
                        }
                    }
                }
            }
        }
    }

    private var showAggregateReviewSummary: Bool {
        cleaned(display.recommendation) != nil ||
        cleaned(display.exposureSummary) != nil ||
        cleaned(display.trustSummary) != nil ||
        cleaned(display.readinessSummary) != nil ||
        !cleanedList(display.strengthReasons).isEmpty ||
        !cleanedList(display.weaknessReasons).isEmpty ||
        !cleanedList(display.missingFacts).isEmpty
    }

    private var headerStatusText: String {
        let count = display.options.count

        if count > 1 {
            return "\(count) paths found"
        }

        if count == 1 {
            return "1 path found"
        }

        return "No path ready"
    }

    private var hasExtraSections: Bool {
        display.extraSections.contains(where: \.isRenderable)
    }

    // MARK: - Header

    private var headerCard: some View {
        compareDarkCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Text("Compare paths")
                        .font(.system(size: 42, weight: .regular, design: .serif))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Spacer(minLength: 8)
                }

                HStack(alignment: .center, spacing: 10) {
                    Text(pathCountText)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        compareAttentionChip(cleaned(display.panelKind) ?? "Compare paths")

                        compareMutedChip(display.options.count > 1 ? "Choosing" : "Review")
                    }
                }
            }
        }
    }
    
    private var pulledOfferProfileLines: [SecretaryPanelInfoLineDisplay] {
        let preferredTitles = [
            "Pulled Offer / Profile",
            "Public Offer / Profile",
            "Matched Surface"
        ]

        for title in preferredTitles {
            if let section = display.extraSections.first(where: {
                $0.title.caseInsensitiveCompare(title) == .orderedSame
            }) {
                return section.lines.filter(\.isRenderable)
            }
        }

        return []
    }

    @ViewBuilder
    private func pulledOfferProfileSection(
        lines: [SecretaryPanelInfoLineDisplay]
    ) -> some View {
        let importantLabels = [
            "Offer",
            "Offer Summary",
            "Category",
            "Tags",
            "Regions",
            "Public Profile",
            "Profile Headline",
            "Profile Summary",
            "Open To",
            "Profile Regions"
        ]

        let filtered = lines.filter { line in
            importantLabels.contains(where: { $0.caseInsensitiveCompare(line.label) == .orderedSame })
        }

        let renderable = filtered.isEmpty ? lines : filtered

        VStack(alignment: .leading, spacing: 10) {
            miniHeader(
                title: "Pulled public surface",
                systemImage: "sparkles.rectangle.stack"
            )

            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(renderable.prefix(10)) { line in
                    compareLine(label: line.label, value: line.value)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
        )
    }

    private var pathCountText: String {
        let count = display.options.count
        if count <= 0 { return "No paths found" }
        return "\(count) path\(count == 1 ? "" : "s") found"
    }

    // MARK: - Review Summary

    private var reviewSummaryCard: some View {
        compareDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                comparePanelSectionHeader(
                    title: cleaned(display.panelKind) ?? "Compare paths",
                    systemImage: "rectangle.and.text.magnifyingglass"
                )

                if let recommendation = cleaned(display.recommendation) {
                    compareLine(label: "Recommendation", value: recommendation)
                }

                HStack(spacing: 10) {
                    reviewMetricPill(
                        value: cleaned(display.trustSummary) ?? "Unknown",
                        label: "Trust"
                    )

                    reviewMetricPill(
                        value: cleaned(display.readinessSummary) ?? "Unknown",
                        label: "Readiness"
                    )
                }

                if let exposure = cleaned(display.exposureSummary) {
                    compareLine(label: "Exposure / Boundary", value: exposure)
                }

                listSection(
                    title: "Strength reasons",
                    systemImage: "checkmark.circle",
                    values: display.strengthReasons
                )

                listSection(
                    title: "Weakness reasons",
                    systemImage: "exclamationmark.circle",
                    values: display.weaknessReasons
                )

                listSection(
                    title: "Missing facts",
                    systemImage: "questionmark.circle",
                    values: display.missingFacts
                )
            }
        }
    }

    // MARK: - Options

    private var optionsCard: some View {
        compareDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                comparePanelSectionHeader(
                    title: "Paths to compare",
                    systemImage: "rectangle.split.3x1"
                )

                if display.options.isEmpty {
                    Text("No comparable opportunity is available yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(display.options) { option in
                            optionCard(option)
                        }
                    }
                }
            }
        }
    }

    private func optionCard(_ option: Option) -> some View {
        let pulledLines = pulledOfferProfileLines
        let expanded = expandedOptionIDs.contains(option.id)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(option.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(option.subtitle)
                        .font(.system(size: 14.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if option.isPreferred, isMultiPathCompare {
                    compareAttentionChip("Checking first")
                }
            }

            if isMultiPathCompare {
                multiPathOptionDetail(option: option)

                if option.hasReviewDepth || !pulledLines.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expanded {
                                expandedOptionIDs.remove(option.id)
                            } else {
                                expandedOptionIDs.insert(option.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(expanded ? "Hide detail" : "More detail")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(SecretaryTheme.darkOrange)
                    }
                    .buttonStyle(.plain)
                }

                if expanded {
                    if !pulledLines.isEmpty {
                        pulledOfferProfileSection(lines: pulledLines)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        compareLine(label: "Recommendation", value: option.recommendationLine)

                        if let next = cleaned(option.nextMoveLine) {
                            compareLine(label: "Next move", value: next)
                        }
                    }

                    listSection(
                        title: "Weakness reasons",
                        systemImage: "exclamationmark.circle",
                        values: option.weaknessReasons,
                        compact: true,
                        maxItems: 6
                    )
                }
            } else if !pulledLines.isEmpty {
                pulledOfferProfileSection(lines: pulledLines)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    compareLine(label: "Trust", value: option.trustLine)
                    compareLine(label: "Exposure", value: option.exposureLine)
                    compareLine(label: "Recommendation", value: option.recommendationLine)

                    if let readiness = cleaned(option.readinessLine) {
                        compareLine(label: "Readiness", value: readiness)
                    }

                    if let boundary = cleaned(option.boundaryLine) {
                        compareLine(label: "Boundary", value: boundary)
                    }

                    if let next = cleaned(option.nextMoveLine) {
                        compareLine(label: "Next move", value: next)
                    }
                }

                listSection(
                    title: "Strength reasons",
                    systemImage: "checkmark.circle",
                    values: option.strengthReasons,
                    compact: true
                )

                listSection(
                    title: "Weakness reasons",
                    systemImage: "exclamationmark.circle",
                    values: option.weaknessReasons,
                    compact: true
                )

                listSection(
                    title: "Missing facts",
                    systemImage: "questionmark.circle",
                    values: option.missingFacts,
                    compact: true
                )
            }

            HStack {
                Spacer(minLength: 0)

                if option.isActionable {
                    comparePrimaryButton(
                        title: isBusy ? "Working…" : optionActionTitle(option),
                        systemImage: "checkmark",
                        disabled: isBusy,
                        isLoading: isBusy
                    ) {
                        guard !isBusy else { return }
                        runAction {
                            await onChooseOption(option)
                        }
                    }
                } else if let onOpenThread {
                    compareSecondaryButton(
                        title: "Inspect thread",
                        systemImage: "arrow.right",
                        disabled: false
                    ) {
                        onOpenThread(display.threadID)
                    }
                } else {
                    compareSecondaryButton(
                        title: "Inspect thread",
                        systemImage: "arrow.right",
                        disabled: true
                    ) {}
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    option.isPreferred && isMultiPathCompare
                        ? SecretaryTheme.darkOrange.opacity(0.42)
                        : SecretaryTheme.darkStroke.opacity(0.78),
                    lineWidth: option.isPreferred && isMultiPathCompare ? 1.5 : 1
                )
        )
    }

    @ViewBuilder
    private func multiPathOptionDetail(option: Option) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            compareLine(label: "Trust", value: option.trustLine)

            if let readiness = cleaned(option.readinessLine) {
                compareLine(label: "Readiness", value: readiness)
            }

            compareLine(label: "Exposure", value: option.exposureLine)
        }

        listSection(
            title: "Top strengths",
            systemImage: "checkmark.circle",
            values: Array(option.strengthReasons.prefix(3)),
            compact: true,
            maxItems: 3
        )

        listSection(
            title: "Top missing facts",
            systemImage: "questionmark.circle",
            values: Array(option.missingFacts.prefix(3)),
            compact: true,
            maxItems: 3
        )
    }

    private func optionActionTitle(_ option: Option) -> String {
        if isMultiPathCompare {
            return "Choose"
        }

        if let primary = cleaned(display.primaryTitle) {
            return primary
        }

        return "Add to trusted"
    }

    // MARK: - Extra Sections

    private var extraSectionsCard: some View {
        compareDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                comparePanelSectionHeader(
                    title: "Additional Review Context",
                    systemImage: "square.stack.3d.up"
                )

                Text("Extra signals are available, but hidden by default so the review stays readable.")
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(display.extraSections.filter(\.isRenderable)) { section in
                    collapsibleInfoLineSection(section)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionCard: some View {
        compareDarkCard {
            VStack(alignment: .leading, spacing: 14) {
                comparePanelSectionHeader(
                    title: "Other moves",
                    systemImage: "arrow.triangle.branch"
                )

                Text(actionExplanation)
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    compareSecondaryButton(
                        title: isBusy ? "Working…" : display.secondaryTitle,
                        systemImage: "magnifyingglass",
                        disabled: isBusy,
                        isLoading: isBusy
                    ) {
                        runAction {
                            await onSecondaryAction()
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if let onOpenThread {
                        comparePrimaryButton(
                            title: display.primaryTitle,
                            systemImage: "arrow.right",
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
    }

    private var actionExplanation: String {
        if isMultiPathCompare {
            return "Compare the visible paths by fit, trust, readiness, exposure, and missing facts before choosing which one should move next."
        }

        return "Review trust, readiness, exposure, and boundary detail on this sheet, or open the thread for the full transcript and draft."
    }

    // MARK: - Shared UI

    private func compareLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
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
        values: [String],
        compact: Bool = false,
        maxItems: Int? = nil
    ) -> some View {
        let cleanedValues = cleanedList(values)

        if !cleanedValues.isEmpty {
            let defaultCap = compact ? 4 : 6
            let cap = maxItems ?? defaultCap

            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                miniHeader(title: title, systemImage: systemImage)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(cleanedValues.prefix(cap).enumerated()), id: \.offset) { _, value in
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
        let renderableLines = lines.filter(\.isRenderable)

        if !renderableLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                miniHeader(title: title, systemImage: systemImage)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(renderableLines) { line in
                        compareLine(label: line.label, value: line.value)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func collapsibleInfoLineSection(
        _ section: SecretaryPanelSectionDisplay
    ) -> some View {
        let renderableLines = section.lines.filter(\.isRenderable)
        let isExpanded = expandedExtraSectionIDs.contains(section.id)
        let visibleLines = isExpanded ? renderableLines : Array(renderableLines.prefix(3))
        let hiddenCount = max(renderableLines.count - visibleLines.count, 0)

        if !renderableLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded {
                            expandedExtraSectionIDs.remove(section.id)
                        } else {
                            expandedExtraSectionIDs.insert(section.id)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange)

                        Text(section.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))

                        Spacer(minLength: 0)

                        if hiddenCount > 0 && !isExpanded {
                            Text("+\(hiddenCount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleLines) { line in
                        compareLine(label: line.label, value: line.value)
                    }
                }

                if hiddenCount > 0 && !isExpanded {
                    Text("\(hiddenCount) more signal\(hiddenCount == 1 ? "" : "s") hidden")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
            )
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

    private func reviewMetricPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

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
            isBusy = true
            defer { isBusy = false }
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

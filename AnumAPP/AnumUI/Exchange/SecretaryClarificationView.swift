import SwiftUI
import AnumCore

struct SecretaryClarificationView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    let threadID: ExchangeThread.ID
    let onBack: () -> Void
    let onSubmitted: (() -> Void)?

    @State private var detail: ExchangeModels.ThreadDetail?
    @State private var answerText = ""
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var loadTask: Task<Void, Never>?
    @FocusState private var isAnswerFocused: Bool

    init(
        threadID: ExchangeThread.ID,
        onBack: @escaping () -> Void,
        onSubmitted: (() -> Void)? = nil
    ) {
        self.threadID = threadID
        self.onBack = onBack
        self.onSubmitted = onSubmitted
    }

    // MARK: - Dark chrome

    @ViewBuilder
    private func clarificationDarkCard<Content: View>(
        cornerRadius: CGFloat = SecretaryTheme.Layout.radiusLarge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func clarificationSectionHeader(title: String, systemImage: String) -> some View {
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

    private func clarificationThreadStatusPill(for detail: ExchangeModels.ThreadDetail) -> some View {
        let title = SecretaryProjectionEngine.visibleThreadStatus(for: detail).label
        let attention = clarificationStatusWantsAttention(title)

        return Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(attention ? SecretaryTheme.darkOrange : SecretaryTheme.darkSecondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        attention
                            ? SecretaryTheme.darkOrangeSoft.opacity(0.48)
                            : SecretaryTheme.darkSurfaceStrong.opacity(0.55)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        attention
                            ? SecretaryTheme.darkOrange.opacity(0.38)
                            : SecretaryTheme.darkStroke.opacity(0.72),
                        lineWidth: 1
                    )
            )
    }

    private func clarificationStatusWantsAttention(_ title: String) -> Bool {
        let lower = title.lowercased()
        if lower.contains("clarif") { return true }
        if lower.contains("need") && lower.contains("you") { return true }
        if lower.contains("input") { return true }
        if lower.contains("approval") || lower.contains("review") { return true }
        if lower.contains("recover") || lower.contains("fail") || lower.contains("block") { return true }
        return false
    }

    private func clarificationMetricStrip(for detail: ExchangeModels.ThreadDetail) -> some View {
        let items: [(String, String)] = [
            (SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "State"),
            ("Local", "Boundary"),
            (modeShort(detail.thread.mode), "Mode"),
            (SecretaryProjectionEngine.selectedCounterpartyName(for: detail) ?? "Open", "Path")
        ]

        return HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Text(item.0)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(item.1)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 9)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.5))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
                )
            }
        }
    }

    private func clarificationPrimaryButton(
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

    private func clarificationSecondaryButton(
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading && detail == nil {
                    UnifyDarkLoadingView(
                        title: "Loading clarification",
                        subtitle: "Bringing the missing detail into view."
                    )
                } else if let errorText, detail == nil {
                    UnifyDarkStateCard(
                        title: "Could not load clarification",
                        message: errorText,
                        systemImage: "exclamationmark.triangle",
                        minHeight: 180
                    )
                } else if let detail {
                    hero(detail)
                    questionCard(detail)
                    answerComposer(detail)
                    contextCard(detail)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await load(showSpinner: true)
        }
        .task(id: threadID) {
            scheduleLoad(delayNanoseconds: 0)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func hero(_ detail: ExchangeModels.ThreadDetail) -> some View {
        clarificationDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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

                    Spacer(minLength: 8)

                    clarificationThreadStatusPill(for: detail)
                }

                Text(SecretaryProjectionEngine.threadTitle(detail))
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("The secretary is paused behind one missing detail. Nothing external should move until you answer.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                clarificationMetricStrip(for: detail)
            }
        }
    }

    private func questionCard(_ detail: ExchangeModels.ThreadDetail) -> some View {
        clarificationDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                clarificationSectionHeader(
                    title: "Clarification Needed",
                    systemImage: "questionmark.circle"
                )

                labeledBlock(
                    "Question",
                    value: SecretaryProjectionEngine.clarificationQuestion(detail)
                )

                let why = clarificationReason(detail)
                if !why.isEmpty {
                    labeledBlock("Why this is needed", value: why)
                }

                labeledBlock(
                    "Boundary",
                    value: SecretaryProjectionEngine.threadBoundaryLine(detail)
                )

                labeledBlock(
                    "What happens after",
                    value: "Your answer becomes a new interpretation pass, but the thread should continue straight into search rather than stopping here again."
                )
            }
        }
    }

    private func answerComposer(_ detail: ExchangeModels.ThreadDetail) -> some View {
        clarificationDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                clarificationSectionHeader(
                    title: "Your Answer",
                    systemImage: "square.and.pencil"
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    isAnswerFocused
                                        ? SecretaryTheme.darkOrange.opacity(0.42)
                                        : SecretaryTheme.darkStroke.opacity(0.85),
                                    lineWidth: isAnswerFocused ? 1.5 : 1
                                )
                        )

                    if trimmedAnswer.isEmpty {
                        Text("Type the missing detail here…")
                            .font(.system(size: 15))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    }

                    TextEditor(text: $answerText)
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .tint(SecretaryTheme.darkOrange)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 140)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .focused($isAnswerFocused)
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    clarificationPrimaryButton(
                        title: isSubmitting ? "Submitting…" : "Submit Answer",
                        systemImage: "arrow.up.circle.fill",
                        disabled: isSubmitting || trimmedAnswer.isEmpty,
                        isLoading: isSubmitting
                    ) {
                        Task { await submitClarification(detail) }
                    }

                    clarificationSecondaryButton(
                        title: "Cancel",
                        systemImage: "xmark",
                        disabled: isSubmitting
                    ) {
                        guard !isSubmitting else { return }
                        onBack()
                    }
                }
            }
        }
    }

    private func contextCard(_ detail: ExchangeModels.ThreadDetail) -> some View {
        clarificationDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                clarificationSectionHeader(
                    title: "Context",
                    systemImage: "shippingbox"
                )

                labeledBlock(
                    "Thread summary",
                    value: clean(detail.summary).isEmpty
                        ? "No additional summary is available yet."
                        : clean(detail.summary)
                )

                labeledBlock(
                    "Current route",
                    value: SecretaryProjectionEngine.selectedCounterpartyName(for: detail) ?? "No route is selected yet."
                )

                if !detail.counterparties.isEmpty {
                    let visiblePaths = detail.counterparties
                        .map(\.bestDisplayLine)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .prefix(3)
                        .joined(separator: " · ")

                    if !visiblePaths.isEmpty {
                        labeledBlock("Visible paths", value: visiblePaths)
                    }
                }
            }
        }
    }

    @MainActor
    private func submitClarification(_ detail: ExchangeModels.ThreadDetail) async {
        guard !isSubmitting else { return }
        guard !trimmedAnswer.isEmpty else {
            errorText = "Please enter the missing detail before submitting."
            return
        }

        loadTask?.cancel()
        isSubmitting = true
        errorText = nil
        defer { isSubmitting = false }

        do {
            _ = try await services.exchangeFacade.answerClarification(
                threadID: detail.thread.id,
                answer: trimmedAnswer
            )

            onSubmitted?()
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func scheduleLoad(
        delayNanoseconds: UInt64 = 150_000_000
    ) {
        loadTask?.cancel()

        loadTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard !Task.isCancelled else { return }
            await load(showSpinner: false)
        }
    }

    @MainActor
    private func load(showSpinner: Bool = true) async {
        if showSpinner || detail == nil {
            isLoading = true
        }

        errorText = nil

        do {
            let loadedDetail = try await services.exchangeFacade.getThread(threadID: threadID)

            guard !Task.isCancelled else { return }

            detail = loadedDetail
        } catch {
            guard !Task.isCancelled else { return }
            errorText = error.localizedDescription
        }

        isLoading = false
    }

    private var trimmedAnswer: String {
        answerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clarificationReason(_ detail: ExchangeModels.ThreadDetail) -> String {
        if let stateSummary = detail.thread.visibleSummary.map(clean), !stateSummary.isEmpty {
            return stateSummary
        }

        if let interpreted = detail.interpretationSummary.map(clean), !interpreted.isEmpty {
            return interpreted
        }

        if !clean(detail.summary).isEmpty {
            return clean(detail.summary)
        }

        return "The request is still missing a key detail needed to proceed."
    }

    private func modeShort(_ mode: ExchangeMode) -> String {
        switch mode {
        case .transactional: return "Txn"
        case .cooperative: return "Co-op"
        case .relational: return "Rel"
        @unknown default: return "Mode"
        }
    }

    private func labeledBlock(_ label: String, value: String) -> some View {
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

    private func clean(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

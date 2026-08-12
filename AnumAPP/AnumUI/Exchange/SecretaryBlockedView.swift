import SwiftUI
import AnumCore

struct SecretaryBlockedView: View {
    @EnvironmentObject private var services: AppServices

    let isTabActive: Bool

    let onOpenThread: (ExchangeThread.ID) -> Void
    let onOpenRecoveryPanel: (SecretaryRecoveryPanel.Display) -> Void

    private struct RecoveryRow: Identifiable {
        let item: ExchangeModels.InboxItem
        let title: String
        let badge: String
        let whatHappened: String
        let whatDidNotHappen: String
        let externalEffect: String
        let bestNextMove: String
        let relativeTimeText: String
        let display: SecretaryRecoveryPanel.Display
        let isBlocked: Bool
        let isDeclined: Bool
        let isStalled: Bool

        var id: ExchangeThread.ID { item.threadID }
        var updatedAt: Date { item.updatedAt }
    }

    private struct RecoveryProjection {
        let rows: [RecoveryRow]
        let blockedCount: Int
        let declinedCount: Int
        let stalledCount: Int

        static let empty = RecoveryProjection(
            rows: [],
            blockedCount: 0,
            declinedCount: 0,
            stalledCount: 0
        )
    }

    @State private var items: [ExchangeModels.InboxItem] = []
    @State private var pendingApprovals: [ExchangeModels.PendingApproval] = []
    @State private var projection = RecoveryProjection.empty
    @State private var appliedDeskSnapshotGeneration: UInt64 = 0
    @State private var deskSnapshotApplyTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 18) {
                    heroCard

                    if isLoading && projection.rows.isEmpty {
                        UnifyDarkLoadingView(
                            title: "Loading recovery",
                            subtitle: "Collecting blocked, failed, and stalled work."
                        )
                    } else if let errorText, projection.rows.isEmpty {
                        UnifyDarkStateCard(
                            title: "Could not load recovery",
                            message: errorText,
                            systemImage: "exclamationmark.triangle",
                            minHeight: 170
                        )
                    } else if projection.rows.isEmpty {
                        UnifyDarkStateCard(
                            title: "Nothing needs recovery",
                            message: "When work stalls, fails, or needs visible recovery, it will appear here.",
                            systemImage: "checkmark.shield",
                            minHeight: 170
                        )
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(projection.rows) { row in
                                recoveryCard(row)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .refreshable {
            services.refreshSecretaryDeskSnapshot(reason: "blockedPullToRefresh", force: true)
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            scheduleApplyDeskSnapshot(generation: services.secretaryDeskSnapshot?.generation)
        }
        .onChange(of: isTabActive) { _, active in
            guard active else { return }
            scheduleApplyDeskSnapshot(generation: services.secretaryDeskSnapshot?.generation)
        }
        .onChange(of: services.secretaryDeskSnapshot?.generation) { _, generation in
            guard isTabActive else { return }
            scheduleApplyDeskSnapshot(generation: generation)
        }
        .onDisappear {
            deskSnapshotApplyTask?.cancel()
            deskSnapshotApplyTask = nil
        }
    }

    // MARK: - Dark chrome

    @ViewBuilder
    private func blockedDarkCard<Content: View>(
        cornerRadius: CGFloat = SecretaryTheme.Layout.radiusLarge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func blockedAttentionChip(_ title: String) -> some View {
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

    private func blockedMutedChip(_ title: String) -> some View {
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

    private func blockedRecoveryBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkOrange)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SecretaryTheme.darkOrangeSoft.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SecretaryTheme.darkOrange.opacity(0.35), lineWidth: 1)
            )
    }

    private func blockedPrimaryButton(
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
                    .minimumScaleFactor(0.82)
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

    private func blockedSecondaryButton(
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
                    .minimumScaleFactor(0.82)
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

    private var blockedMetricItems: [(value: String, title: String)] {
        [
            ("\(projection.rows.count)", "Recovery"),
            ("\(projection.blockedCount)", "Blocked"),
            ("\(projection.declinedCount)", "Declined"),
            ("\(projection.stalledCount)", "Stalled")
        ]
    }

    private var blockedMetricStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(blockedMetricItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Text(item.value)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Text(item.title)
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

    private var heroCard: some View {
        blockedDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)

                    Text("Recovery")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))

                    Spacer(minLength: 0)

                    if projection.rows.isEmpty {
                        blockedMutedChip("Quiet")
                    } else {
                        blockedAttentionChip("Visible")
                    }
                }

                Text("Failure should be legible.")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("This space should clarify what happened, what did not happen, what changed externally, and what the best recovery move is.")
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                blockedMetricStrip
            }
        }
    }

    private func recoveryCard(_ row: RecoveryRow) -> some View {
        blockedDarkCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    blockedRecoveryBadge(row.badge)

                    Spacer(minLength: 8)

                    Text(row.relativeTimeText)
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                Text(row.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    infoBlock(label: "What happened", value: row.whatHappened)
                    infoBlock(label: "What did not happen", value: row.whatDidNotHappen)
                    infoBlock(label: "External effect", value: row.externalEffect)
                    infoBlock(label: "Best next move", value: row.bestNextMove)
                }

                HStack(spacing: 10) {
                    blockedPrimaryButton(
                        title: "Recover",
                        systemImage: "arrow.clockwise"
                    ) {
                        onOpenRecoveryPanel(row.display)
                    }

                    blockedSecondaryButton(
                        title: "Thread",
                        systemImage: "arrow.right"
                    ) {
                        onOpenThread(row.id)
                    }

                    blockedSecondaryButton(
                        title: "Dismiss",
                        systemImage: "xmark"
                    ) {
                        Task {
                            try? await services.exchangeFacade.archiveThread(id: row.id)
                            services.refreshSecretaryDeskSnapshot(reason: "blockedArchive", force: true)
                        }
                    }
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

    @MainActor
    private func scheduleApplyDeskSnapshot(generation: UInt64?) {
        guard isTabActive else {
            #if DEBUG
            print(
                "[RetainedTabLoadGate] view=Blocked active=false skip=applyDeskSnapshot " +
                "reason=hiddenRetainedMount generation=\(generation ?? 0)"
            )
            #endif
            return
        }

        guard let generation else {
            if projection.rows.isEmpty {
                isLoading = true
            }
            return
        }

        #if DEBUG
        print(
            "[RetainedTabLoadGate] view=Blocked active=true source=snapshot " +
            "generation=\(generation)"
        )
        #endif

        deskSnapshotApplyTask?.cancel()
        deskSnapshotApplyTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard let snapshot = services.secretaryDeskSnapshot,
                  snapshot.generation == generation else { return }
            applyDeskSnapshot(snapshot)
        }
    }

    @MainActor
    private func applyDeskSnapshot(_ snapshot: SecretaryDeskSnapshot) {
        guard snapshot.generation != appliedDeskSnapshotGeneration else { return }

        items = snapshot.threadItems
        pendingApprovals = snapshot.pendingApprovals
        projection = buildProjection(
            items: snapshot.threadItems,
            pendingApprovals: snapshot.pendingApprovals
        )
        appliedDeskSnapshotGeneration = snapshot.generation
        errorText = nil
        isLoading = false
    }

    private func buildProjection(
        items: [ExchangeModels.InboxItem],
        pendingApprovals: [ExchangeModels.PendingApproval]
    ) -> RecoveryProjection {
        let pendingApprovalThreadIDs = Set(pendingApprovals.map(\.threadID))

        let rows = items
            .filter {
                SecretaryProjectionEngine.bucket(
                    for: $0,
                    pendingApprovalThreadIDs: pendingApprovalThreadIDs
                ) == .recovery
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.threadID.uuidString < $1.threadID.uuidString
            }
            .map { item in
                RecoveryRow(
                    item: item,
                    title: SecretaryProjectionEngine.displayTitle(for: item),
                    badge: SecretaryProjectionEngine.recoveryBadge(for: item),
                    whatHappened: SecretaryProjectionEngine.failureWhatHappened(for: item),
                    whatDidNotHappen: SecretaryProjectionEngine.failureWhatDidNotHappen(for: item),
                    externalEffect: SecretaryProjectionEngine.failureExternalEffect(for: item),
                    bestNextMove: SecretaryProjectionEngine.failureNextMove(for: item),
                    relativeTimeText: SecretaryRelativeTime.string(from: item.updatedAt),
                    display: SecretaryProjectionEngine.recoveryDisplay(for: item),
                    isBlocked: SecretaryProjectionEngine.isBlockedRecovery(item),
                    isDeclined: SecretaryProjectionEngine.isDeclinedRecovery(item),
                    isStalled: SecretaryProjectionEngine.isStalledRecovery(item)
                )
            }

        return RecoveryProjection(
            rows: rows,
            blockedCount: rows.filter(\.isBlocked).count,
            declinedCount: rows.filter(\.isDeclined).count,
            stalledCount: rows.filter(\.isStalled).count
        )
    }
}

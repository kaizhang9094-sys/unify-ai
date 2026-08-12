import SwiftUI

struct SecretaryExecutionStageDisplay: Identifiable, Hashable {
    enum Status: Hashable {
        case pending
        case active
        case complete
        case failed
    }

    let id: UUID
    let title: String
    let subtitle: String
    let status: Status

    init(
        id: UUID? = nil,
        title: String,
        subtitle: String,
        status: Status
    ) {
        if let id {
            self.id = id
        } else {
            self.id = SecretaryExecutionStageDisplay.stableID(
                title: title,
                subtitle: subtitle,
                status: status
            )
        }

        self.title = title
        self.subtitle = subtitle
        self.status = status
    }

    private static func stableID(
        title: String,
        subtitle: String,
        status: Status
    ) -> UUID {
        let raw = "\(title)|\(subtitle)|\(status)"
        var hash = UInt64(1469598103934665603)

        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }

        let hex = String(format: "%016llx", hash)
        let uuidString = "00000000-0000-0000-\(String(hex.prefix(4)))-\(String(hex.suffix(12)))"

        return UUID(uuidString: uuidString) ?? UUID()
    }
}

struct SecretaryExecutionDisplay: Hashable {
    let title: String
    let summary: String
    let badgeTitle: String
    let boundary: String
    let nextMove: String
    let primaryActionTitle: String
    let primarySystemImage: String
    let secondaryActionTitle: String
    let secondarySystemImage: String
    let currentStageTitle: String
    let currentStageSubtitle: String
    let stages: [SecretaryExecutionStageDisplay]

    init(
        title: String,
        summary: String,
        badgeTitle: String = "Working",
        boundary: String,
        nextMove: String,
        primaryActionTitle: String = "Open",
        primarySystemImage: String = "arrow.right",
        secondaryActionTitle: String = "Details",
        secondarySystemImage: String = "list.bullet.rectangle",
        currentStageTitle: String,
        currentStageSubtitle: String,
        stages: [SecretaryExecutionStageDisplay]
    ) {
        self.title = title
        self.summary = summary
        self.badgeTitle = badgeTitle
        self.boundary = boundary
        self.nextMove = nextMove
        self.primaryActionTitle = primaryActionTitle
        self.primarySystemImage = primarySystemImage
        self.secondaryActionTitle = secondaryActionTitle
        self.secondarySystemImage = secondarySystemImage
        self.currentStageTitle = currentStageTitle
        self.currentStageSubtitle = currentStageSubtitle
        self.stages = stages
    }
}

struct SecretaryExecutionStageView: View {
    let display: SecretaryExecutionDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            currentStageCard

            if !display.stages.isEmpty {
                stageRail
            }
        }
    }

    private var currentStageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecretaryThreadStateBadge(title: "Current stage")

            Text(display.currentStageTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(display.currentStageSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(SecretaryTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SecretaryTheme.secondaryFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SecretaryTheme.stroke, lineWidth: 1)
        )
    }

    private var stageRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.ink.opacity(0.72))

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(display.stages) { stage in
                    stageRow(
                        stage: stage,
                        isLast: stage.id == display.stages.last?.id
                    )
                }
            }
            .padding(.vertical, 4)
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

    private func stageRow(
        stage: SecretaryExecutionStageDisplay,
        isLast: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                stageMarker(for: stage.status)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(stage.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        SecretaryMiniStagePill(
                            title: statusTitle(for: stage.status),
                            style: chipStyle(for: stage.status)
                        )
                    }

                    Text(stage.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(SecretaryTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !isLast {
                Divider()
                    .overlay(SecretaryTheme.stroke.opacity(0.72))
                    .padding(.leading, 30)
            }
        }
    }

    @ViewBuilder
    private func stageMarker(for status: SecretaryExecutionStageDisplay.Status) -> some View {
        switch status {
        case .complete:
            Circle()
                .fill(SecretaryTheme.gold.opacity(0.85))
                .frame(width: 12, height: 12)

        case .active:
            Circle()
                .fill(SecretaryTheme.gold)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(SecretaryTheme.gold.opacity(0.28), lineWidth: 5)
                        .frame(width: 22, height: 22)
                )

        case .pending:
            Circle()
                .stroke(SecretaryTheme.stroke.opacity(0.95), lineWidth: 2)
                .frame(width: 12, height: 12)

        case .failed:
            Circle()
                .fill(SecretaryTheme.ink.opacity(0.70))
                .frame(width: 12, height: 12)
        }
    }

    private func statusTitle(for status: SecretaryExecutionStageDisplay.Status) -> String {
        switch status {
        case .pending:
            return "Pending"
        case .active:
            return "Active"
        case .complete:
            return "Done"
        case .failed:
            return "Failed"
        }
    }

    private func chipStyle(for status: SecretaryExecutionStageDisplay.Status) -> SecretaryStateChip.Style {
        switch status {
        case .pending:
            return .neutral
        case .active:
            return .active
        case .complete:
            return .neutral
        case .failed:
            return .blocked
        }
    }
}

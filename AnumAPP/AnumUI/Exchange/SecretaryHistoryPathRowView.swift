import SwiftUI
import AnumCore

/// Compact History child path row under an umbrella search workbench.
struct SecretaryHistoryPathRowView: View {
    let child: ExchangeModels.CoordinationChildThreadSummary
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Result path")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.9))
                            .textCase(.uppercase)

                        Text(SecretaryProjectionEngine.historyPathDisplayTitle(for: child))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if let updated = child.updatedAt {
                            Text(SecretaryRelativeTime.string(from: updated))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkMutedText)
                        }
                    }

                    Text(SecretaryProjectionEngine.historyPathStatusLabel(for: child))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SecretaryTheme.darkSurface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

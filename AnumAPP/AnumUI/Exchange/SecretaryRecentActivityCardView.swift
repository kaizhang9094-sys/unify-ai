import SwiftUI

struct SecretaryRecentActivityCardView: View {
    let card: SecretaryRecentActivityCardProjection
    let onOpenThread: () -> Void

    var body: some View {
        UnifyDarkCard(cornerRadius: 22, strokeOpacity: 0.9) {
            VStack(alignment: .leading, spacing: 12) {
                Text(card.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(2)

                if let status = card.statusLabel, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                }

                Text(card.summary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenThread) {
                    Text(card.ctaTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

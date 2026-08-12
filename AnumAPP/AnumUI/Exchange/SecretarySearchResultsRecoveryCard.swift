import SwiftUI

/// Compact no-match recovery surface only — not used for matched result cards.
struct SecretarySearchResultsRecoveryCard: View {
    private let suggestionChips = ["Widen area", "Refine search", "Try nearby"]

    var body: some View {
        UnifyDarkCard(cornerRadius: 20, strokeOpacity: 0.88) {
            VStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)

                VStack(spacing: 4) {
                    Text("No strong match found")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .multilineTextAlignment(.center)

                    Text("Try widening the area or refining the request.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    ForEach(suggestionChips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(SecretaryTheme.white.opacity(0.07))
                            }
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(SecretaryTheme.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
    }
}

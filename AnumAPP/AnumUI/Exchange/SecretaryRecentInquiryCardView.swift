import SwiftUI

struct SecretaryRecentInquiryCardView: View {
    let card: SecretaryRecentInquiryCardProjection
    let onOpenThread: () -> Void

    var body: some View {
        UnifyDarkCard(cornerRadius: 22, strokeOpacity: 0.9) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    leadAvatar

                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.senderTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(2)

                        Text(card.statusLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SecretaryTheme.darkOrange.opacity(0.22))
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(card.summary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.factLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(card.factLines, id: \.self) { fact in
                            Label(fact, systemImage: "checkmark.circle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkMutedText)
                                .lineLimit(2)
                        }
                    }
                }

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

    @ViewBuilder
    private var leadAvatar: some View {
        let size: CGFloat = 52
        if let urlString = card.primaryImageURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    avatarFallback
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            avatarFallback
                .frame(width: size, height: size)
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(SecretaryTheme.white.opacity(0.08))
            Text(initials(from: card.senderTitle))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.88))
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }
        let joined = letters.joined()
        return joined.isEmpty ? "?" : joined.uppercased()
    }
}

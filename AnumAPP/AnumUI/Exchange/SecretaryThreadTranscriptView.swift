import SwiftUI
import AnumCore

private enum SecretaryThreadTranscriptLayout {
    static let transcriptBodyMaxHeight: CGFloat = 380
}

/// Local conversation history derived from drafts and turns (not a transport log).
struct SecretaryThreadTranscriptView<TrailingAction: View>: View {
    let detail: ExchangeModels.ThreadDetail
    let trailingAction: TrailingAction?

    init(
        detail: ExchangeModels.ThreadDetail,
        trailingAction: TrailingAction? = nil
    ) {
        self.detail = detail
        self.trailingAction = trailingAction
    }

    var body: some View {
        let resolvedEntries = ExchangeModels.ThreadTranscriptBuilder.build(
            from: detail,
            secondHalfDisplay: detail.secondHalfDisplay
        )

        UnifyDarkCard(cornerRadius: SecretaryTheme.Layout.radiusLarge) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if resolvedEntries.isEmpty {
                    Text("No conversation messages yet. The thread is waiting for the next reply.")
                        .font(.system(size: 14.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(resolvedEntries.enumerated()), id: \.element.id) { index, entry in
                                transcriptRow(entry, isLatest: index == 0)

                                if index < resolvedEntries.count - 1 {
                                    Divider()
                                        .overlay(SecretaryTheme.darkStroke.opacity(0.45))
                                        .padding(.leading, 34)
                                        .padding(.vertical, 10)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: SecretaryThreadTranscriptLayout.transcriptBodyMaxHeight, alignment: .top)
                    .clipped()
                }

                if let trailingAction {
                    HStack {
                        Spacer(minLength: 0)
                        trailingAction
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .frame(width: 22, alignment: .leading)

            Text("Conversation")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transcriptRow(
        _ entry: ExchangeModels.ThreadTranscriptEntry,
        isLatest: Bool
    ) -> some View {
        let visibleTitle = sanitizeConversationVisibleText(entry.title)
        let visibleStatusChip = entry.statusChip.map(sanitizeConversationVisibleText)
        let visibleBody = sanitizeConversationVisibleText(entry.bodyPreview)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: transcriptIcon(for: entry))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isLatest ? SecretaryTheme.darkOrange : SecretaryTheme.darkMutedText)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(visibleTitle)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if isLatest {
                        Text("Latest")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(formattedTime(entry.timestamp))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .lineLimit(1)
                }

                if let chip = visibleStatusChip?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                    Text(chip)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                if !visibleBody.isEmpty {
                    Text(visibleBody)
                        .font(.system(size: 14.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineSpacing(1.35)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transcriptIcon(for entry: ExchangeModels.ThreadTranscriptEntry) -> String {
        let title = entry.title.lowercased()
        let chip = (entry.statusChip ?? "").lowercased()

        if title.contains("you") || chip.contains("sent") {
            return "arrow.up.right"
        }

        if chip.contains("draft") || title.contains("draft") {
            return "doc.text"
        }

        if chip.contains("reply") || title.contains("reply") {
            return "arrow.down.left"
        }

        return "message"
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func sanitizeConversationVisibleText(_ raw: String) -> String {
        var line = collapseConversationVisibleWhitespace(
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !line.isEmpty else { return "" }

        let leadingPrefixPatterns = [
            "(?i)^response\\s*[-–—]\\s*response\\s+received\\s*[-–—:]\\s*",
            "(?i)^response\\s+received\\s*[-–—:]\\s*",
            "(?i)^response\\s*:\\s*",
            "(?i)^response\\s*[-–—]\\s*"
        ]

        var changed = true
        while changed {
            changed = false
            for pattern in leadingPrefixPatterns {
                let stripped = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                if stripped != line {
                    line = collapseConversationVisibleWhitespace(stripped)
                    changed = true
                    break
                }
            }
        }

        if line.isEmpty {
            return "New inquiry received"
        }

        let lower = line.lowercased()
        let standaloneScaffold: Set<String> = [
            "response received",
            "counterparty is asking for additional information",
            "counterparty is asking for additional information.",
            "response - response received",
            "response — response received"
        ]
        if standaloneScaffold.contains(lower) {
            return "New inquiry received"
        }

        return line
    }

    private func collapseConversationVisibleWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

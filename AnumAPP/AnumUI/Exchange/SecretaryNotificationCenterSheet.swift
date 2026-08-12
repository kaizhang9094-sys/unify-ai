import SwiftUI
import AnumCore

private extension SecretaryNotification {
    var userFacingTitle: String {
        ExchangeUserFacingCopySanitizer.sanitizeOrFallback(title, field: .title, fallback: "Update")
    }

    var userFacingBody: String {
        ExchangeUserFacingCopySanitizer.sanitizeOrFallback(body, field: .body, fallback: "New activity in this thread")
    }
}

struct SecretaryNotificationCenterSheet: View {
    let notifications: [SecretaryNotification]
    let onDismiss: () -> Void
    let onSelect: (SecretaryNotification) -> Void
    let onMarkAllRead: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var markingAll = false

    private var unreadCount: Int {
        notifications.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if notifications.isEmpty {
                        UnifyDarkEmptyState(
                            title: "You’re caught up.",
                            message: "When something needs attention, it will appear here.",
                            systemImage: "bell",
                            minHeight: 220
                        )
                        .padding(.horizontal, 18)
                        .padding(.top, 24)
                    } else {
                        UnifyDarkCard(cornerRadius: 20, strokeOpacity: 0.9) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(notifications.enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        dismiss()
                                        onSelect(item)
                                    } label: {
                                        notificationRow(item)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 5)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if index < notifications.count - 1 {
                                        Rectangle()
                                            .fill(SecretaryTheme.darkStroke.opacity(0.38))
                                            .frame(height: 1)
                                            .padding(.leading, 34)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Updates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                // Match `SecretaryStyleSettingsView` (Secretary Instructions) leading toolbar control exactly.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                        onDismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            markingAll = true
                            defer { markingAll = false }
                            await onMarkAllRead()
                            dismiss()
                            onDismiss()
                        }
                    } label: {
                        Text("Mark all read")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                markingAll || unreadCount == 0
                                    ? SecretaryTheme.darkMutedText
                                    : SecretaryTheme.darkOrange
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(markingAll || unreadCount == 0)
                    .opacity(unreadCount == 0 ? 0.42 : 1)
                }
            }
        }
        .tint(SecretaryTheme.darkOrange)
    }

    private func notificationRow(_ item: SecretaryNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.isRead ? Color.clear : SecretaryTheme.darkOrange)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(kindChip(item.kind))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkGlass.opacity(0.55))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
                                )
                        )

                    Text(SecretaryRelativeTime.string(from: item.updatedAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)

                    Spacer(minLength: 0)
                }

                Text(item.userFacingTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text(item.userFacingBody)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .padding(.top, 32)
        }
        .opacity(item.isRead ? 0.86 : 1)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.userFacingTitle). \(item.userFacingBody)")
    }

    private func kindChip(_ kind: SecretaryNotificationKind) -> String {
        switch kind {
        case .newReply: return "MESSAGE"
        case .needsAnswer: return "ANSWER NEEDED"
        case .needsApproval: return "APPROVAL"
        case .sendFailed: return "SEND"
        case .matchReady: return "MATCH READY"
        case .recoveryNeeded: return "RECOVERY"
        case .trustedContactAdded: return "CONTACT"
        case .messageSent: return "SENT"
        case .discoveryMatch: return "DISCOVERY"
        case .publicationIssue: return "SURFACE"
        case .inboundDigest: return "CHAT"
        case .approvalDigest: return "APPROVALS"
        }
    }
}

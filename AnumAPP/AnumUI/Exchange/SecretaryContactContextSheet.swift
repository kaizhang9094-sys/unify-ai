import SwiftUI
import AnumCore

struct SecretaryContactContextSheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    let remoteNodeID: String
    let displayName: String
    let onSaved: (ExchangeModels.ContactContext) -> Void

    @State private var relationshipChoice: ReplyContextRelationshipChoice = .workContact
    @State private var customRelationshipLabel: String = ""
    @State private var goalChoice: ReplyContextGoalChoice = .keepInTouch
    @State private var customRelationshipGoal: String = ""
    @State private var goalNotes: String = ""
    @State private var notes: String = ""
    @State private var toneOverride: String = ""
    @State private var suggestionsEnabled: Bool = true
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    replyContextIntro

                    relationshipCard
                    goalCard
                    assistCard
                    optionalNotesCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Reply context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isSaving ? SecretaryTheme.darkMutedText : SecretaryTheme.darkOrange
                    )
                    .disabled(isSaving)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                load()
            }
        }
        .tint(SecretaryTheme.darkOrange)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    // MARK: - Intro

    private var replyContextIntro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Private notes that help your AI suggest better replies.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Suggestions only — nothing sends automatically.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    // MARK: - Cards

    private var relationshipCard: some View {
        UnifyDarkCard(cornerRadius: 24, strokeOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 14) {
                contactContextSectionHeader(title: "Relationship", systemImage: "person.2")

                contextMenuField(
                    title: "How you know them",
                    value: relationshipChoice.title,
                    systemImage: "person.crop.circle"
                ) {
                    ForEach(ReplyContextRelationshipChoice.allCases) { choice in
                        Button {
                            relationshipChoice = choice
                        } label: {
                            Text(choice.title)
                        }
                    }
                }

                if relationshipChoice == .custom {
                    textField(
                        "Describe the relationship",
                        text: $customRelationshipLabel,
                        placeholder: "Example: mentor, neighbour, repeat buyer"
                    )
                }
            }
            .padding(16)
        }
    }

    private var goalCard: some View {
        UnifyDarkCard(cornerRadius: 24, strokeOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 14) {
                contactContextSectionHeader(title: "Reply goal", systemImage: "target")

                contextHint(
                    "What you want these suggested replies to move toward."
                )

                contextMenuField(
                    title: "Goal for this person",
                    value: goalChoice.title,
                    systemImage: "arrow.up.forward.circle"
                ) {
                    ForEach(ReplyContextGoalChoice.allCases) { choice in
                        Button {
                            goalChoice = choice
                        } label: {
                            Text(choice.title)
                        }
                    }
                }

                if goalChoice == .custom {
                    textField(
                        "Describe the goal",
                        text: $customRelationshipGoal,
                        placeholder: "Example: stay helpful without overcommitting"
                    )
                }

                optionalField(
                    title: "Goal notes (optional)",
                    text: $goalNotes,
                    placeholder: "Pacing, boundaries, or context for suggestions…",
                    minLines: 2,
                    maxLines: 5
                )
            }
            .padding(16)
        }
    }

    private var assistCard: some View {
        UnifyDarkCard(cornerRadius: 24, strokeOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 14) {
                contactContextSectionHeader(title: "Suggestions", systemImage: "sparkles")

                contextMenuField(
                    title: "Reply suggestions",
                    value: suggestionsEnabled ? "Suggestions on" : "Suggestions off",
                    systemImage: "wand.and.stars"
                ) {
                    Button {
                        suggestionsEnabled = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggestions on")
                            Text("Your AI can suggest replies.")
                                .font(.footnote)
                        }
                    }

                    Button {
                        suggestionsEnabled = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggestions off")
                            Text("No AI reply suggestions for this person.")
                                .font(.footnote)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var optionalNotesCard: some View {
        UnifyDarkCard(cornerRadius: 24, strokeOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 14) {
                contactContextSectionHeader(title: "Optional notes", systemImage: "text.alignleft")

                contextHint(
                    "Add detail only if it helps suggestions. Leave blank if the picks above are enough."
                )

                optionalField(
                    title: "Notes (optional)",
                    text: $notes,
                    placeholder: "How you met, boundaries, preferences…",
                    minLines: 3,
                    maxLines: 7
                )

                optionalField(
                    title: "Tone (optional)",
                    text: $toneOverride,
                    placeholder: "Example: warm and casual, professional and concise…",
                    minLines: 2,
                    maxLines: 5
                )
            }
            .padding(16)
        }
    }

    private func contactContextSectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .frame(width: 26, alignment: .center)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Custom Controls

    private func contextMenuField<Content: View>(
        title: String,
        value: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            Menu {
                content()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .frame(width: 20, height: 20, alignment: .center)

                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.86)
                        .layoutPriority(-1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .frame(width: 16, alignment: .center)
                }
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.92), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func contextHint(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13.5))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func textField(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .tint(SecretaryTheme.darkOrange)
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.92), lineWidth: 1)
                )
        }
    }

    private func optionalField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        minLines: Int,
        maxLines: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14.5))
                        .foregroundStyle(SecretaryTheme.darkMutedText.opacity(0.95))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }

                TextField("", text: text, axis: .vertical)
                    .lineLimit(minLines...maxLines)
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .tint(SecretaryTheme.darkOrange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.92), lineWidth: 1)
            )
        }
    }

    // MARK: - Data

    private func load() {
        let context = services.getContactContext(remoteNodeID: remoteNodeID)
        relationshipChoice = ReplyContextRelationshipChoice.from(storage: context.relationshipType)
        customRelationshipLabel = context.customRelationshipLabel ?? ""
        goalChoice = ReplyContextGoalChoice.from(storage: context.relationshipGoal)
        customRelationshipGoal = context.customRelationshipGoal ?? ""
        goalNotes = context.goalNotes ?? ""
        notes = context.notes
        toneOverride = context.toneOverride ?? ""
        suggestionsEnabled = context.aiAssistLevel != .autoReplyDisabled
    }

    private func save() {
        isSaving = true

        var context = services.getContactContext(remoteNodeID: remoteNodeID)
        context.relationshipType = relationshipChoice.storageType
        if relationshipChoice == .custom {
            let trimmed = customRelationshipLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            context.customRelationshipLabel = trimmed.isEmpty ? nil : trimmed
        } else {
            context.customRelationshipLabel = nil
        }

        context.relationshipGoal = goalChoice.storageGoal
        if goalChoice == .custom {
            let trimmed = customRelationshipGoal.trimmingCharacters(in: .whitespacesAndNewlines)
            context.customRelationshipGoal = trimmed.isEmpty ? nil : trimmed
        } else {
            context.customRelationshipGoal = nil
        }

        context.goalNotes = goalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : goalNotes
        context.notes = notes
        context.toneOverride = toneOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : toneOverride
        context.aiAssistLevel = suggestionsEnabled ? .suggestOnly : .autoReplyDisabled
        context.updatedAt = Date()

        let saved = services.saveContactContext(context)
        onSaved(saved)
        isSaving = false
        dismiss()
    }
}

// MARK: - Simplified UI choices (maps to persisted Exchange enums)

private enum ReplyContextRelationshipChoice: String, CaseIterable, Identifiable {
    case friend
    case family
    case workContact
    case client
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friend: return "Friend"
        case .family: return "Family"
        case .workContact: return "Work contact"
        case .client: return "Client"
        case .custom: return "Custom"
        }
    }

    var storageType: ExchangeModels.ContactRelationshipType {
        switch self {
        case .friend: return .friend
        case .family: return .family
        case .workContact: return .professionalContact
        case .client: return .client
        case .custom: return .custom
        }
    }

    static func from(storage: ExchangeModels.ContactRelationshipType) -> Self {
        switch storage {
        case .friend:
            return .friend
        case .family:
            return .family
        case .client, .lead:
            return .client
        case .custom:
            return .custom
        case .colleague, .supplier, .investor, .broker, .contractor, .professionalContact:
            return .workContact
        }
    }
}

private enum ReplyContextGoalChoice: String, CaseIterable, Identifiable {
    case keepInTouch
    case buildFriendship
    case workTogether
    case sellOrWinWork
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepInTouch: return "Keep in touch"
        case .buildFriendship: return "Build friendship"
        case .workTogether: return "Work together"
        case .sellOrWinWork: return "Sell or win work"
        case .custom: return "Custom"
        }
    }

    var storageGoal: ExchangeModels.RelationshipGoal {
        switch self {
        case .keepInTouch: return .maintainFriendship
        case .buildFriendship: return .becomeCloserFriends
        case .workTogether: return .warmProfessionalContact
        case .sellOrWinWork: return .developClientRelationship
        case .custom: return .custom
        }
    }

    static func from(storage: ExchangeModels.RelationshipGoal) -> Self {
        switch storage {
        case .maintainFriendship, .reconnectCasually:
            return .keepInTouch
        case .becomeCloserFriends, .personalRelationship:
            return .buildFriendship
        case .warmProfessionalContact, .explorePartnership,
             .maintainSupplierRelationship, .referralContact, .buildInvestorRelationship:
            return .workTogether
        case .developClientRelationship, .winFutureContract:
            return .sellOrWinWork
        case .custom:
            return .custom
        }
    }
}

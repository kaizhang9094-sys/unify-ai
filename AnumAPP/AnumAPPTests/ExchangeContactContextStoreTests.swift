import XCTest
@testable import AnumAPP
@testable import AnumCore

final class ExchangeContactContextStoreTests: XCTestCase {
    func test_defaultContext_isSuggestOnlyProfessional() {
        let suite = "exchange-contact-context-default-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ExchangeUserDefaultsContactContextStore(defaults: defaults)

        let context = store.getContext(remoteNodeID: "node-default-1")
        XCTAssertEqual(context.remoteNodeID, "node-default-1")
        XCTAssertEqual(context.relationshipType, .professionalContact)
        XCTAssertEqual(context.relationshipGoal, .warmProfessionalContact)
        XCTAssertEqual(context.aiAssistLevel, .suggestOnly)
    }

    func test_saveAndLoad_byRemoteNodeID() {
        let suite = "exchange-contact-context-save-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ExchangeUserDefaultsContactContextStore(defaults: defaults)

        let saved = store.saveContext(
            .init(
                remoteNodeID: "node-save-1",
                relationshipType: .client,
                relationshipGoal: .winFutureContract,
                notes: "Prefers short updates.",
                toneOverride: "professional and concise",
                aiAssistLevel: .draftBeforeSend
            )
        )
        let loaded = store.getContext(remoteNodeID: "node-save-1")
        XCTAssertEqual(loaded.remoteNodeID, "node-save-1")
        XCTAssertEqual(loaded.relationshipType, .client)
        XCTAssertEqual(loaded.relationshipGoal, .winFutureContract)
        XCTAssertEqual(loaded.notes, "Prefers short updates.")
        XCTAssertEqual(loaded.toneOverride, "professional and concise")
        XCTAssertEqual(loaded.aiAssistLevel, .draftBeforeSend)
        XCTAssertEqual(saved.remoteNodeID, loaded.remoteNodeID)
    }

    func test_notesAndTone_areLengthCapped() {
        let suite = "exchange-contact-context-caps-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ExchangeUserDefaultsContactContextStore(defaults: defaults)

        let longNotes = String(repeating: "n", count: 2000)
        let longTone = String(repeating: "t", count: 900)
        let saved = store.saveContext(
            .init(
                remoteNodeID: "node-cap-1",
                relationshipType: .colleague,
                notes: longNotes,
                toneOverride: longTone
            )
        )
        XCTAssertEqual(saved.notes.count, 1500)
        XCTAssertEqual(saved.toneOverride?.count, 500)
    }

    func test_customGoal_persists() {
        let suite = "exchange-contact-context-custom-goal-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ExchangeUserDefaultsContactContextStore(defaults: defaults)

        _ = store.saveContext(
            .init(
                remoteNodeID: "node-custom-goal",
                relationshipType: .custom,
                relationshipGoal: .custom,
                customRelationshipGoal: "Build long-term creative collaboration"
            )
        )
        let loaded = store.getContext(remoteNodeID: "node-custom-goal")
        XCTAssertEqual(loaded.relationshipGoal, .custom)
        XCTAssertEqual(loaded.customRelationshipGoal, "Build long-term creative collaboration")
    }

    func test_directReplyPrompt_includesRelationshipGoalAndSuggestOnlySafety() {
        let context = ExchangeModels.ContactContext(
            remoteNodeID: "node-prompt-goal",
            relationshipType: .professionalContact,
            relationshipGoal: .referralContact,
            notes: "Be useful and concise."
        )
        let input = ExchangeModels.DirectReplySuggestionInput(
            remoteNodeID: "node-prompt-goal",
            contactDisplayName: "Dana",
            latestIncomingMessage: "Can you share a referral?",
            recentTranscript: [
                .init(role: .remoteContact, text: "Can you share a referral?")
            ],
            contactContext: context,
            relationshipType: context.relationshipType,
            relationshipGoal: context.relationshipGoal,
            relationshipNotes: context.notes,
            toneOverride: context.toneOverride,
            userSecretaryStyle: "professional and concise",
            userSecretaryConstitution: "safety first",
            contactPublicProfileSummary: "Advisor",
            contactCommercialProfileSummary: "Consulting",
            safetyRules: ["suggest_only_never_send"]
        )
        let prompt = AppServices.buildDirectReplySuggestionPromptForTesting(
            input: input,
            latestInboundMessage: "Can you share a referral?",
            userInstruction: nil,
            commercialSummaryOverride: "Consulting"
        )
        XCTAssertTrue(prompt.contains("\"relationshipGoal\":\"referralContact\""))
        XCTAssertTrue(prompt.contains("suggest_only_never_send"))
        XCTAssertTrue(prompt.contains("never_optimize_for_manipulation"))
    }

    func test_personalRelationshipGoal_doesNotEnableAutoSend() {
        let context = ExchangeModels.ContactContext(
            remoteNodeID: "node-personal-goal",
            relationshipType: .custom,
            relationshipGoal: .personalRelationship,
            customRelationshipGoal: "Get to know each other respectfully"
        )
        let input = ExchangeModels.DirectReplySuggestionInput(
            remoteNodeID: "node-personal-goal",
            contactDisplayName: "Alex",
            latestIncomingMessage: "Hi",
            recentTranscript: [],
            contactContext: context,
            relationshipType: context.relationshipType,
            relationshipGoal: context.relationshipGoal,
            relationshipNotes: context.notes,
            toneOverride: context.toneOverride,
            userSecretaryStyle: nil,
            userSecretaryConstitution: nil,
            contactPublicProfileSummary: nil,
            contactCommercialProfileSummary: nil,
            safetyRules: ["suggest_only_never_send"]
        )
        let prompt = AppServices.buildDirectReplySuggestionPromptForTesting(
            input: input,
            latestInboundMessage: "Hi",
            userInstruction: nil
        )
        XCTAssertTrue(prompt.contains("\"relationshipGoal\":\"personalRelationship\""))
        XCTAssertTrue(prompt.contains("Suggest only. Never send."))
    }

    func test_recentTranscript_isCappedToLatestTenInPrompt() {
        let context = ExchangeModels.ContactContext(remoteNodeID: "node-cap")
        let messages: [ExchangeModels.DirectReplyTranscriptMessage] = (0..<14).map {
            .init(role: $0 % 2 == 0 ? .localUser : .remoteContact, text: "m\($0)")
        }
        let input = ExchangeModels.DirectReplySuggestionInput(
            remoteNodeID: "node-cap",
            recentTranscript: messages,
            contactContext: context,
            relationshipType: context.relationshipType,
            relationshipGoal: context.relationshipGoal,
            relationshipNotes: "",
            safetyRules: ["suggest_only_never_send"]
        )
        let prompt = AppServices.buildDirectReplySuggestionPromptForTesting(
            input: input,
            latestInboundMessage: "m13",
            userInstruction: nil
        )
        XCTAssertFalse(prompt.contains("\"text\":\"m0\""))
        XCTAssertTrue(prompt.contains("\"text\":\"m13\""))
    }

    func test_contactReplySuggestion_requiresApprovalByDefault() {
        let suggestion = ExchangeModels.ContactReplySuggestion(reply: "Thanks, I will follow up.")
        XCTAssertTrue(suggestion.requiresApproval)
    }
}

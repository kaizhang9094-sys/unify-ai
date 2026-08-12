import Foundation

// MARK: - Companion UserDefaults (explicit keys only)

public enum CompanionWipeUserDefaultsKeys {
    public static let all: [String] = [
        "companionAvatarThumbFilename",
        "companionAvatarFullFilename",
        "companionBackgroundThumbFilename",
        "companionBackgroundFullFilename",
        "companionPrologue",
        "hasOnboarded",
        "companionName",
        "companionGenderRaw",
        "userName",
        "userGenderRaw",
        "onboarding.relationshipRole",
        "onboarding.relationshipRoleRaw",
        "onboarding.role",
        "onboarding.relationship",
        "onboarding.showUpStyles",
        "onboarding.showUpStylesRaw",
        "onboarding.showUp",
        "onboarding.showUpRaw",
        "onboarding.conversationThemes",
        "onboarding.conversationThemesRaw",
        "onboarding.themes",
        "onboarding.themeRaw",
        "onboarding.goals",
        "onboarding.goalRaw",
        "onboarding.goalsRaw",
        "onboarding.userGoals",
        "onboarding.extraNote",
        "onboarding.note",
        "onboarding.journalNote",
        "onboarding.companionPronouns",
        "onboarding.companionPronounsRaw",
        "onboarding.userPronouns",
        "onboarding.userPronounsRaw",
        "onboarding.isAdult",
        "onboarding.userIsAdult",
        "onboarding.user_is_adult",
        "onboarding.userAge",
        "onboarding.age",
        "onboarding.user_age"
    ]
}

// MARK: - Secretary UserDefaults (prefix + explicit keys)

public enum SecretaryWipeUserDefaultsCatalog {
    public static let keyPrefixes: [String] = [
        "secretary.",
        "exchange.",
        "forYou.standingInterest.v2."
    ]

    public static let exactKeys: [String] = [
        "DirectChatPrefixCachedReplayForceFullNext"
    ]

    public static let protectedExactKeys: Set<String> = [
        "Anum.identity.selectedId"
    ]

    public static func shouldRemoveKey(_ key: String) -> Bool {
        if protectedExactKeys.contains(key) { return false }
        if exactKeys.contains(key) { return true }
        return keyPrefixes.contains { key.hasPrefix($0) }
    }
}

// MARK: - File paths

public enum UnifyDataLifecycleFiles {
    public static let symbioticCompanionRuntimeFilenames = [
        "symbiotic_seeds.json",
        "symbiotic_state.json",
        "symbiotic_hints.json"
    ]

    public static func exchangeDatabaseURLs(baseDirectory: URL) -> [URL] {
        let main = baseDirectory.appendingPathComponent("exchange.sqlite")
        return [
            main,
            URL(fileURLWithPath: main.path + "-wal"),
            URL(fileURLWithPath: main.path + "-shm")
        ]
    }
}

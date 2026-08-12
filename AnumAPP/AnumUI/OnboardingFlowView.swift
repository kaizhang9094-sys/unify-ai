

import SwiftUI

private struct OnboardingBackdrop: View {
    let imageName: String?

    var body: some View {
        ZStack {
            // Always keep an opaque base so there are no seams/lines at the top during paging.
            Color.black
                .ignoresSafeArea()

            if let name = imageName {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.16, blue: 0.28),
                        Color(red: 0.10, green: 0.30, blue: 0.52)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            // Gentle readability overlay (no vignette border, no blur)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.30),
                    Color.black.opacity(0.12),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Tiny uniform darkening so the very top never looks “unfiltered”.
            Rectangle()
                .fill(Color.black.opacity(0.04))
                .ignoresSafeArea()
        }
    }
}

private enum OnboardingFocusField: Hashable {
    case companionName
    case userName
    case extraNote
}

struct OnboardingFlowView: View {
    @Binding var hasOnboarded: Bool

    // Existing persisted basics used by RootView / Room
    @Binding var companionName: String
    @Binding var companionGenderRaw: String
    @Binding var userName: String
    @Binding var userGenderRaw: String

    @EnvironmentObject private var services: AppServices
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedField: OnboardingFocusField?

    private func dismissKeyboard() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
#endif
    }

    private func isTextEntryPage(_ p: Int) -> Bool {
        // Pages that contain a TextField.
        // 2: Companion name, 4: User name
        p == 2 || p == 4
    }

    @State private var page: Int = 0
    @State private var draft: OnboardingState = .init()

    // For the final blend page
    @State private var bridgeOverlayVisible: Bool = true
    @State private var showValidationHint: Bool = false

    private let lastPageIndex: Int = 12 // Bridge page tag

    var body: some View {
        TabView(selection: $page) {
            HeroPage()
                .tag(0)

            AboutThisAppPage()
                .tag(1)

            CompanionNamePage(name: $draft.companionName, focusedField: $focusedField)
                .tag(2)

            CompanionPronounsPage(choice: $draft.companionPronouns)
                .tag(3)

            UserNamePage(name: $draft.userName, focusedField: $focusedField)
                .tag(4)

            UserPronounsPage(choice: $draft.userPronouns)
                .tag(5)

            AgePage(age: $draft.userAge, onChanged: sanitizeForAge)
                .tag(6)

            RelationshipRolePage(
                isAdult: draft.isAdult,
                role: $draft.relationshipRole
            )
            .tag(7)

            ShowUpStylesPage(
                isAdult: draft.isAdult,
                selections: $draft.showUpStyles
            )
            .tag(8)

            ConversationThemesPage(
                isAdult: draft.isAdult,
                selections: $draft.conversationThemes
            )
            .tag(9)

            GoalsPage(
                selections: $draft.goals
            )
            .tag(10)

            HowToUsePage()
                .tag(11)

            // Bridge page: renders the real Room shell behind an overlay
            BridgeToRoomPage(
                companionName: resolvedCompanionName,
                overlayVisible: $bridgeOverlayVisible,
                showValidationHint: $showValidationHint,
                onEnter: enterRoom
            )
            .tag(12)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .ignoresSafeArea()
        .background(
            // Prevents “white flash” / leftover edge artifacts while swiping between pages
            Color(red: 0.05, green: 0.16, blue: 0.28)
                .ignoresSafeArea()
        )
        .overlay(alignment: .bottom) {
            onboardingBottomBar
        }
        .onChange(of: scenePhase) { _, phase in
            // Defensive: if iOS presents a system modal (e.g. crash/analytics prompt) while a TextField
            // is focused, SwiftUI focus reconciliation can crash on some devices/OS builds.
            // Clear focus whenever we leave the active phase.
            if phase != .active {
                focusedField = nil
                dismissKeyboard()
            }
        }
        .task(id: page) {
            // Only adjust focus/keyboard while active. System modals can transition us to inactive.
            guard scenePhase == .active else { return }

            // When moving to a selection-only page, ensure any TextField focus is cleared so
            // the keyboard doesn't cover the options.
            if !isTextEntryPage(page) {
                await MainActor.run {
                    focusedField = nil
                    dismissKeyboard()
                }
            }
        }
        .onAppear {
            // Initialize draft from stored values if any (in case user re-triggers onboarding)
            let initialCompanionName = companionName.trimmed
            let normalizedCompanionName = initialCompanionName
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Treat the built-in default name as "unset" so the TextField shows its placeholder.
            draft.companionName = (normalizedCompanionName.isEmpty || normalizedCompanionName == "anum") ? "" : initialCompanionName
            let initialUserName = userName.trimmed
            draft.userName = (initialUserName.isEmpty || initialUserName.caseInsensitiveCompare("Anum") == .orderedSame) ? "" : initialUserName

            // Best-effort restore of the old raw keys into the new UI (does not block onboarding).
            if !companionGenderRaw.isEmpty {
                draft.companionPronouns = PronounsChoice.fromLegacyRaw(companionGenderRaw)
            }
            if !userGenderRaw.isEmpty {
                draft.userPronouns = UserPronounsChoice.fromLegacyRaw(userGenderRaw)
            }

            // Restore extended onboarding choices if present
            let ud = UserDefaults.standard
            if ud.object(forKey: Keys.userAge) != nil {
                draft.userAge = ud.integer(forKey: Keys.userAge)
            }
            if let raw = ud.string(forKey: Keys.relationshipRole) {
                draft.relationshipRole = RelationshipRole(rawValue: raw)
            }
            if let arr = ud.array(forKey: Keys.showUpStyles) as? [String] {
                draft.showUpStyles = Set(arr.compactMap(ShowUpStyle.init(rawValue:)))
            }
            if let arr = ud.array(forKey: Keys.conversationThemes) as? [String] {
                draft.conversationThemes = Set(arr.compactMap(ConversationTheme.init(rawValue:)))
            }
            if let arr = ud.array(forKey: Keys.goals) as? [String] {
                draft.goals = Set(arr.compactMap(Goal.init(rawValue:)))
            }
            draft.extraNote = ud.string(forKey: Keys.extraNote) ?? ""

            sanitizeForAge()
        }
    }

    private var onboardingBottomBar: some View {
        VStack(spacing: 10) {
            if page < lastPageIndex {
                Button {
                    goNext()
                } label: {
                    Text(primaryButtonTitle)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.06, green: 0.12, blue: 0.20))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(primaryButtonDisabled)
                .tint(
                    LinearGradient(
                        colors: [
                            // warm apricot (top)
                            Color(red: 0.94, green: 0.64, blue: 0.34),
                            // toasted amber (bottom)
                            Color(red: 0.84, green: 0.50, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(primaryButtonDisabled ? 0.40 : 1.0)
                .shadow(color: .black.opacity(primaryButtonDisabled ? 0.0 : 0.12), radius: 10, x: 0, y: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            } else {
                // Bridge page has its own Enter button inside the overlay for better blending.
                EmptyView()
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var primaryButtonTitle: String {
        if page == 0 { return "Start" }
        return "Next"
    }

    private var primaryButtonDisabled: Bool {
        switch page {
        case 2:
            return draft.companionName.trimmed.isEmpty
        case 3:
            return draft.companionPronouns == nil
        case 6:
            return draft.userAge == nil
        case 7:
            return draft.relationshipRole == nil
        case 8:
            return draft.showUpStyles.isEmpty
        case 9:
            return draft.conversationThemes.isEmpty
        case 10:
            return draft.goals.isEmpty
        default:
            return false
        }
    }

    private var resolvedCompanionName: String {
        let trimmed = draft.companionName.trimmed
        return trimmed.isEmpty ? "Companion Name" : trimmed
    }

    private func goNext() {
        focusedField = nil
        dismissKeyboard()
        guard page < lastPageIndex else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            page += 1
        }
    }

    private func sanitizeForAge() {
        // Enforce 18+ gating: strip romantic selections if user is not adult.
        guard !draft.isAdult else { return }
        if draft.relationshipRole == .romanticPartner {
            draft.relationshipRole = nil
        }
        draft.showUpStyles.remove(.affectionate)
        draft.conversationThemes.remove(.romanceAffection)
    }

    private func firstInvalidPage() -> Int? {
        if draft.companionName.trimmed.isEmpty { return 2 }
        if draft.companionPronouns == nil { return 3 }
        if draft.userAge == nil { return 6 }
        if draft.relationshipRole == nil { return 7 }
        if draft.showUpStyles.isEmpty { return 8 }
        if draft.conversationThemes.isEmpty { return 9 }
        if draft.goals.isEmpty { return 10 }
        return nil
    }

    private func enterRoom() {
        if let invalid = firstInvalidPage() {
            withAnimation(.easeInOut(duration: 0.2)) {
                page = invalid
            }
            // If user somehow tries to enter, show a subtle hint (Bridge page uses it visually).
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                showValidationHint = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showValidationHint = false
                }
            }
            return
        }

        // Fade out overlay first for a “door opening” effect
        withAnimation(.easeInOut(duration: 0.25)) {
            bridgeOverlayVisible = false
        }

        // Commit after the overlay fades, then RootView switches to RoomView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let resolvedName = resolvedCompanionName

            companionName = resolvedName
            userName = draft.userName.trimmed

            // Keep legacy raw keys filled with best-effort values for now.
            // (We store richer preferences separately below.)
            companionGenderRaw = draft.companionPronouns?.legacyRaw ?? "na"
            userGenderRaw = draft.userPronouns.legacyRaw

            persistExtendedProfile(resolvedCompanionName: resolvedName)

            // Phase 6: Apply onboarding profile immediately so identity layer sees it on the first turn.
            services.chat.applyOnboardingProfileNow()

            withAnimation(.easeInOut(duration: 0.25)) {
                hasOnboarded = true
            }
        }
    }

    private func persistExtendedProfile(resolvedCompanionName: String) {
        let ud = UserDefaults.standard

        if let age = draft.userAge {
            ud.set(age, forKey: Keys.userAge)
        }
        ud.set(draft.isAdult, forKey: Keys.isAdult)

        ud.set(resolvedCompanionName, forKey: Keys.companionName)
        ud.set(draft.companionPronouns?.rawValue ?? "", forKey: Keys.companionPronouns)

        ud.set(draft.userName.trimmed, forKey: Keys.userName)
        ud.set(draft.userPronouns.rawValue, forKey: Keys.userPronouns)

        ud.set(draft.relationshipRole?.rawValue ?? "", forKey: Keys.relationshipRole)

        ud.set(Array(draft.showUpStyles.map { $0.rawValue }), forKey: Keys.showUpStyles)
        ud.set(Array(draft.conversationThemes.map { $0.rawValue }), forKey: Keys.conversationThemes)
        ud.set(Array(draft.goals.map { $0.rawValue }), forKey: Keys.goals)

        ud.set(draft.extraNote.trimmed, forKey: Keys.extraNote)
    }
}

// MARK: - Draft + Keys

private struct OnboardingState {
    var companionName: String = ""
    var companionPronouns: PronounsChoice? = nil

    var userName: String = ""
    var userPronouns: UserPronounsChoice = .skip

    var userAge: Int? = nil

    var relationshipRole: RelationshipRole? = nil
    var showUpStyles: Set<ShowUpStyle> = []     // pick 1–2
    var conversationThemes: Set<ConversationTheme> = [] // pick 1–3
    var goals: Set<Goal> = []                   // pick 1–3
    var extraNote: String = ""

    var isAdult: Bool {
        guard let age = userAge else { return false }
        return age >= 18
    }
}

private enum Keys {
    static let userAge = "onboarding.userAge"
    static let isAdult = "onboarding.isAdult"

    static let companionName = "onboarding.companionName"
    static let companionPronouns = "onboarding.companionPronouns"

    static let userName = "onboarding.userName"
    static let userPronouns = "onboarding.userPronouns"

    static let relationshipRole = "onboarding.relationshipRole"
    static let showUpStyles = "onboarding.showUpStyles"
    static let conversationThemes = "onboarding.conversationThemes"
    static let goals = "onboarding.goals"
    static let extraNote = "onboarding.extraNote"
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Choices

private enum PronounsChoice: String, CaseIterable, Identifiable {
    case sheHer
    case heHim
    case theyThem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sheHer: return "She / her"
        case .heHim: return "He / him"
        case .theyThem: return "They / them"
        }
    }

    /// Best-effort mapping back to your legacy raw key.
    var legacyRaw: String {
        switch self {
        case .sheHer: return "female"
        case .heHim: return "male"
        case .theyThem: return "neutral"
        }
    }

    static func fromLegacyRaw(_ raw: String) -> PronounsChoice {
        let r = raw.lowercased()
        if r.contains("female") || r == "f" { return .sheHer }
        if r.contains("male") || r == "m" { return .heHim }
        if r.contains("they") || r.contains("neutral") || r.contains("nb") { return .theyThem }
        return .theyThem
    }
}

private enum UserPronounsChoice: String, CaseIterable, Identifiable {
    case sheHer
    case heHim
    case theyThem
    case nameOnly
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sheHer: return "She / her"
        case .heHim: return "He / him"
        case .theyThem: return "They / them"
        case .nameOnly: return "Just use my name"
        case .skip: return "Skip"
        }
    }

    var legacyRaw: String {
        switch self {
        case .sheHer: return "female"
        case .heHim: return "male"
        case .theyThem: return "neutral"
        case .nameOnly: return "na"
        case .skip: return "na"
        }
    }

    static func fromLegacyRaw(_ raw: String) -> UserPronounsChoice {
        let r = raw.lowercased()
        if r.contains("female") || r == "f" { return .sheHer }
        if r.contains("male") || r == "m" { return .heHim }
        if r.contains("they") || r.contains("neutral") || r.contains("nb") { return .theyThem }
        if r.contains("na") { return .skip }
        return .skip
    }
}

private enum RelationshipRole: String, CaseIterable, Identifiable {
    case treeHoleListener
    case friend
    case mentor
    case coach
    case someoneSpecial
    case romanticPartner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .treeHoleListener: return "A listener"
        case .friend: return "A friend"
        case .mentor: return "A mentor"
        case .coach: return "A coach"
        case .someoneSpecial: return "Someone special"
        case .romanticPartner: return "A romantic partner"
        }
    }
}

private enum ShowUpStyle: String, CaseIterable, Identifiable, Hashable {
    case mostlyListen
    case steady
    case practical
    case reassuring
    case playful
    case affectionate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostlyListen: return "Mostly listen. Don’t interrupt."
        case .steady: return "Stay steady. Keep me grounded."
        case .practical: return "Be clear and practical."
        case .reassuring: return "Be soft and reassuring."
        case .playful: return "Bring a little lightness."
        case .affectionate: return "Be affectionate."
        }
    }
}

private enum ConversationTheme: String, CaseIterable, Identifiable, Hashable {
    case feelings
    case stressAnxiety
    case relationships
    case habits
    case funRandom
    case romanceAffection
    case ideasMeaning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feelings: return "Feelings and emotions"
        case .stressAnxiety: return "Stress and anxiety"
        case .relationships: return "Relationships"
        case .habits: return "Motivation and habits"
        case .funRandom: return "Fun and randomness"
        case .romanceAffection: return "Romance and affection"
        case .ideasMeaning: return "Ideas and meaning"
        }
    }
}

private enum Goal: String, CaseIterable, Identifiable, Hashable {
    case calm
    case mood
    case vent
    case consistency
    case clarity
    case lessAlone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return "Help me calm down"
        case .mood: return "Lift my mood"
        case .vent: return "Let me vent safely"
        case .consistency: return "Keep me consistent"
        case .clarity: return "Help me think clearly"
        case .lessAlone: return "Help me feel less alone"
        }
    }
}

// MARK: - Pages

private struct HeroPage: View {
    var body: some View {
        ZStack {
            OnboardingBackdrop(imageName: "onboarding_first")

            GeometryReader { geo in
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Text("Create your private")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("AI companion")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                    Text("No cloud. No tracking. Just you.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                // Upper-middle placement: tune the 0.10 value (0.08 higher, 0.12 lower)
                .padding(.top, geo.safeAreaInsets.top + geo.size.height * 0.10)
            }
        }
    }
}

private struct AboutThisAppPage: View {
    var body: some View {
        OnboardingQuestionPage(
            title: "Before you start:",
            subtitle: "A couple notes to help you settle in."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                AboutInfoSection(
                    symbol: "lock.fill",
                    title: "Private by design",
                    bodyText: "Runs entirely on your device."
                )

                AboutInfoSection(
                    symbol: "bolt.fill",
                    title: "First run warmth",
                    bodyText: "Initial setup is heavy. This settles quickly."
                )

                AboutInfoSection(
                    symbol: "text.bubble.fill",
                    title: "Steer with plain language",
                    bodyText: "Use native language to adjust language, emojis and tone."
                )

                AboutInfoSection(
                    symbol: "info.circle.fill",
                    title: "Not professional advice",
                    bodyText: "AI-powered. Not medical or legal advice."
                )
            }
            .padding(.top, 2)
        }
    }
}

private struct AboutInfoSection: View {
    let symbol: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black.opacity(0.55))
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.90))

                Text(bodyText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.70))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct HowToUsePage: View {
    var body: some View {
        OnboardingQuestionPage(
            title: "Shape your companion:",
            subtitle: "Prologue is your world-setting spell.",
            subtitleColor: Color(red: 0.78, green: 0.34, blue: 0.10).opacity(0.90)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HowToUseCalloutCard(
                    title: "Make it instantly yours",
                    bodyText: "Write a short Prologue that sets the stage—voice, relationship, and how it should respond. There are no rules. You can be practical, poetic, cinematic, weird, gentle… anything.",
                    symbol: "sparkles"
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Prologue example")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.90))

                    PrologueExampleCard(text:
                        "You are my schoolmate, we are best friend, you live in a small apartment, you have soft eyes, calm face, gentle smile, you wear grey oversized hoodie, you like cooking and travel, you have a pet named Mochi, You like staring at the stars in the night, you don't like crowds."
                    )

                    Text("Edit anytime in Settings → Prologue.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(red: 0.78, green: 0.34, blue: 0.10).opacity(0.90))
                }

                HowToUseMiniCard(
                    title: "If you don’t know what to write",
                    bodyText: "Start with: who she/he is to you + where she/he is + how she/he should speak.",
                    symbol: "wand.and.stars"
                )


                HowToUseMiniCard(
                    title: "Your character learns and adapts",
                    bodyText: "The more you share, the more she/he feels like yours.",
                    symbol: "leaf.fill"
                )

                HowToUseMiniCard(
                    title: "Customize the interface",
                    bodyText: "Change the avatar and background anytime in Settings.",
                    symbol: "photo.fill"
                )
            }
        }
    }
}

private struct HowToUseCalloutCard: View {
    let title: String
    let bodyText: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.78, green: 0.34, blue: 0.10).opacity(0.85))
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.92))

                Text(bodyText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.93, blue: 0.84).opacity(0.85),
                            Color(.systemGray6).opacity(0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct HowToUseMiniCard: View {
    let title: String
    let bodyText: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black.opacity(0.50))
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.90))

                Text(bodyText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.70))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct PrologueExampleCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .regular, design: .monospaced))
            .foregroundStyle(.black.opacity(0.78))
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray6).opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}


private struct CompanionNamePage: View {
    @Binding var name: String
    let focusedField: FocusState<OnboardingFocusField?>.Binding

    var body: some View {
        OnboardingQuestionPage(
            title: "What's my name?",
            subtitle: nil
        ) {
            TextField("My name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused(focusedField, equals: .companionName)
        }
    }
}

private struct CompanionPronounsPage: View {
    @Binding var choice: PronounsChoice?

    var body: some View {
        OnboardingQuestionPage(
            title: "My pronouns:",
            subtitle: nil
        ) {
            OptionGrid(options: PronounsChoice.allCases, selection: Binding(
                get: { choice },
                set: { choice = $0 }
            )) { opt in
                opt.title
            }
        }
    }
}

private struct UserNamePage: View {
    @Binding var name: String
    let focusedField: FocusState<OnboardingFocusField?>.Binding

    var body: some View {
        OnboardingQuestionPage(
            title: "What's you name?",
            subtitle: "A nickname is totally fine."
        ) {
            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused(focusedField, equals: .userName)
        }
    }
}

private struct UserPronounsPage: View {
    @Binding var choice: UserPronounsChoice

    var body: some View {
        OnboardingQuestionPage(
            title: "Your pronouns:",
            subtitle: nil
        ) {
            OptionGridRequired(
                options: UserPronounsChoice.allCases.filter { $0 != .nameOnly },
                selection: $choice,
                title: { $0.title }
            )
        }
    }
}

private struct AgePage: View {
    @Binding var age: Int?
    let onChanged: () -> Void

    var body: some View {
        OnboardingQuestionPage(
            title: "Your age:",
            subtitle: "This only changes available relationship modes."
        ) {
            Picker("Age", selection: Binding(
                get: { age ?? 18 },
                set: { age = $0; onChanged() }
            )) {
                ForEach(10..<100, id: \.self) { v in
                    Text("\(v)").tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxHeight: 220)
        }
        .onAppear {
            if age == nil { age = 18; onChanged() }
        }
    }
}

private struct RelationshipRolePage: View {
    let isAdult: Bool
    @Binding var role: RelationshipRole?

    private var options: [RelationshipRole] {
        if isAdult {
            return [.treeHoleListener, .friend, .someoneSpecial, .romanticPartner]
        } else {
            return [.treeHoleListener, .friend, .someoneSpecial]
        }
    }

    var body: some View {
        OnboardingQuestionPage(
            title: "How should i support?",
            subtitle: nil
        ) {
            OptionGrid(options: options, selection: Binding(
                get: { role },
                set: { role = $0 }
            )) { opt in
                opt.title
            }
        }
    }
}

private struct ShowUpStylesPage: View {
    let isAdult: Bool
    @Binding var selections: Set<ShowUpStyle>

    private var options: [ShowUpStyle] {
        if isAdult {
            return [.practical, .reassuring, .playful, .affectionate]
        } else {
            return [.practical, .reassuring, .playful]
        }
    }

    var body: some View {
        OnboardingQuestionPage(
            title: "How should i respond?",
            subtitle: "Pick up to 2."
        ) {
            MultiOptionGrid(
                options: options,
                selections: $selections,
                maxSelections: 2
            ) { opt in
                opt.title
            }
        }
    }
}

private struct ConversationThemesPage: View {
    let isAdult: Bool
    @Binding var selections: Set<ConversationTheme>

    private var options: [ConversationTheme] {
        if isAdult {
            return [.feelings, .habits, .funRandom, .romanceAffection]
        } else {
            return [.feelings, .habits, .funRandom, .ideasMeaning]
        }
    }

    var body: some View {
        OnboardingQuestionPage(
            title: "What topics matter most?",
            subtitle: "Pick up to 3."
        ) {
            MultiOptionGrid(
                options: options,
                selections: $selections,
                maxSelections: 3
            ) { opt in
                opt.title
            }
        }
    }
}

private struct GoalsPage: View {
    @Binding var selections: Set<Goal>

    private let options: [Goal] = [.mood, .vent, .clarity, .lessAlone]

    var body: some View {
        OnboardingQuestionPage(
            title: "What should i help?",
            subtitle: "Pick up to 3."
        ) {
            MultiOptionGrid(
                options: options,
                selections: $selections,
                maxSelections: 3
            ) { opt in
                opt.title
            }
        }
    }
}

// MARK: - Page Shell + Option UI

private struct OnboardingQuestionPage<Content: View>: View {
    let title: String
    let subtitle: String?
    let subtitleColor: Color?
    let content: () -> Content

    init(title: String, subtitle: String?, subtitleColor: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            let usableH = geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom
            // Slightly wider + ~20% taller fixed card
            let cardW = min(geo.size.width - 28, 400)
            let cardH = max(504, min(usableH * 0.79, 680))

            ZStack {
                // Calm blue → deep ocean backdrop (no purple / no "sexy" vibe)
                LinearGradient(
                    colors: [
                        // deep ocean (top)
                        Color(red: 0.05, green: 0.16, blue: 0.28),
                        // calm blue (mid)
                        Color(red: 0.10, green: 0.30, blue: 0.52),
                        // soft teal-blue (bottom)
                        Color(red: 0.08, green: 0.26, blue: 0.40)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Warm sunlight glow near the horizon (gold, not pink/purple)
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.00, green: 0.88, blue: 0.64).opacity(0.26),
                        Color.clear
                    ]),
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 760
                )
                .ignoresSafeArea()

                // Cool lift for depth (keeps it airy)
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.62, green: 0.84, blue: 1.00).opacity(0.14),
                        Color.clear
                    ]),
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 420
                )
                .ignoresSafeArea()

                // Subtle bottom glow so the lower area never reads too flat
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.75, green: 0.90, blue: 1.00).opacity(0.10),
                        Color.clear
                    ]),
                    center: .bottom,
                    startRadius: 0,
                    endRadius: 620
                )
                .ignoresSafeArea()

                // Fixed-size white card (same size on every slide)
                VStack {
                    Spacer(minLength: geo.safeAreaInsets.top + 18)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(title)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.90))
                            .fixedSize(horizontal: false, vertical: true)

                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(subtitleColor ?? .black.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Scroll only INSIDE the card so card size never changes between pages
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                content()
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.vertical, 22)
                    .padding(.horizontal, 18)
                    .frame(width: cardW, height: cardH, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(Color.white.opacity(0.94))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 10)

                    // leaves room for your bottom Next bar overlay
                    Spacer(minLength: geo.safeAreaInsets.bottom + 90)
                }
            }
            // Make default controls (Picker/TextField/etc.) readable on white
            .environment(\.colorScheme, .light)
        }
    }
}

private struct OptionGrid<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option?
    let title: (Option) -> String

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { opt in
                OptionCard(title: title(opt), isSelected: selection == opt)
                    .onTapGesture { selection = opt }
            }
        }
    }
}

private struct OptionGridRequired<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { opt in
                OptionCard(title: title(opt), isSelected: selection == opt)
                    .onTapGesture { selection = opt }
            }
        }
    }
}

private struct MultiOptionGrid<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selections: Set<Option>
    let maxSelections: Int
    let title: (Option) -> String

    @State private var capHintVisible: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { opt in
                OptionCard(title: title(opt), isSelected: selections.contains(opt))
                    .onTapGesture { toggle(opt) }
            }

            if capHintVisible {
                Text("Up to \(maxSelections)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: capHintVisible)
    }

    private func toggle(_ opt: Option) {
        if selections.contains(opt) {
            selections.remove(opt)
            return
        }
        if selections.count >= maxSelections {
            capHintVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                capHintVisible = false
            }
            return
        }
        selections.insert(opt)
    }
}

private struct OptionCard: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.black.opacity(0.88))
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(2)

            Spacer(minLength: 10)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? Color(.systemGray5) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(isSelected ? 0.10 : 0.06), lineWidth: 1)
        )
    }
}

#Preview {
    struct PreviewHost: View {
        @State var hasOnboarded = false
        @State var cName = ""
        @State var cGender = "na"
        @State var uName = ""
        @State var uGender = "na"

        var body: some View {
            let orch = AppOrchestrator(model: StubModelProvider())
            let services = AppServices(orchestrator: orch)
            OnboardingFlowView(
                hasOnboarded: $hasOnboarded,
                companionName: $cName,
                companionGenderRaw: $cGender,
                userName: $uName,
                userGenderRaw: $uGender
            )
            .environmentObject(services)
            .environmentObject(services.chat)
        }
    }

    return PreviewHost()
}

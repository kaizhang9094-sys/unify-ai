import SwiftUI

// MARK: - Flow

struct UnifyOnboardingFlowView: View {
    @Binding var hasOnboarded: Bool
    @Binding var companionName: String
    @Binding var companionGenderRaw: String
    @Binding var userName: String
    @Binding var userGenderRaw: String

    @EnvironmentObject private var services: AppServices
    @FocusState private var isAINameFocused: Bool

    @State private var page: Int = 0
    @State private var aiNameDraft: String = "Uni"

    private let lastPageIndex = 5
    private let defaultAIName = "Uni"

    var body: some View {
        ZStack {
            UnifyDarkBackground()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    UnifyOnboardingOnePersonPage()
                        .tag(0)

                    UnifyOnboardingSearchPage()
                        .tag(1)

                    UnifyOnboardingSuggestionsPage()
                        .tag(2)

                    UnifyOnboardingSellingPage()
                        .tag(3)

                    UnifyOnboardingPrivateMessagingPage()
                        .tag(4)

                    UnifyOnboardingNameAIPage(
                        aiName: $aiNameDraft,
                        isFocused: $isAINameFocused
                    )
                    .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.22), value: page)

                bottomChrome
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissKeyboard()
            }
        )
        .preferredColorScheme(.dark)
        .onAppear {
            if aiNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                aiNameDraft = defaultAIName
            }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 14) {
            pageIndicator

            Button(action: handlePrimaryAction) {
                Text(primaryButtonTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.black.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SecretaryTheme.darkOrange)
                    )
            }
            .buttonStyle(.plain)
            .disabled(primaryButtonDisabled)
            .opacity(primaryButtonDisabled ? 0.45 : 1)
            .padding(.horizontal, 22)
        }
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    SecretaryTheme.darkBackground.opacity(0.72),
                    SecretaryTheme.darkBackground.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(0...lastPageIndex, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(
                        index == page
                            ? SecretaryTheme.darkOrange
                            : SecretaryTheme.white.opacity(0.22)
                    )
                    .frame(width: index == page ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: page)
            }
        }
    }

    private var primaryButtonTitle: String {
        page == lastPageIndex ? "Start using Unify" : "Continue"
    }

    private var primaryButtonDisabled: Bool {
        page == lastPageIndex && resolvedAIName.isEmpty
    }

    private var resolvedAIName: String {
        let trimmed = aiNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultAIName }
        return trimmed
    }

    private func handlePrimaryAction() {
        if page == 4 {
            UserDefaults.standard.set(true, forKey: UnifyOnboardingKeys.sawAutonomyExplainer)
        }

        if page < lastPageIndex {
            dismissKeyboard()
            withAnimation(.easeInOut(duration: 0.22)) {
                page += 1
            }
            return
        }

        completeOnboarding()
    }

    private func completeOnboarding() {
        dismissKeyboard()

        let name = resolvedAIName
        companionName = name

        let ud = UserDefaults.standard
        ud.set(name, forKey: UnifyOnboardingKeys.aiName)
        ud.set(name, forKey: "onboarding.companionName")
        ud.set(2, forKey: UnifyOnboardingKeys.completedVersion)
        ud.set(true, forKey: UnifyOnboardingKeys.secretaryMode)

        services.chat.enterSecretaryRuntimeMode()

        withAnimation(.easeInOut(duration: 0.25)) {
            hasOnboarded = true
        }
    }

    private func dismissKeyboard() {
        isAINameFocused = false

    #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    #endif
    }
}

// MARK: - Shared layout

private enum UnifyOnboardingLayout {
    static let horizontalPadding: CGFloat = 30
    static let contentMaxWidth: CGFloat = 330

    static let titleFont = Font.system(size: 29, weight: .bold)
    static let subtitleFont = Font.system(size: 16.5, weight: .regular)
    static let supportingFont = Font.system(size: 15.5, weight: .regular)
    static let quoteFont = Font.system(size: 15.5, weight: .regular)
    static let fieldLabelFont = Font.system(size: 15, weight: .semibold)

    static let iconSizeCompact: CGFloat = 76
    static let iconSizeRegular: CGFloat = 96
}

/// Large centered SF Symbol.
/// No silver holder/background. Icon only, larger proportion like the reference screens.
private struct UnifyOnboardingHeroIcon: View {
    let systemName: String
    var diameter: CGFloat = UnifyOnboardingLayout.iconSizeRegular

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: diameter, weight: .ultraLight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
            .frame(width: diameter + 20, height: diameter + 20)
            .accessibilityHidden(true)
    }
}

private struct UnifyOnboardingTextStack: View {
    let title: String
    let subtitle: String
    let supportingLines: [String]
    let quotes: [String]

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(UnifyOnboardingLayout.titleFont)
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            Text(subtitle)
                .font(UnifyOnboardingLayout.subtitleFont)
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if !quotes.isEmpty {
                VStack(spacing: 10) {
                    ForEach(quotes, id: \.self) { quote in
                        Text("“\(quote)”")
                            .font(UnifyOnboardingLayout.quoteFont)
                            .italic()
                            .foregroundStyle(SecretaryTheme.darkSecondaryText.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 24)
            }

            if !supportingLines.isEmpty {
                VStack(spacing: 10) {
                    ForEach(supportingLines, id: \.self) { line in
                        Text(line)
                            .font(UnifyOnboardingLayout.supportingFont)
                            .foregroundStyle(SecretaryTheme.darkSecondaryText.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: UnifyOnboardingLayout.contentMaxWidth)
    }
}

/// Centered content block:
/// spacer → icon → title/subtitle/supporting copy → optional input → spacer
private struct UnifyOnboardingPageScaffold<Extra: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconDiameter: CGFloat = UnifyOnboardingLayout.iconSizeRegular
    var denseContent: Bool = false
    var supportingLines: [String] = []
    var quotes: [String] = []
    @ViewBuilder var extraContent: () -> Extra

    init(
        icon: String,
        title: String,
        subtitle: String,
        iconDiameter: CGFloat = UnifyOnboardingLayout.iconSizeRegular,
        denseContent: Bool = false,
        supportingLines: [String] = [],
        quotes: [String] = [],
        @ViewBuilder extraContent: @escaping () -> Extra = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconDiameter = iconDiameter
        self.denseContent = denseContent
        self.supportingLines = supportingLines
        self.quotes = quotes
        self.extraContent = extraContent
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700 || denseContent
            let iconSize = compact ? UnifyOnboardingLayout.iconSizeCompact : iconDiameter
            let iconGap = compact ? 24.0 : 30.0
            let extraTopGap = compact ? 18.0 : 24.0

            VStack(spacing: 0) {
                Spacer(minLength: compact ? 22 : 34)

                VStack(spacing: 0) {
                    UnifyOnboardingHeroIcon(systemName: icon, diameter: iconSize)
                        .padding(.bottom, iconGap)

                    UnifyOnboardingTextStack(
                        title: title,
                        subtitle: subtitle,
                        supportingLines: supportingLines,
                        quotes: quotes
                    )

                    extraContent()
                        .padding(.top, extraTopGap)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, UnifyOnboardingLayout.horizontalPadding)

                Spacer(minLength: compact ? 22 : 34)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Pages

private struct UnifyOnboardingOnePersonPage: View {
    var body: some View {
        UnifyOnboardingPageScaffold(
            icon: "person.crop.circle.badge.checkmark",
            title: "One Person, One AI.",
            subtitle: "Your AI lives on your device and connects you to other people and providers through Unify’s federated network."
        )
    }
}

private struct UnifyOnboardingSearchPage: View {
    var body: some View {
        UnifyOnboardingPageScaffold(
            icon: "scope",
            title: "Search Naturally",
            subtitle: "\"Find me a wedding photographer in Toronto next Saturday under $800.\" Your AI can search and inquire across people and services."
        )
    }
}

private struct UnifyOnboardingSuggestionsPage: View {
    var body: some View {
        UnifyOnboardingPageScaffold(
            icon: "sparkles.rectangle.stack",
            title: "Relevant Opportunities",
            subtitle: "Set up your public profile, your AI can bring people and opportunities based on your interests."
        )
    }
}

private struct UnifyOnboardingSellingPage: View {
    var body: some View {
        UnifyOnboardingPageScaffold(
            icon: "storefront",
            title: "Start Selling",
            subtitle: "Set up your commercial profile. No content hustle, no paid ranking. Your AI can help reply to inquiries."
        )
    }
}

private struct UnifyOnboardingPrivateMessagingPage: View {
    var body: some View {
        UnifyOnboardingPageScaffold(
            icon: "lock.shield",
            title: "End-To-End Encrypted Messaging",
            subtitle: "Your messages are encrypted. Unify only helps deliver them."
        )
    }
}

private struct UnifyOnboardingNameAIPage: View {
    @Binding var aiName: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        UnifyOnboardingPageScaffold(
            icon: "seal",
            title: "Name your AI",
            subtitle: "Give your AI a name before you start.",
            iconDiameter: UnifyOnboardingLayout.iconSizeCompact,
            denseContent: true
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Name")
                    .font(UnifyOnboardingLayout.fieldLabelFont)
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                TextField("Uni", text: $aiName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused(isFocused)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background {
                        UnifyGlassTextFieldChrome(cornerRadius: 16)
                    }
            }
            .frame(maxWidth: UnifyOnboardingLayout.contentMaxWidth, alignment: .leading)
        }
    }
}

import SwiftUI
import PhotosUI
import UIKit
import UserNotifications
import AnumCore

/// Compact offer photo strip inside Profile “Your offering” (presentation only).
private enum ProfileShellOfferPhotosStripMetrics {
    static let slotHeight: CGFloat = 84
    static let slotWidth: CGFloat = 78
    static let slotCornerRadius: CGFloat = 18
    static let stripSpacing: CGFloat = 10
}

/// Unify profile tab shell: dark premium layout, reads `AppServices.sellerWorkspace` for display.
/// Hero identity is tappable for a quick public-profile edit sheet; Guardians / Special Thanks / Help use the same half-height sheet pattern as Offering — Required / Additional.
struct UnifyWorkspaceProfileShellView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    /// When `false`, the tab is retained off-screen (`SecretaryWorkspaceView`); refresh when it becomes active so hydration is not stuck on an early no-node no-op.
    var isTabActive: Bool = true

    /// StoreKit guardianship surface (`GuardiansContentView`); started on profile appear.
    @StateObject private var supportStore = SupportStore()

    @State private var isPublicProfileQuickEditPresented = false
    @State private var isSavingQuickProfile = false
    @State private var quickProfileSaveError: String?

    @State private var draftDisplayName = ""
    @State private var draftHeadline = ""
    @State private var draftAboutYou = ""
    @State private var draftLookingFor = ""
    @State private var draftInterests = ""
    @State private var draftCurrentRoles = ""
    @State private var draftRegion = ""

    @State private var profilePhotoPickerItem: PhotosPickerItem?
    @State private var isUploadingProfilePhoto = false
    @State private var profilePhotoError: String?

    @State private var offerHeroPhotoPickerItem: PhotosPickerItem?
    @State private var offerGalleryPhotoPickerItem: PhotosPickerItem?
    @State private var isOfferGalleryReplacePickerPresented = false
    @State private var offerGalleryReplacePickerItem: PhotosPickerItem?
    @State private var pendingOfferGalleryReplace: (index: Int, rawURL: String)?
    @State private var isUploadingOfferHeroImage = false
    @State private var isUploadingOfferGalleryImage = false
    @State private var offerMediaError: String?

    @State private var photoCropSourceImage: UIImage?
    @State private var showPhotoCropper = false
    @State private var pendingPhotoCropTarget: ProfileShellPhotoCropTarget?

    @State private var isOfferingRequiredSheetPresented = false
    @State private var offeringSheetAdditionalInitiallyExpanded = false
    @State private var isSecretaryStyleSettingsPresented = false
    @State private var isSecretaryAutoInquiryRepliesPresented = false
    @State private var isGuardiansSheetPresented = false
    @State private var isSpecialThanksSheetPresented = false
    @State private var isHelpSheetPresented = false
    @State private var isDataPrivacySheetPresented = false
    @State private var isSavingOfferingRequired = false
    @State private var isSavingOfferingAdditional = false
    @State private var offeringRequiredSaveError: String?
    @State private var serviceAreaResolveNotice: String?
    @State private var offeringAdditionalSaveError: String?

    @State private var offeringReqTitle = ""
    @State private var offeringReqSummary = ""
    @State private var offeringReqCategory = ""
    @State private var offeringReqRegionTags = ""
    @State private var offeringReqTags = ""

    @State private var offAddContactName = ""
    @State private var offAddBusinessName = ""
    @State private var offAddEmail = ""
    @State private var offAddPhone = ""
    @State private var offAddWebsite = ""
    @State private var offAddPreferredMethod = ""
    @State private var offAddContactAvailability = ""
    @State private var offAddServiceAddress = ""
    @State private var offAddPriceDisplay = ""
    @State private var offAddPriceMin = ""
    @State private var offAddPriceMax = ""
    @State private var offAddCurrency = ""
    @State private var offAddPriceUnit = ""
    @State private var offAddPackages = ""
    @State private var offAddServiceAreaNote = ""
    @State private var offAddAvailabilityNote = ""
    @State private var offAddMinimumEngagement = ""
    @State private var offAddCancellation = ""
    @State private var offAddRefund = ""
    @State private var offAddWarranty = ""
    @State private var offAddRequiredInputs = ""
    @State private var offAddFAQs = ""
    @State private var offAddAutoPricing = false
    @State private var offAddAutoAvailability = false
    @State private var offAddAutoPolicies = true
    @State private var offAddAutoServiceArea = true
    @State private var offAddAutoFAQs = true
    @State private var offAddAutoCustomQuote = true

    @State private var isPublicationFooterBusy = false
    @State private var publicationPreparedError: String?

    /// Profile “Your offering” notification row: iOS guidance alerts only (delivery state lives on `AppServices`).
    @State private var isApplyingSecretaryPushDeliveryToggle = false
    @State private var notificationPermissionV1Alert: NotificationPermissionV1Alert?
    @State private var serverDisableErrorMessage: String?

    /// True after the user opens Public Profile quick edit until a successful save (used for publish dirty detection only).
    @State private var publicProfileQuickEditOpenedSinceLastSave = false
    /// True after the user opens Offering — Required until a successful save.
    @State private var offeringRequiredOpenedSinceLastSave = false
    /// True after the user opens Offering — Additional until a successful save.
    @State private var offeringAdditionalOpenedSinceLastSave = false

    /// Profile-level placeholder titles blocked from publish (case-insensitive, trimmed). Matches `createDraftOffer` / old editor defaults in this surface.
    private static let invalidPublishOfferTitlesLowercased: Set<String> = [
        "new offer",
        "active offer",
        "untitled offer",
    ]

    private var workspace: ExchangeModels.SellerWorkspaceSummary? {
        services.sellerWorkspace
    }

    private var sellerValidationIssues: [ExchangeSellerValidationIssue] {
        services.sellerValidationIssues
    }

    var body: some View {
        GeometryReader { geo in
            // Match main tabs (e.g. Threads): scroll content only. `SecretaryWorkspaceView` already
            // paints `UnifyIceShellBackground()` behind the tab stack; nesting it here added an inner
            // `GeometryReader` + `ignoresSafeArea()` pass that could fight this `GeometryReader`’s
            // fixed frame on first layout (zoomed/clipped until a sheet forced relayout).
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        profileScreenTitle

                        profileHeader
                            .padding(.top, 10)
                    }
                    .modifier(ProfileRootColumnWidthCap(measuredWidth: geo.size.width))
                    .padding(.horizontal, 16)
                    .padding(.top, geo.safeAreaInsets.top + UnifyMainTabScrollLayout.paddingBelowSafeArea)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            publicProfileCard
                                .padding(.top, 20)

                            yourOfferingSection
                                .padding(.top, 20)

                            secretarySettingsCard
                                .padding(.top, 20)

                            settingsSecondaryGroupedCard
                                .padding(.top, 20)

                            #if DEBUG
                            searchIntentSmokeAuditCard
                                .padding(.top, 20)

                            appSearchSmokeAuditCard
                                .padding(.top, 20)

                            retrievalE2ESmokeCard
                                .padding(.top, 20)

                            multilingualE2ESmokeCard
                                .padding(.top, 20)

                            multilingualLiveSubsetSmokeCard
                                .padding(.top, 20)

                            requesterGapSmokeAuditCard
                                .padding(.top, 20)

                            requesterComposeSmokeAuditCard
                                .padding(.top, 20)

                            providerInquiryAnswerSmokeAuditCard
                                .padding(.top, 20)

                            directChatReplySmokeAuditCard
                                .padding(.top, 20)
                            #endif
                        }
                        // Wide intrinsic width from the horizontal media strip can expand this column past the viewport;
                        // cap only once `GeometryReader` reports a real width (never cap on ~0 first pass).
                        .modifier(ProfileRootColumnWidthCap(measuredWidth: geo.size.width))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            supportStore.start()
            services.guardianSupporterPresentationForPublish = { [supportStore] in
                ExchangeSupporterPresentation.guardianCrownIfActive(supportStore.isSupportingMonthly)
            }
            #if DEBUG
            logGuardianCrownOwnProfile(context: "onAppear")
            #endif
            profileShellLogRenderState(context: "viewAppear")
            profileShellLogOfferMediaState(context: "viewAppear")
        }
        .onChange(of: supportStore.isSupportingMonthly) { _, isActive in
            #if DEBUG
            logGuardianCrownOwnProfile(context: "entitlementChange isActive=\(isActive)")
            #endif
            Task {
                await services.updateOwnerGuardianSupporterPresentation(isActive: isActive)
                await services.publishSellerSurfaceNow()
            }
        }
        .onChange(of: supportStore.isMonthlyAutoRenewOn) { _, _ in
            #if DEBUG
            logGuardianCrownOwnProfile(context: "autoRenewChange")
            #endif
        }
        .onChange(of: services.sellerWorkspaceHydrationGeneration) { oldGeneration, newGeneration in
            let loadingBefore = profileHeaderShowsHydrationPlaceholder
            #if DEBUG
            print(
                "[ProfileViewHydrationObserved] generation=\(newGeneration) " +
                "loadingBefore=\(loadingBefore) loadingAfter=\(profileHeaderShowsHydrationPlaceholder) " +
                "oldGeneration=\(oldGeneration)"
            )
            #endif
            profileShellLogRenderState(context: "hydrationGeneration")
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            services.setSecretaryProfileTabActive(true)
            profileShellLogRenderState(context: "taskActive")
            if services.sellerWorkspace != nil {
                profileShellLogRenderState(context: "taskReuseWorkspace")
                return
            }
            await services.refreshSellerWorkspace()
            profileShellLogRenderState(context: "taskAfterRefresh")
        }
        .onChange(of: isTabActive) { _, active in
            guard active else { return }
            services.setSecretaryProfileTabActive(true)
            profileShellLogRenderState(context: "tabBecameActive")
            if services.sellerWorkspace != nil {
                return
            }
            Task {
                await services.refreshSellerWorkspace()
                profileShellLogRenderState(context: "tabActiveAfterRefresh")
            }
        }
        .onChange(of: services.sellerWorkspace?.offers.count) { _, _ in
            #if DEBUG
            profileShellLogOfferMediaState(context: "workspaceOffersChanged")
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                await services.refreshSecretaryPushNotificationDeliveryState()
            }
        }
        .alert(item: $notificationPermissionV1Alert) { kind in
            notificationPermissionV1AlertBody(for: kind)
        }
        .alert(
            "Couldn’t update notifications",
            isPresented: Binding(
                get: { serverDisableErrorMessage != nil },
                set: { if !$0 { serverDisableErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    serverDisableErrorMessage = nil
                }
            },
            message: {
                Text(serverDisableErrorMessage ?? "")
            }
        )
        .sheet(isPresented: $isPublicProfileQuickEditPresented) {
            PublicProfileQuickEditSheet(
                isPresented: $isPublicProfileQuickEditPresented,
                draftDisplayName: $draftDisplayName,
                draftHeadline: $draftHeadline,
                draftAboutYou: $draftAboutYou,
                draftLookingFor: $draftLookingFor,
                draftInterests: $draftInterests,
                draftCurrentRoles: $draftCurrentRoles,
                draftRegion: $draftRegion,
                isSaving: $isSavingQuickProfile,
                saveError: $quickProfileSaveError,
                onSave: { await savePublicProfileQuickEdit() }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isOfferingRequiredSheetPresented) {
            OfferingRequiredSheet(
                isPresented: $isOfferingRequiredSheetPresented,
                draftTitle: $offeringReqTitle,
                draftSummary: $offeringReqSummary,
                draftCategory: $offeringReqCategory,
                draftRegionTags: $offeringReqRegionTags,
                draftTags: $offeringReqTags,
                contactName: $offAddContactName,
                contactBusinessName: $offAddBusinessName,
                contactEmail: $offAddEmail,
                contactPhone: $offAddPhone,
                contactWebsite: $offAddWebsite,
                contactPreferredMethod: $offAddPreferredMethod,
                contactAvailabilityNote: $offAddContactAvailability,
                contactServiceAddressOrArea: $offAddServiceAddress,
                priceDisplay: $offAddPriceDisplay,
                priceMinText: $offAddPriceMin,
                priceMaxText: $offAddPriceMax,
                currency: $offAddCurrency,
                priceUnit: $offAddPriceUnit,
                packagesText: $offAddPackages,
                serviceAreaNote: $offAddServiceAreaNote,
                availabilityNote: $offAddAvailabilityNote,
                minimumEngagement: $offAddMinimumEngagement,
                cancellationPolicy: $offAddCancellation,
                refundPolicy: $offAddRefund,
                warrantyPolicy: $offAddWarranty,
                requiredInputsText: $offAddRequiredInputs,
                faqsText: $offAddFAQs,
                initialAdditionalExpanded: offeringSheetAdditionalInitiallyExpanded,
                isSavingRequired: $isSavingOfferingRequired,
                isSavingAdditional: $isSavingOfferingAdditional,
                requiredSaveError: $offeringRequiredSaveError,
                additionalSaveError: $offeringAdditionalSaveError,
                serviceAreaNotice: $serviceAreaResolveNotice,
                onSave: {
                    await saveOfferingRequiredSheet()
                    await saveOfferingAdditionalSheet()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isGuardiansSheetPresented) {
            ProfileGuardiansSheet(isPresented: $isGuardiansSheetPresented, store: supportStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSpecialThanksSheetPresented) {
            ProfileSpecialThanksSheet(isPresented: $isSpecialThanksSheetPresented)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isHelpSheetPresented) {
            ProfileHelpSheet(isPresented: $isHelpSheetPresented)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isDataPrivacySheetPresented) {
            ProfileDataPrivacySheet(isPresented: $isDataPrivacySheetPresented)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSecretaryStyleSettingsPresented) {
            SecretaryStyleSettingsView {
                isSecretaryStyleSettingsPresented = false
            }
            .environmentObject(services)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSecretaryAutoInquiryRepliesPresented) {
            SecretaryAutoInquiryRepliesSheet(
                isPresented: $isSecretaryAutoInquiryRepliesPresented,
                autoAnswerPricing: $offAddAutoPricing,
                autoAnswerAvailability: $offAddAutoAvailability,
                autoAnswerPolicies: $offAddAutoPolicies,
                autoAnswerServiceArea: $offAddAutoServiceArea,
                autoAnswerFAQs: $offAddAutoFAQs,
                autoAnswerCustomQuote: $offAddAutoCustomQuote,
                isSaving: $isSavingOfferingAdditional,
                saveError: $offeringAdditionalSaveError,
                onSave: { await saveOfferingAdditionalSheet() }
            )
            .environmentObject(services)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sharedPhotoCropperCover(
            isPresented: $showPhotoCropper,
            sourceImage: photoCropSourceImage,
            preset: profileShellPhotoCropPreset,
            title: photoCropTitle,
            onCancel: { dismissProfileShellPhotoCropper() },
            onUse: { cropped in
                Task { @MainActor in
                    await applyProfileShellCroppedPhoto(cropped)
                }
            }
        )
    }

    private enum ProfileShellPhotoCropTarget: Equatable {
        case profile
        case offerHero
        case offerGalleryNew
        case offerGalleryReplace(index: Int, rawURL: String)
    }

    private var photoCropTitle: String {
        switch pendingPhotoCropTarget {
        case .profile: return "Adjust Profile Photo"
        case .offerHero: return "Adjust Main Photo"
        case .offerGalleryNew: return "Adjust Gallery Photo"
        case .offerGalleryReplace: return "Replace Gallery Photo"
        case .none: return "Adjust Photo"
        }
    }

    private var profileShellPhotoCropPreset: SharedPhotoCropperView.Preset {
        switch pendingPhotoCropTarget {
        case .profile:
            return .profileAvatar
        case .offerHero, .offerGalleryNew, .offerGalleryReplace:
            return .profileMediaStrip
        case .none:
            return .profileMediaStrip
        }
    }

    /// Same large title lane as `SecretaryInboundView.chatsHeader` so tab switches do not jump vertically.
    private var profileScreenTitle: some View {
        HStack(alignment: .center) {
            Text("Profile")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Header (avatar → photo picker + upload; text → quick edit sheet)

    private var profileHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                GuardianCrownAvatarFrame(
                    showsCrown: supportStore.isSupportingMonthly,
                    avatarDiameter: ProfileShellLayout.heroAvatarDiameter,
                    debugSurface: "ownProfile",
                
                    debugProfileID: workspace?.publicProfile?.profile.id
                ) {
                    profileAvatarPhotoPicker
                }

                if let profilePhotoError, !profilePhotoError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(profilePhotoError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                }

                if profileHeaderShowsHydrationPlaceholder {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                        Text("Loading profile…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(SecretaryTheme.darkGlass.opacity(0.5))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SecretaryTheme.darkStroke.opacity(0.55), lineWidth: 1)
                    }
                } else {
                    VStack(spacing: 6) {
                        Text(resolvedDisplayName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)

                        Text(resolvedPublicHeadline)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Public profile. \(resolvedDisplayName). \(resolvedPublicHeadline)")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
        }
    }

    private var profileAvatarPhotoPicker: some View {
        PhotosPicker(
            selection: $profilePhotoPickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            ZStack {
                avatarView
                    .frame(width: ProfileShellLayout.heroAvatarDiameter, height: ProfileShellLayout.heroAvatarDiameter)
                    .clipped()

                Group {
                    if isUploadingProfilePhoto {
                        ProgressView()
                            .scaleEffect(0.85)
                            .tint(SecretaryTheme.darkOrange)
                            .padding(8)
                            .background {
                                UnifyGlassIconDisk(diameter: 36, strokeOpacity: 0.95)
                            }
                    } else if resolvedAvatarURL == nil {
                        // No URL: prominent empty-state camera (picker still covers full orb).
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                            .padding(8)
                            .background {
                                UnifyGlassIconDisk(diameter: 36, strokeOpacity: 0.95)
                            }
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: ProfileShellLayout.heroAvatarDiameter, height: ProfileShellLayout.heroAvatarDiameter)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(SecretaryTheme.darkStroke, lineWidth: 1)
            }
            .shadow(color: SecretaryTheme.darkShadow.opacity(0.35), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isUploadingProfilePhoto)
        .accessibilityLabel("Change profile photo")
        .onChange(of: profilePhotoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                await presentProfileShellPhotoCrop(from: newItem, target: .profile)
                profilePhotoPickerItem = nil
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = resolvedAvatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    avatarPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    avatarPlaceholder
                @unknown default:
                    avatarPlaceholder
                }
            }
            .id(url.absoluteString)
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            UnifyGlassIconDisk(diameter: ProfileShellLayout.heroAvatarDiameter, strokeOpacity: 0.42)

            profileShellDottedCircleInset()
        }
    }


    // MARK: - Profile slot chrome matching inbound quick-chat slots

    private func profileShellDottedRoundedInset(cornerRadius: CGFloat, padding: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                SecretaryTheme.white.opacity(0.20),
                style: StrokeStyle(lineWidth: 1.1, dash: [5, 4])
            )
            .padding(padding)
    }

    private func profileShellDottedCircleInset(padding: CGFloat = 9) -> some View {
        Circle()
            .strokeBorder(
                SecretaryTheme.white.opacity(0.20),
                style: StrokeStyle(lineWidth: 1.1, dash: [5, 4])
            )
            .padding(padding)
    }

    private func profileShellGalleryNumberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(SecretaryTheme.darkMutedText)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    // MARK: - Media (primary offer hero + gallery; profile avatar stays public profile primary)

    private var isOfferMediaUploadBusy: Bool {
        isUploadingOfferHeroImage || isUploadingOfferGalleryImage
    }

    /// Trailing strip slots after hero (4 wide → 5 slots total with hero); mirrors strip layout but hit-testable.
    private enum OfferMediaStripTrailingKind: Equatable {
        case gallery(index: Int, rawURL: String)
        case addGallery
        case overflowMore(Int)
        case pad
    }

    /// Trailing strip slots (4 → 5 total with Main): gallery add is always slot 2; gallery images follow.
    private func offerMediaStripTrailingKinds(galleryStrings: [String]) -> [OfferMediaStripTrailingKind] {
        let maxVisibleGalleryImages = 4
        let maxTrailing = 1 + maxVisibleGalleryImages // add button + 4 gallery photos

        var slots: [OfferMediaStripTrailingKind] = []
        slots.append(.addGallery)

        let galleryCount = galleryStrings.count

        if galleryCount <= maxVisibleGalleryImages {
            for index in 0..<galleryCount {
                slots.append(.gallery(index: index, rawURL: galleryStrings[index]))
            }

            while slots.count < maxTrailing {
                slots.append(.pad)
            }

            return slots
        }

        let visibleGalleryCount = maxVisibleGalleryImages - 1

        for index in 0..<visibleGalleryCount {
            slots.append(.gallery(index: index, rawURL: galleryStrings[index]))
        }

        slots.append(.overflowMore(galleryCount - visibleGalleryCount))

        while slots.count < maxTrailing {
            slots.append(.pad)
        }

        return slots
    }

    private func profileShellTrimmedGalleryStrings(from offer: ExchangeOffer?) -> [String] {
        offer?.galleryImageURLs.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } ?? []
    }

    private func profileShellMainCommercialRawURL(from offer: ExchangeOffer?) -> String? {
        let trimmed = offer?.primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func offerMediaStripPadTile(opacity: Double) -> some View {
        let cornerRadius = ProfileShellOfferPhotosStripMetrics.slotCornerRadius

        return ZStack {
            UnifyGlassPlateBackground(cornerRadius: cornerRadius)

            profileShellDottedRoundedInset(cornerRadius: cornerRadius, padding: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.7), lineWidth: 1)
        )
        .opacity(opacity)
    }

    @ViewBuilder
    private var mediaSection: some View {
        offerMediaAndPhotosCard
            .onChange(of: offerHeroPhotoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task { @MainActor in
                    await presentProfileShellPhotoCrop(from: newItem, target: .offerHero)
                    offerHeroPhotoPickerItem = nil
                }
            }
            .onChange(of: offerGalleryPhotoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task { @MainActor in
                    await presentProfileShellPhotoCrop(from: newItem, target: .offerGalleryNew)
                    offerGalleryPhotoPickerItem = nil
                }
            }
            .onChange(of: offerGalleryReplacePickerItem) { _, newItem in
                guard let newItem else { return }
                guard let pending = pendingOfferGalleryReplace else { return }
                let replaceTarget: ProfileShellPhotoCropTarget = .offerGalleryReplace(
                    index: pending.index,
                    rawURL: pending.rawURL
                )
                Task { @MainActor in
                    await presentProfileShellPhotoCrop(from: newItem, target: replaceTarget)
                    offerGalleryReplacePickerItem = nil
                    pendingOfferGalleryReplace = nil
                }
            }
            .photosPicker(
                isPresented: $isOfferGalleryReplacePickerPresented,
                selection: $offerGalleryReplacePickerItem,
                matching: .images
            )
    }

    private var offerMediaAndPhotosCard: some View {
        let offer = primaryOfferFromWorkspace()?.offer
        let mainRawURL = profileShellMainCommercialRawURL(from: offer)
        let heroURL = profileShellResolvedPublicImageURL(from: mainRawURL)
        let galleryStrings = profileShellTrimmedGalleryStrings(from: offer)
        let trailingKinds = offerMediaStripTrailingKinds(galleryStrings: galleryStrings)
        let orderedCount = ExchangeOffer.limitedOrderedOfferImageURLs(
            primaryImageURL: offer?.primaryImageURL,
            galleryImageURLs: offer?.galleryImageURLs ?? []
        ).count
        let atImageCap = orderedCount >= ExchangeOffer.maxPublicOfferImageCount
        let slotHeight = ProfileShellOfferPhotosStripMetrics.slotHeight

        return VStack(alignment: .leading, spacing: 8) {
            if let offerMediaError, !offerMediaError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(offerMediaError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ProfileShellOfferPhotosStripMetrics.stripSpacing) {
                    offerMediaStripHeroSlot(
                        heroURL: heroURL,
                        hasMainCommercial: mainRawURL != nil
                    )

                    ForEach(Array(trailingKinds.enumerated()), id: \.offset) { _, kind in
                        offerMediaStripTrailingSlot(kind: kind, offer: offer)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: slotHeight)
            .clipped()

            if atImageCap {
                Text("Image limit reached")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onAppear {
            #if DEBUG
            profileShellLogProfileMediaSlots(
                context: "offerMediaCardAppear",
                offer: offer,
                mainRawURL: mainRawURL,
                heroURL: heroURL,
                galleryStrings: galleryStrings,
                trailingKinds: trailingKinds
            )
            #endif
        }
    }

    private func profileShellMediaStripPhotoLayer(url: URL?, placeholder: some View) -> some View {
        let slotShape = RoundedRectangle(
            cornerRadius: ProfileShellOfferPhotosStripMetrics.slotCornerRadius,
            style: .continuous
        )
        return ZStack {
            placeholder
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.clear
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .id(url.absoluteString)
            }
        }
        .profileShellOfferPhotosStripSlotLayout()
        .clipShape(slotShape)
    }

    @ViewBuilder
    private func offerMediaStripHeroSlot(heroURL: URL?, hasMainCommercial: Bool) -> some View {
        let slotShape = RoundedRectangle(cornerRadius: ProfileShellOfferPhotosStripMetrics.slotCornerRadius, style: .continuous)
        ZStack {
            profileShellMediaStripPhotoLayer(
                url: hasMainCommercial ? heroURL : nil,
                placeholder: offerMediaHeroPlaceholder
            )

            PhotosPicker(
                selection: $offerHeroPhotoPickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isOfferMediaUploadBusy || isUploadingProfilePhoto)

            offerMediaStripMainChrome(hasMainCommercial: hasMainCommercial)
                .allowsHitTesting(false)
            if hasMainCommercial {
                VStack {
                    HStack {
                        Button {
                            Task { @MainActor in
                                await clearOfferHeroImage()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    SecretaryTheme.darkPrimaryText,
                                    SecretaryTheme.darkShadow.opacity(0.65)
                                )
                                .padding(5)
                        }
                        .buttonStyle(.plain)
                        .disabled(isOfferMediaUploadBusy || isUploadingProfilePhoto)

                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 0)
                }
            }
            
            if isUploadingOfferHeroImage {
                ZStack {
                    slotShape
                        .fill(SecretaryTheme.darkGlass.opacity(0.5))
                    slotShape
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .opacity(0.42)
                }
                .allowsHitTesting(false)
                ProgressView()
                    .scaleEffect(0.95)
                    .tint(SecretaryTheme.darkOrange)
                    .allowsHitTesting(false)
            }
        }
        .profileShellOfferPhotosStripSlotLayout()
        .clipShape(slotShape)
        .overlay {
            slotShape.stroke(SecretaryTheme.darkStroke.opacity(0.7), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if hasMainCommercial {
                Button("Clear main image", role: .destructive) {
                    Task { @MainActor in
                        await clearOfferHeroImage()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func offerMediaStripMainChrome(hasMainCommercial: Bool) -> some View {
        if hasMainCommercial {
            VStack(spacing: 0) {
                Text("Main")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        UnifyGlassCapsuleChrome()
                    }
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(SecretaryTheme.darkStroke.opacity(0.65), lineWidth: 1)
                    )

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 6)
        } else {
            VStack(spacing: 8) {
                Text("Main")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .shadow(color: SecretaryTheme.darkShadow.opacity(0.35), radius: 2, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func offerMediaStripTrailingSlot(
        kind: OfferMediaStripTrailingKind,
        offer: ExchangeOffer?
    ) -> some View {
        switch kind {
        case .gallery(let index, let rawURL):
            offerMediaStripGalleryThumbnailSlot(
                galleryIndex: index,
                rawURL: rawURL,
                gallerySlotNumber: index + 1
            )
        case .addGallery:
            offerMediaStripAddGallerySlot(offer: offer)
        case .overflowMore(let hidden):
            offerMediaStripOverflowSlot(hiddenCount: hidden)
        case .pad:
            offerMediaStripPadTile(opacity: 1)
                .profileShellOfferPhotosStripSlotLayout()
        }
    }

    @ViewBuilder
    private func offerMediaStripGalleryThumbnailSlot(
        galleryIndex: Int,
        rawURL: String,
        gallerySlotNumber: Int
    ) -> some View {
        let slotShape = RoundedRectangle(cornerRadius: ProfileShellOfferPhotosStripMetrics.slotCornerRadius, style: .continuous)
        let url = profileShellResolvedPublicImageURL(from: rawURL)
        Button {
            pendingOfferGalleryReplace = (galleryIndex, rawURL)
            isOfferGalleryReplacePickerPresented = true
            #if DEBUG
            profileShellLogOfferMediaState(
                context: "galleryReplaceTap",
                tappedAction: "offerGalleryReplace(index:\(galleryIndex))",
                replaceIndex: galleryIndex
            )
            #endif
        } label: {
            ZStack {
                profileShellMediaStripPhotoLayer(
                    url: url,
                    placeholder: offerMediaGalleryPlaceholderTile
                )

                profileShellGalleryNumberBadge(gallerySlotNumber)
                    .allowsHitTesting(false)
                
                VStack {
                    HStack {
                        Button {
                            Task { @MainActor in
                                await removeOfferGalleryImage(removingRaw: rawURL)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    SecretaryTheme.darkPrimaryText,
                                    SecretaryTheme.darkShadow.opacity(0.65)
                                )
                                .padding(5)
                        }
                        .buttonStyle(.plain)
                        .disabled(isOfferMediaUploadBusy || isUploadingProfilePhoto)

                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 0)
                }
                
            }
        }
        .buttonStyle(.plain)
        .disabled(isOfferMediaUploadBusy || isUploadingProfilePhoto)
        .profileShellOfferPhotosStripSlotLayout()
        .clipShape(slotShape)
        .overlay {
            slotShape.stroke(SecretaryTheme.darkStroke.opacity(0.7), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Replace gallery photo") {
                pendingOfferGalleryReplace = (galleryIndex, rawURL)
                isOfferGalleryReplacePickerPresented = true
            }
            Button("Remove from gallery", role: .destructive) {
                Task { @MainActor in
                    await removeOfferGalleryImage(removingRaw: rawURL)
                }
            }
        }
    }

    @ViewBuilder
    private func offerMediaStripAddGallerySlot(offer: ExchangeOffer?) -> some View {
        let slotShape = RoundedRectangle(cornerRadius: ProfileShellOfferPhotosStripMetrics.slotCornerRadius, style: .continuous)
        ZStack {
            offerMediaStripPadTile(opacity: 1)

            Image(systemName: "plus")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .allowsHitTesting(false)

            PhotosPicker(
                selection: $offerGalleryPhotoPickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isOfferMediaUploadBusy || isUploadingProfilePhoto || !canAddOfferGalleryImage(offer: offer))

            if isUploadingOfferGalleryImage {
                ZStack {
                    slotShape
                        .fill(SecretaryTheme.darkGlass.opacity(0.5))
                    slotShape
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .opacity(0.42)
                }
                .allowsHitTesting(false)
                ProgressView()
                    .scaleEffect(0.9)
                    .tint(SecretaryTheme.darkOrange)
                    .allowsHitTesting(false)
            }
        }
        .profileShellOfferPhotosStripSlotLayout()
        .clipShape(slotShape)
        .overlay {
            slotShape.stroke(SecretaryTheme.darkStroke.opacity(0.7), lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private func offerMediaStripOverflowSlot(hiddenCount: Int) -> some View {
        let slotShape = RoundedRectangle(cornerRadius: ProfileShellOfferPhotosStripMetrics.slotCornerRadius, style: .continuous)
        return ZStack {
            UnifyGlassPlateBackground(cornerRadius: ProfileShellOfferPhotosStripMetrics.slotCornerRadius)
            slotShape
                .stroke(SecretaryTheme.darkStroke, lineWidth: 1)
            Text("+\(hiddenCount)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
        }
        .profileShellOfferPhotosStripSlotLayout()
    }

    private var offerMediaHeroPlaceholder: some View {
        let cornerRadius = ProfileShellOfferPhotosStripMetrics.slotCornerRadius
        return ZStack {
            UnifyGlassPlateBackground(cornerRadius: cornerRadius)

            profileShellDottedRoundedInset(cornerRadius: cornerRadius, padding: 3)
        }
    }

    private var offerMediaGalleryPlaceholderTile: some View {
        let cornerRadius = ProfileShellOfferPhotosStripMetrics.slotCornerRadius
        return ZStack {
            UnifyGlassPlateBackground(cornerRadius: cornerRadius)

            profileShellDottedRoundedInset(cornerRadius: cornerRadius, padding: 3)
        }
    }

    /// Resolves persisted offer/profile media strings for `AsyncImage` (https, schemeless host, federation-relative paths).
    private func profileShellResolvedPublicImageURL(from raw: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let normalized = WorkThreadLeadImageURLNormalizer.normalizedChain(from: [trimmed])
        if let first = normalized.first, let url = URL(string: first) {
            return url
        }

        if trimmed.hasPrefix("/") {
            let base = ExchangeBootstrap.resolvedFederationBaseURL()
            if let url = URL(string: trimmed, relativeTo: base)?.absoluteURL {
                return url
            }
        }

        return nil
    }

    private func profileShellLogOfferMediaState(
        context: String,
        tappedAction: String? = nil,
        replaceIndex: Int? = nil
    ) {
        #if DEBUG
        let offer = primaryOfferFromWorkspace()?.offer
        let mainRawURL = profileShellMainCommercialRawURL(from: offer)
        let galleryStrings = profileShellTrimmedGalleryStrings(from: offer)
        let trailingKinds = offerMediaStripTrailingKinds(galleryStrings: galleryStrings)
        profileShellLogProfileMediaSlots(
            context: context,
            offer: offer,
            mainRawURL: mainRawURL,
            heroURL: profileShellResolvedPublicImageURL(from: mainRawURL),
            galleryStrings: galleryStrings,
            trailingKinds: trailingKinds,
            tappedAction: tappedAction,
            replaceIndex: replaceIndex
        )
        #endif
    }

    private func profileShellLogProfileMediaSlots(
        context: String,
        offer: ExchangeOffer?,
        mainRawURL: String?,
        heroURL: URL?,
        galleryStrings: [String],
        trailingKinds: [OfferMediaStripTrailingKind],
        tappedAction: String? = nil,
        replaceIndex: Int? = nil
    ) {
        #if DEBUG
        var slotOrder = ["main"]
        for kind in trailingKinds {
            switch kind {
            case .addGallery:
                slotOrder.append("galleryAdd")
            case .gallery(let index, _):
                slotOrder.append("galleryImage\(index + 1)")
            case .overflowMore(let hidden):
                slotOrder.append("overflowMore(\(hidden))")
            case .pad:
                slotOrder.append("pad")
            }
        }
        let galleryResolvableCount = galleryStrings.filter {
            profileShellResolvedPublicImageURL(from: $0) != nil
        }.count
        var message =
            "[ProfileMediaSlots] context=\(context) primaryOfferID=\(offer?.id ?? "nil") " +
            "hasMainURL=\(mainRawURL != nil) galleryCount=\(galleryStrings.count) " +
            "slotOrder=\(slotOrder) mainResolvable=\(heroURL != nil) " +
            "galleryResolvableCount=\(galleryResolvableCount)"
        if let tappedAction {
            message += " target=\(tappedAction)"
        }
        if let replaceIndex {
            message += " replaceIndex=\(replaceIndex)"
        }
        print(message)
        #endif
    }

    private func canAddOfferGalleryImage(offer: ExchangeOffer?) -> Bool {
        let primary = offer?.primaryImageURL
        let gallery = offer?.galleryImageURLs ?? []
        let count = ExchangeOffer.limitedOrderedOfferImageURLs(
            primaryImageURL: primary,
            galleryImageURLs: gallery,
            maxCount: ExchangeOffer.maxPublicOfferImageCount
        ).count
        return count < ExchangeOffer.maxPublicOfferImageCount
    }

    // MARK: - Public profile

    private var publicProfileCard: some View {
        VStack(spacing: 0) {
            ProfileShellOfferingTapRow(
                icon: "person.crop.circle",
                title: "Public profile",
                subtitle: publicProfileCardSubtitle,
                showRequiredCapsule: false,
                action: presentPublicProfileQuickEdit
            )
        }
        .padding(.vertical, 6)
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
    }

    private var publicProfileCardSubtitle: String {
        "Discovery identity, intro, and interests"
    }

    private func presentPublicProfileQuickEdit() {
        hydrateQuickProfileDraftFromWorkspace()
        quickProfileSaveError = nil
        publicProfileQuickEditOpenedSinceLastSave = true
        isPublicProfileQuickEditPresented = true
    }

    // MARK: - Your offering

    private var yourOfferingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            offeringSectionHeader

            mediaSection
                .padding(.top, 4)

            VStack(spacing: 0) {
                ProfileShellOfferingTapRow(
                    icon: "doc.text.fill",
                    title: "Offering",
                    subtitle: "Minimum details needed before publishing.",
                    showRequiredCapsule: offeringTitleMissingForBadge,
                    action: {
                        hydrateOfferingRequiredDrafts()
                        hydrateOfferingAdditionalDrafts()
                        offeringRequiredSaveError = nil
                        offeringAdditionalSaveError = nil
                        offeringRequiredOpenedSinceLastSave = true
                        offeringSheetAdditionalInitiallyExpanded = false
                        isOfferingRequiredSheetPresented = true
                    }
                )
            }
            .padding(.vertical, 6)

            Rectangle()
                .fill(SecretaryTheme.white.opacity(0.08))
                .frame(height: 1)
                .padding(.leading, 52)

            yourOfferingStatusFooter
        }
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
        .onAppear {
            Task { await services.refreshSecretaryPushNotificationDeliveryState() }
        }
        .onChange(of: isTabActive) { _, active in
            guard active else { return }
            Task { await services.refreshSecretaryPushNotificationDeliveryState() }
        }
    }

    private var offeringSectionHeader: some View {
        offeringSectionHeaderLabel
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private var offeringSectionHeaderLabel: some View {
        Text("Your offering")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkPrimaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Secretary settings

    private var secretarySettingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Secretary settings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ProfileShellOfferingTapRow(
                    icon: "text.quote",
                    title: "Style & instructions",
                    subtitle: "How your secretary represents you",
                    showRequiredCapsule: false,
                    action: {
                        isSecretaryStyleSettingsPresented = true
                    }
                )
                offeringDivider
                ProfileShellOfferingTapRow(
                    icon: "paperplane",
                    title: "Auto inquiry & replies",
                    subtitle: SecretaryStyleSettingsView.safeAutoFollowUpsDescription,
                    showRequiredCapsule: false,
                    action: {
                        hydrateOfferingAdditionalDrafts()
                        offeringAdditionalSaveError = nil
                        offeringAdditionalOpenedSinceLastSave = true
                        isSecretaryAutoInquiryRepliesPresented = true
                    }
                )
            }
            .padding(.vertical, 6)
        }
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
    }

    private struct OfferingReachabilitySnapshot: Equatable {
        let subtitle: String
    }

    /// Read-only discoverability copy for the Your offering footer (subtitle only in UI; no publication CTAs).
    private var offeringFooterReachabilitySnapshot: OfferingReachabilitySnapshot {
        guard let ws = workspace else {
            return OfferingReachabilitySnapshot(subtitle: "Finish setup to appear in discovery.")
        }

        let status = ws.publicationState?.status
        let hasValidation = !sellerValidationIssues.isEmpty

        if hasValidation {
            let detail = sellerValidationIssues.first?.summary
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let subtitle: String = detail.isEmpty
                ? "Fix blocking issues before discovery is reliable."
                : detail
            return OfferingReachabilitySnapshot(subtitle: subtitle)
        }

        if status == .failed {
            return OfferingReachabilitySnapshot(subtitle: "Fix the issue before discovery is reliable.")
        }

        let validOffer = profileShellPrimaryOfferIsValidForDiscovery(ws)
        if !validOffer {
            return OfferingReachabilitySnapshot(subtitle: "Add a real offer before people can find you.")
        }

        let pubPaused = status == .paused || status == .pendingUnpublish || status == .archived
        let profileHidden = (ws.publicProfile?.profile.visibility ?? .discoverable) != .discoverable
        if pubPaused || profileHidden {
            return OfferingReachabilitySnapshot(subtitle: "This surface is not currently discoverable.")
        }

        if status == .published || status == .stale {
            return OfferingReachabilitySnapshot(subtitle: "People can find and contact you.")
        }

        if status == .pendingPublish {
            return OfferingReachabilitySnapshot(subtitle: "Publishing your latest changes.")
        }

        if status == .draft || status == nil {
            return OfferingReachabilitySnapshot(subtitle: "Your offer is ready to publish.")
        }

        return OfferingReachabilitySnapshot(subtitle: "Finish setup to appear in discovery.")
    }

    /// Visible subtitle for the reachability row; uses snapshot copy with a neutral fallback when empty.
    private var offeringFooterReachabilitySubtitleLine: String {
        let trimmed = offeringFooterReachabilitySnapshot.subtitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "People can find and contact you."
    }

    private var yourOfferingStatusFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Reachability")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(offeringFooterReachabilitySubtitleLine)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Reachability. \(offeringFooterReachabilitySubtitleLine)")

                publicationFooterRightControl
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            offeringDivider

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 5) {
                    Text(notificationPermissionRowTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Get alerts when someone replies, sends a request, or needs your approval.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(notificationPermissionRowTitle). Get alerts when someone replies, sends a request, or needs your approval."
                )

                Toggle(isOn: notificationPermissionToggleBinding) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(SecretaryTheme.darkOrange)
                .disabled(isApplyingSecretaryPushDeliveryToggle)
                .opacity(isApplyingSecretaryPushDeliveryToggle ? 0.55 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            if let publicationPreparedError,
               !publicationPreparedError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    Color.clear
                        .frame(width: 28)
                    Text(publicationPreparedError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(SecretaryTheme.darkOrangeSoft.opacity(0.22))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(SecretaryTheme.darkOrange.opacity(0.28), lineWidth: 1)
                        }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .allowsHitTesting(true)
    }

    private var notificationPermissionRowTitle: String {
        services.secretaryPushNotificationDeliveryEffectiveOn ? "Notification Enabled" : "Notification Disabled"
    }

    private var notificationPermissionToggleBinding: Binding<Bool> {
        Binding(
            get: { services.secretaryPushNotificationDeliveryEffectiveOn },
            set: { newValue in
                Task { @MainActor in
                    await handleSecretaryPushDeliveryToggle(desiredOn: newValue)
                }
            }
        )
    }

    @MainActor
    private func handleSecretaryPushDeliveryToggle(desiredOn: Bool) async {
        isApplyingSecretaryPushDeliveryToggle = true
        let outcome = await services.applySecretaryProfileNotificationDeliveryToggle(desiredOn: desiredOn)
        isApplyingSecretaryPushDeliveryToggle = false
        switch outcome {
        case .none:
            break
        case .deniedInIOSSettings:
            notificationPermissionV1Alert = .deniedInSystemSettings
        case .serverDisableFailed(let message):
            serverDisableErrorMessage = message
        }
    }

    private func openUnifyAppSettingsFromNotificationRow() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func notificationPermissionV1AlertBody(for kind: NotificationPermissionV1Alert) -> Alert {
        switch kind {
        case .deniedInSystemSettings:
            Alert(
                title: Text("Notifications are disabled in iOS Settings."),
                message: Text("Enable notifications for Unify in Settings to receive secretary alerts."),
                primaryButton: .default(Text("Open Settings")) {
                    openUnifyAppSettingsFromNotificationRow()
                    Task { @MainActor in
                        await services.refreshSecretaryPushNotificationDeliveryState()
                    }
                },
                secondaryButton: .cancel(Text("OK")) {
                    Task { @MainActor in
                        await services.refreshSecretaryPushNotificationDeliveryState()
                    }
                }
            )
        }
    }

    private enum PublicationFooterAction: Equatable {
        case none
        case publishPreparedSurface
        case presentOfferingRequiredSheet
        case presentQuickProfileEditSheet
    }

    @ViewBuilder
    private var publicationFooterRightControl: some View {
        let pack = publicationFooterButtonPack
        switch pack.style {
        case .disabled(let title):
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.white.opacity(0.06))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.45), lineWidth: 1)
                )

        case .primary(let title, let attention):
            let canTap = pack.action != .none && !isPublicationFooterBusy
            Button {
                Task { @MainActor in
                    await handlePublicationFooterAction(pack.action)
                }
            } label: {
                Text(isPublicationFooterBusy ? "Working…" : title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(attention ? SecretaryTheme.darkPrimaryText : SecretaryTheme.darkSecondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(attention ? SecretaryTheme.darkOrange : SecretaryTheme.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                attention
                                    ? SecretaryTheme.darkOrange.opacity(0.5)
                                    : SecretaryTheme.darkStroke.opacity(0.45),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canTap)
        }
    }

    private struct PublicationFooterButtonPack {
        enum Style: Equatable {
            case disabled(String)
            case primary(String, attention: Bool)
        }

        let style: Style
        let action: PublicationFooterAction
    }

    /// Publication posture from `SellerWorkspaceSummary` only; actions stay on Profile sheets / prepared publish.
    private var publicationFooterButtonPack: PublicationFooterButtonPack {
        guard let ws = workspace else {
            return .init(style: .primary("Unavailable", attention: true), action: .presentOfferingRequiredSheet)
        }

        let hasProfile = ws.publicProfile != nil
        let hasOffers = !ws.offers.isEmpty
        let hasValidation = !sellerValidationIssues.isEmpty
        let status = ws.publicationState?.status

        switch status {
        case .published:
            return .init(style: .disabled("Published"), action: .none)

        case .pendingPublish:
            return .init(style: .disabled("Publishing"), action: .none)

        case .pendingUnpublish:
            return .init(style: .disabled("Withdrawing"), action: .none)

        case .paused, .archived:
            let title = profileShellTrimmedNonEmpty(ws.primaryCTAHint) ?? "Continue"
            return .init(style: .primary(title, attention: true), action: .presentOfferingRequiredSheet)

        case .failed:
            if hasProfile, hasOffers, !hasValidation {
                return .init(style: .primary("Retry", attention: true), action: .publishPreparedSurface)
            }
            return .init(style: .primary("Fix required", attention: true), action: .presentOfferingRequiredSheet)

        case nil, .draft, .stale:
            if !hasProfile {
                return .init(style: .primary("Profile", attention: true), action: .presentQuickProfileEditSheet)
            }
            if !hasOffers || hasValidation {
                return .init(style: .primary("Fix required", attention: true), action: .presentOfferingRequiredSheet)
            }
            return .init(style: .primary("Publish", attention: true), action: .publishPreparedSurface)
        }
    }

    @MainActor
    private func handlePublicationFooterAction(_ action: PublicationFooterAction) async {
        switch action {
        case .none:
            return
        case .presentOfferingRequiredSheet:
            publicationPreparedError = nil
            hydrateOfferingRequiredDrafts()
            hydrateOfferingAdditionalDrafts()
            offeringRequiredSaveError = nil
            offeringAdditionalSaveError = nil
            offeringRequiredOpenedSinceLastSave = true
            offeringSheetAdditionalInitiallyExpanded = false
            isOfferingRequiredSheetPresented = true
        case .presentQuickProfileEditSheet:
            publicationPreparedError = nil
            hydrateQuickProfileDraftFromWorkspace()
            quickProfileSaveError = nil
            publicProfileQuickEditOpenedSinceLastSave = true
            isPublicProfileQuickEditPresented = true
        case .publishPreparedSurface:
            await publishPreparedProfileSurface()
        }
    }

    private func profileShellTrimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var offeringTitleMissingForBadge: Bool {
        let title = primaryOfferFromWorkspace()?.offer.title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty
    }

    private var offeringDivider: some View {
        Rectangle()
            .fill(SecretaryTheme.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 52)
    }

    // MARK: - Settings (profile subpages)

    /// Same half-screen sheet pattern as Offering — Required / Additional (`ProfileGuardiansSheet`, etc.).
    private var settingsSecondaryGroupedCard: some View {
        VStack(spacing: 0) {
            Button {
                isGuardiansSheetPresented = true
            } label: {
                ProfileShellSettingRowLabel(
                    icon: "shield.checkered",
                    title: "Guardians",
                    subtitle: "Protect private design"
                )
            }
            .buttonStyle(.plain)

            offeringDivider

            Button {
                isSpecialThanksSheetPresented = true
            } label: {
                ProfileShellSettingRowLabel(
                    icon: "sparkles",
                    title: "Special Thanks",
                    subtitle: "Credits"
                )
            }
            .buttonStyle(.plain)

            offeringDivider

            Button {
                isDataPrivacySheetPresented = true
            } label: {
                ProfileShellSettingRowLabel(
                    icon: "hand.raised.fill",
                    title: "Data & Privacy",
                    subtitle: "Local data and federation identity"
                )
            }
            .buttonStyle(.plain)

            offeringDivider

            Button {
                isHelpSheetPresented = true
            } label: {
                ProfileShellSettingRowLabel(
                    icon: "questionmark.circle",
                    title: "Help",
                    subtitle: "Feedback and support"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .background {
            UnifyProfileTranslucentPanelBackground()
        }
    }

    #if DEBUG
    private var appSearchSmokeAuditCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("App search smoke")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text("Runs 10 fixed queries through ExchangeFacade.submit against localhost federation (127.0.0.1:8787). Requires Phase 4F seeded server.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if services.isAppSearchSmokeRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                        Text("Running app search smoke…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                }

                if let status = services.appSearchSmokeStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.appSearchSmokeLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Button {
                        guard !services.isAppSearchSmokeRunning else { return }
                        Task {
                            await services.runAppSearchSmokeAudit(
                                trigger: .manualButton(source: "profile.appSearchSmoke")
                            )
                        }
                    } label: {
                        Text(services.isAppSearchSmokeRunning ? "Running…" : "Run")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SecretaryTheme.darkOrange)
                    .disabled(services.isAppSearchSmokeRunning)

                    Button {
                        guard let report = services.appSearchSmokeLastReport, !report.isEmpty else { return }
                        #if canImport(UIKit)
                        UIPasteboard.general.string = report
                        #endif
                    } label: {
                        Text("Copy Report")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(services.appSearchSmokeLastReport?.isEmpty != false)
                }
            }
            .padding(16)
        }
    }

    private var retrievalE2ESmokeCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Retrieval E2E smoke")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text("Runs 5 natural-language queries through ExchangeFacade.submit on a real device against localhost federation. Logs use [RetrievalE2E] prefix.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if services.isRetrievalE2ESmokeRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                        Text("Running retrieval E2E smoke…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                }

                if let status = services.retrievalE2ESmokeStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.retrievalE2ESmokeLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Button {
                        guard !services.isRetrievalE2ESmokeRunning else { return }
                        Task {
                            await services.runRetrievalE2ESmoke(
                                trigger: .manualButton(source: "profile.retrievalE2E")
                            )
                        }
                    } label: {
                        Text(services.isRetrievalE2ESmokeRunning ? "Running…" : "Run")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SecretaryTheme.darkOrange)
                    .disabled(services.isRetrievalE2ESmokeRunning)

                    Button {
                        guard let report = services.retrievalE2ESmokeLastReport, !report.isEmpty else { return }
                        #if canImport(UIKit)
                        UIPasteboard.general.string = report
                        #endif
                    } label: {
                        Text("Copy Report")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(services.retrievalE2ESmokeLastReport?.isEmpty != false)
                }
            }
            .padding(16)
        }
    }

    private var multilingualE2ESmokeCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Multilingual retrieval E2E smoke")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text("Seeds one Chinese roofer fixture plus a noisy home-services profile, then runs the Chinese secretary request. Use injected baseline for deterministic carrier parity, live enricher for real seller enrichment, or pair to compare both.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if services.isMultilingualE2ESmokeRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                        Text("Running multilingual E2E smoke…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                }

                if let status = services.multilingualE2ESmokeStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.multilingualE2ESmokeLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                VStack(spacing: 10) {
                    Button {
                        guard !services.isMultilingualE2ESmokeRunning else { return }
                        Task {
                            await services.runMultilingualRetrievalE2ESmoke(
                                trigger: .manualButton(source: "profile.multilingualE2E.injected"),
                                mode: .injectedCarrierFixture
                            )
                        }
                    } label: {
                        Text(services.isMultilingualE2ESmokeRunning ? "Running…" : "Run injected baseline")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SecretaryTheme.darkOrange)
                    .disabled(services.isMultilingualE2ESmokeRunning)

                    Button {
                        guard !services.isMultilingualE2ESmokeRunning else { return }
                        Task {
                            await services.runMultilingualRetrievalE2ESmoke(
                                trigger: .manualButton(source: "profile.multilingualE2E.liveEnricher"),
                                mode: .livePublishEnricher
                            )
                        }
                    } label: {
                        Text("Run live enricher")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(services.isMultilingualE2ESmokeRunning)

                    Button {
                        guard !services.isMultilingualE2ESmokeRunning else { return }
                        Task {
                            await services.runMultilingualRetrievalE2ESmoke(
                                trigger: .manualButton(source: "profile.multilingualE2E.fullFacade"),
                                mode: .fullFacadePublishPath
                            )
                        }
                    } label: {
                        Text("Run full facade publish")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(services.isMultilingualE2ESmokeRunning)

                    Button {
                        guard !services.isMultilingualE2ESmokeRunning else { return }
                        Task {
                            await services.runMultilingualRetrievalE2ESmokePair(
                                trigger: .manualButton(source: "profile.multilingualE2E.pair")
                            )
                        }
                    } label: {
                        Text("Run paired comparison")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(services.isMultilingualE2ESmokeRunning)

                    Button {
                        guard !services.isMultilingualE2ESmokeRunning else { return }
                        Task {
                            await services.runMultilingualRetrievalE2ESmokeTriple(
                                trigger: .manualButton(source: "profile.multilingualE2E.triple")
                            )
                        }
                    } label: {
                        Text("Run triple comparison")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(services.isMultilingualE2ESmokeRunning)
                }

                HStack(spacing: 10) {
                    Button {
                        guard let report = services.multilingualE2ESmokeLastReport, !report.isEmpty else { return }
                        #if canImport(UIKit)
                        UIPasteboard.general.string = report
                        #endif
                    } label: {
                        Text("Copy Report")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(services.multilingualE2ESmokeLastReport?.isEmpty != false)
                }
            }
            .padding(16)
        }
    }

    private var multilingualLiveSubsetSmokeCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Multilingual live subset")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text("Runs 10 live scenarios (5 verticals × zh_zh + mixed) through ExchangeFacade with live enricher seeding. DEBUG/manual only.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if services.isMultilingualLiveSubsetRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                        Text("Running multilingual live subset…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                }

                if let status = services.multilingualLiveSubsetStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.multilingualLiveSubsetLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                Button {
                    guard !services.isMultilingualLiveSubsetRunning else { return }
                    Task {
                        await services.runMultilingualLiveSubsetSmoke(
                            trigger: .manualButton(source: "profile.multilingualLiveSubset")
                        )
                    }
                } label: {
                    Text(services.isMultilingualLiveSubsetRunning ? "Running…" : "Run multilingual live subset")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SecretaryTheme.darkOrange)
                .disabled(services.isMultilingualLiveSubsetRunning || services.isMultilingualE2ESmokeRunning)
            }
            .padding(16)
        }
    }

    private var searchIntentSmokeAuditCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Search intent smoke audit")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text("Runs the real on-device search intent extractor with English, Chinese, and mixed prompts.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if services.isSearchIntentSmokeAuditRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                        Text("Running smoke audit…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                }

                if let status = services.searchIntentSmokeAuditStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.searchIntentSmokeAuditLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                Button {
                    guard !services.isSearchIntentSmokeAuditRunning else { return }
                    Task {
                        await services.runSearchIntentExtractionSmokeAudit(
                            trigger: .manualButton(source: "profile.searchIntentSmoke")
                        )
                    }
                } label: {
                    Text(services.isSearchIntentSmokeAuditRunning ? "Running…" : "Run smoke audit")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                }
                .buttonStyle(.plain)
                .disabled(services.isSearchIntentSmokeAuditRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private var requesterGapSmokeAuditCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Requester gap smoke audit")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text("Runs fixed requester/profile fixtures through the live on-device requester match compare path.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if services.isRequesterGapSmokeAuditRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                        Text("Running gap smoke audit…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                }

                if let status = services.requesterGapSmokeAuditStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.requesterGapSmokeAuditLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                Button {
                    guard !services.isRequesterGapSmokeAuditRunning else { return }
                    Task {
                        await services.runRequesterGapOnDeviceSmokeAudit(
                            trigger: .manualButton(source: "profile.requesterGapSmoke")
                        )
                    }
                } label: {
                    Text(services.isRequesterGapSmokeAuditRunning ? "Running…" : "Run gap smoke audit")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                }
                .buttonStyle(.plain)
                .disabled(services.isRequesterGapSmokeAuditRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private var providerInquiryAnswerSmokeBatchButtons: some View {
        let ranges: [(String, ClosedRange<Int>)] = [
            ("1–5", 1...5),
            ("6–10", 6...10),
            ("11–15", 11...15),
            ("16–20", 16...20)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ranges.enumerated()), id: \.offset) { _, item in
                Button {
                    guard !services.isProviderInquiryAnswerSmokeAuditRunning else { return }
                    Task {
                        await services.runProviderInquiryAnswerOnDeviceSmokeAudit(
                            trigger: .manualButton(source: "profile.providerInquirySmoke.\(item.0)"),
                            range: item.1
                        )
                    }
                } label: {
                    Text("Run fixtures \(item.0)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(SecretaryTheme.darkGlass.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .disabled(services.isProviderInquiryAnswerSmokeAuditRunning)
            }
        }
    }

    private var providerInquiryAnswerSmokeAuditCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Provider inquiry answer smoke audit (DEBUG)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text(
                    "Runs provider inquiry compare fixtures through the live on-device providerInquiryCompare runner. " +
                    "Use batched runs (5 fixtures) to avoid long Xcode sessions. Checks grounded answers and boundary discipline."
                )
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                providerInquiryAnswerSmokeBatchButtons

                if services.isProviderInquiryAnswerSmokeAuditRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running on-device provider inquiry compare…")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
                }

                if let status = services.providerInquiryAnswerSmokeAuditStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.providerInquiryAnswerSmokeAuditLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                Button {
                    guard !services.isProviderInquiryAnswerSmokeAuditRunning else { return }
                    Task {
                        await services.runProviderInquiryAnswerOnDeviceSmokeAudit(
                            trigger: .manualButton(source: "profile.providerInquirySmoke.all")
                        )
                    }
                } label: {
                    Text(services.isProviderInquiryAnswerSmokeAuditRunning ? "Running…" : "Run all (20 fixtures)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                }
                .buttonStyle(.plain)
                .disabled(services.isProviderInquiryAnswerSmokeAuditRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private var requesterComposeSmokeAuditCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Requester compose smoke audit (DEBUG)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text(
                    "Runs two autonomous compose fixtures through the live on-device requesterDraft runner. " +
                    "Checks compare-succeeded guard acceptance/rejection."
                )
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if services.isRequesterComposeSmokeAuditRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running on-device compose…")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
                }

                if let status = services.requesterComposeSmokeAuditStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.requesterComposeSmokeAuditLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                Button {
                    guard !services.isRequesterComposeSmokeAuditRunning else { return }
                    Task {
                        await services.runRequesterComposeOnDeviceSmokeAudit(
                            trigger: .manualButton(source: "profile.requesterComposeSmoke")
                        )
                    }
                } label: {
                    Text(services.isRequesterComposeSmokeAuditRunning ? "Running…" : "Run compose smoke audit")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                }
                .buttonStyle(.plain)
                .disabled(services.isRequesterComposeSmokeAuditRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private var directChatReplySmokeAuditCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Direct reply smoke audit (DEBUG)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Text(
                    "Runs six direct-message reply suggestion fixtures through the live on-device " +
                    "directChatReply runner. Checks no-inbound and auto-reply-disabled gates, " +
                    "non-empty suggestions, and commercial-language guardrails."
                )
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if services.isDirectChatReplySmokeAuditRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running on-device direct reply…")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
                }

                if let status = services.directChatReplySmokeAuditStatus {
                    Text(status)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = services.directChatReplySmokeAuditLastArtifactURL {
                    Text("Last artifact: \(url.lastPathComponent)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .textSelection(.enabled)
                }

                Button {
                    guard !services.isDirectChatReplySmokeAuditRunning else { return }
                    Task {
                        await services.runDirectChatReplyOnDeviceSmokeAudit(
                            trigger: .manualButton(source: "profile.directChatReplySmoke")
                        )
                    }
                } label: {
                    Text(services.isDirectChatReplySmokeAuditRunning ? "Running…" : "Run direct reply smoke audit")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                }
                .buttonStyle(.plain)
                .disabled(services.isDirectChatReplySmokeAuditRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
    #endif

    // MARK: - Resolved copy (real data + fallbacks)

    private var hasMeaningfulWorkspaceIdentity: Bool {
        if let profile = workspace?.publicProfile {
            let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return true }
        }
        if let owner = workspace?.ownerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !owner.isEmpty {
            return true
        }
        return false
    }

    /// True only while there is no canonical workspace snapshot to render yet.
    private var profileHeaderShowsHydrationPlaceholder: Bool {
        if services.sellerWorkspace != nil {
            return false
        }
        if hasMeaningfulWorkspaceIdentity {
            return false
        }
        return services.isSellerWorkspaceRefreshInFlight
            || !services.hasCompletedSellerWorkspaceHydrationAtLeastOnce
    }

    private func profileShellLogRenderState(context: String) {
        #if DEBUG
        let imageRaw = workspace?.publicProfile?.profile.primaryImageURL ?? ""
        print(
            "[ProfileRenderState] context=\(context) route=profile isTabActive=\(isTabActive) " +
            "hasWorkspace=\(workspace != nil) hasPublicProfile=\(workspace?.publicProfile != nil) " +
            "imageURL=\(imageRaw.isEmpty ? "empty" : imageRaw) " +
            "loading=\(profileHeaderShowsHydrationPlaceholder) " +
            "generation=\(services.sellerWorkspaceHydrationGeneration) " +
            "hydrationComplete=\(services.hasCompletedSellerWorkspaceHydrationAtLeastOnce) " +
            "refreshInFlight=\(services.isSellerWorkspaceRefreshInFlight)"
        )
        #endif
    }

    #if DEBUG
    private func logGuardianCrownOwnProfile(context: String) {
        let derived = ExchangeSupporterPresentation.guardianCrownIfActive(supportStore.isSupportingMonthly)
        let stored = workspace?.publicProfile?.profile.publicSupporterPresentation
        let render = supportStore.isSupportingMonthly
        GuardianCrownDebugLog.log(
            "OwnProfile",
            "context=\(context) isSupportingMonthly=\(supportStore.isSupportingMonthly) " +
            "autoRenew=\(supportStore.isMonthlyAutoRenewOn) " +
            "derived=\(GuardianCrownDebugLog.presentationLabel(derived)) " +
            "stored=\(GuardianCrownDebugLog.presentationLabel(stored)) " +
            "render=\(render)"
        )
    }
    #endif

    private var resolvedDisplayName: String {
        if let name = workspace?.publicProfile?.displayName, !name.isEmpty {
            return name
        }
        if let owner = workspace?.ownerDisplayName, !owner.isEmpty {
            return owner
        }
        return ProfileShellPlaceholder.fallbackDisplayName
    }

    private var resolvedPublicHeadline: String {
        if let p = workspace?.publicProfile {
            if let h = p.headline, !h.isEmpty { return h }
            if let s = p.summaryLine, !s.isEmpty { return s }
            if let s2 = p.summary, !s2.isEmpty {
                let trimmed = String(s2.prefix(160))
                return trimmed.count < s2.count ? "\(trimmed)…" : trimmed
            }
            if let intro = p.publicIntroLine, !intro.isEmpty { return intro }
        }
        if let line = workspace?.statusLine, !line.isEmpty {
            return line
        }
        return ProfileShellPlaceholder.fallbackPublicHeadline
    }

    private var resolvedAvatarURL: URL? {
        profileShellResolvedPublicImageURL(
            from: workspace?.publicProfile?.profile.primaryImageURL
        )
    }

    // MARK: - Public profile quick edit (same persistence path as seller surface editor)

    @MainActor
    private func presentProfileShellPhotoCrop(
        from item: PhotosPickerItem,
        target: ProfileShellPhotoCropTarget
    ) async {
        let pickerContext: String = {
            switch target {
            case .profile: return "profileShellProfilePhotoPicker"
            case .offerHero: return "profileShellOfferHeroPicker"
            case .offerGalleryNew: return "profileShellOfferGalleryNewPicker"
            case .offerGalleryReplace(let index, _):
                return "profileShellOfferGalleryReplacePicker(index:\(index))"
            }
        }()
        guard let image = await SharedPhotoEditFlow.loadUIImage(from: item, context: pickerContext) else {
            switch target {
            case .profile:
                profilePhotoError = "Selected photo could not be loaded."
            case .offerHero, .offerGalleryNew, .offerGalleryReplace:
                offerMediaError = "Selected photo could not be loaded."
            }
            return
        }
        pendingPhotoCropTarget = target
        photoCropSourceImage = image
        showPhotoCropper = true
    }

    @MainActor
    private func dismissProfileShellPhotoCropper() {
        showPhotoCropper = false
        photoCropSourceImage = nil
        pendingPhotoCropTarget = nil
    }

    @MainActor
    private func applyProfileShellCroppedPhoto(_ editedImage: UIImage) async {
        let target = pendingPhotoCropTarget
        dismissProfileShellPhotoCropper()
        switch target {
        case .profile:
            await uploadProfilePhoto(editedImage: editedImage)
        case .offerHero:
            await uploadOfferHeroPhoto(editedImage: editedImage)
        case .offerGalleryNew:
            await uploadOfferGalleryPhoto(editedImage: editedImage)
        case .offerGalleryReplace(let index, let rawURL):
            await replaceOfferGalleryImage(at: index, replacingRaw: rawURL, editedImage: editedImage)
        case .none:
            break
        }
    }

    /// Same pipeline as `SecretarySellerSurfaceEditorView` profile photo: `SellerEditorImagePrep` → `uploadPublicMedia` → `savePublicProfile`.
    @MainActor
    private func uploadProfilePhoto(editedImage: UIImage) async {
        profilePhotoError = nil
        isUploadingProfilePhoto = true
        defer { isUploadingProfilePhoto = false }

        let prepared = SellerEditorImagePrep.prepareForUpload(editedImage, context: "profileShellProfilePhoto")

        let nodeID = await services.exchangeNodeID ?? ""
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            profilePhotoError = "Missing local node ID."
            return
        }

        do {
            let previousProfileImageKey = PublicMediaURLSupport.storageKeyFromPublicMediaURL(
                services.sellerWorkspace?.publicProfile?.profile.primaryImageURL
            )

            var profile: ExchangePublicNodeProfile
            if let existing = services.sellerWorkspace?.publicProfile?.profile {
                profile = existing
            } else {
                let ownerName = services.sellerWorkspace?.ownerDisplayName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let displayForCreate: String? = (ownerName?.isEmpty == false) ? ownerName : nil
                profile = try await services.exchangeFacade.createSellerProfile(
                    ownerNodeID: trimmedNode,
                    ownerDisplayName: displayForCreate
                )
            }

            let uploadedURL = try await services.uploadPublicMedia(
                data: prepared.data,
                mimeType: prepared.mimeType,
                role: "primaryProfile",
                publicProfileID: profile.id,
                offerID: nil
            )

            let trimmedURL = uploadedURL.trimmingCharacters(in: .whitespacesAndNewlines)
            var updated = profile
            updated.primaryImageURL = trimmedURL.isEmpty ? nil : trimmedURL
            updated.updatedAt = Date()

            try await services.exchangeFacade.savePublicProfile(updated)
            await services.refreshSellerWorkspace()

            var staleProfileKeys: Set<String> = []
            if let previousProfileImageKey {
                let currentKey = PublicMediaURLSupport.storageKeyFromPublicMediaURL(trimmedURL)
                if currentKey != previousProfileImageKey {
                    staleProfileKeys.insert(previousProfileImageKey)
                }
            }
            if let syncError = await services.afterSuccessfulSellerSurfaceMediaMutation(
                staleStorageKeys: staleProfileKeys,
                context: "profile-shell-profile-photo"
            ) {
                profilePhotoError = syncError
            }
        } catch {
            profilePhotoError = "Could not upload or save profile photo: \(error.localizedDescription)"
        }
    }

    // MARK: - Offer media (same `uploadPublicMedia` roles as `SecretarySellerSurfaceEditorView`: `primaryOffer`, `offerGallery`)

    @MainActor
    private func profileShellRefreshPrimaryOfferAfterEnsure(nodeID: String) async throws -> ExchangeOffer {
        let profile = try await ensurePublicProfileForOfferSave(nodeID: nodeID)
        _ = try await ensureOfferForEditing(nodeID: nodeID, publicProfileID: profile.id)
        await services.refreshSellerWorkspace()
        guard let o = primaryOfferFromWorkspace()?.offer else {
            throw NSError(
                domain: "UnifyProfileShell",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not load primary offer after ensuring it exists."]
            )
        }
        return o
    }

    @MainActor
    private func uploadOfferHeroPhoto(editedImage: UIImage) async {
        offerMediaError = nil
        isUploadingOfferHeroImage = true
        defer { isUploadingOfferHeroImage = false }

        let prepared = SellerEditorImagePrep.prepareForUpload(editedImage, context: "profileShellOfferHero")

        let nodeID = await services.exchangeNodeID ?? ""
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            offerMediaError = "Missing local node ID."
            return
        }

        do {
            var offer = try await profileShellRefreshPrimaryOfferAfterEnsure(nodeID: trimmedNode)
            let previousHeroKey = PublicMediaURLSupport.storageKeyFromPublicMediaURL(offer.primaryImageURL)

            let uploadedURL = try await services.uploadPublicMedia(
                data: prepared.data,
                mimeType: prepared.mimeType,
                role: "primaryOffer",
                publicProfileID: offer.publicProfileID,
                offerID: offer.id
            )

            let trimmedURL = uploadedURL.trimmingCharacters(in: .whitespacesAndNewlines)
            offer.primaryImageURL = trimmedURL.isEmpty ? nil : trimmedURL
            offer.galleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                primary: offer.primaryImageURL,
                gallery: offer.galleryImageURLs
            )
            offer.updatedAt = Date()

            try await services.exchangeFacade.saveOffer(offer)
            await services.refreshSellerWorkspace()

            var staleHeroKeys: Set<String> = []
            if let previousHeroKey {
                let currentKey = PublicMediaURLSupport.storageKeyFromPublicMediaURL(offer.primaryImageURL)
                if currentKey != previousHeroKey {
                    staleHeroKeys.insert(previousHeroKey)
                }
            }
            if let syncError = await services.afterSuccessfulSellerSurfaceMediaMutation(
                staleStorageKeys: staleHeroKeys,
                context: "profile-shell-offer-hero"
            ) {
                offerMediaError = syncError
            }
        } catch {
            offerMediaError = "Could not upload or save offer hero image: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func uploadOfferGalleryPhoto(editedImage: UIImage) async {
        offerMediaError = nil
        isUploadingOfferGalleryImage = true
        defer { isUploadingOfferGalleryImage = false }

        let prepared = SellerEditorImagePrep.prepareForUpload(editedImage, context: "profileShellOfferGallery")

        let nodeID = await services.exchangeNodeID ?? ""
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            offerMediaError = "Missing local node ID."
            return
        }

        do {
            var offer = try await profileShellRefreshPrimaryOfferAfterEnsure(nodeID: trimmedNode)

            let atCap = ExchangeOffer.limitedOrderedOfferImageURLs(
                primaryImageURL: offer.primaryImageURL,
                galleryImageURLs: offer.galleryImageURLs
            ).count >= ExchangeOffer.maxPublicOfferImageCount
            if atCap {
                offerMediaError = "Image limit reached."
                return
            }

            let uploadedURL = try await services.uploadPublicMedia(
                data: prepared.data,
                mimeType: prepared.mimeType,
                role: "offerGallery",
                publicProfileID: offer.publicProfileID,
                offerID: offer.id
            )

            var merged = offer.galleryImageURLs
            merged.append(uploadedURL)
            offer.galleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                primary: offer.primaryImageURL,
                gallery: merged
            )
            offer.updatedAt = Date()

            try await services.exchangeFacade.saveOffer(offer)
            await services.refreshSellerWorkspace()

            if let syncError = await services.afterSuccessfulSellerSurfaceMediaMutation(
                staleStorageKeys: [],
                context: "profile-shell-offer-gallery-add"
            ) {
                offerMediaError = syncError
            }
        } catch {
            offerMediaError = "Could not upload or save gallery image: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func replaceOfferGalleryImage(
        at index: Int,
        replacingRaw oldRaw: String,
        editedImage: UIImage
    ) async {
        offerMediaError = nil
        isUploadingOfferGalleryImage = true
        defer { isUploadingOfferGalleryImage = false }

        let prepared = SellerEditorImagePrep.prepareForUpload(
            editedImage,
            context: "profileShellOfferGalleryReplace(index:\(index))"
        )

        let nodeID = await services.exchangeNodeID ?? ""
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            offerMediaError = "Missing local node ID."
            return
        }

        do {
            var offer = try await profileShellRefreshPrimaryOfferAfterEnsure(nodeID: trimmedNode)
            guard index >= 0, index < offer.galleryImageURLs.count else {
                offerMediaError = "Gallery image no longer exists."
                return
            }

            let previousKey = PublicMediaURLSupport.storageKeyFromPublicMediaURL(oldRaw)

            let uploadedURL = try await services.uploadPublicMedia(
                data: prepared.data,
                mimeType: prepared.mimeType,
                role: "offerGallery",
                publicProfileID: offer.publicProfileID,
                offerID: offer.id
            )

            let trimmedURL = uploadedURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty else {
                offerMediaError = "Upload did not return a URL."
                return
            }

            var gallery = offer.galleryImageURLs
            gallery[index] = trimmedURL
            offer.galleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                primary: offer.primaryImageURL,
                gallery: gallery
            )
            offer.updatedAt = Date()

            try await services.exchangeFacade.saveOffer(offer)
            await services.refreshSellerWorkspace()

            var staleGalleryKeys: Set<String> = []
            if let previousKey {
                let currentKey = PublicMediaURLSupport.storageKeyFromPublicMediaURL(trimmedURL)
                if currentKey != previousKey {
                    staleGalleryKeys.insert(previousKey)
                }
            }
            if let syncError = await services.afterSuccessfulSellerSurfaceMediaMutation(
                staleStorageKeys: staleGalleryKeys,
                context: "profile-shell-replace-offer-gallery"
            ) {
                offerMediaError = syncError
            }
        } catch {
            offerMediaError = "Could not replace gallery image: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearOfferHeroImage() async {
        offerMediaError = nil
        isUploadingOfferHeroImage = true
        defer { isUploadingOfferHeroImage = false }

        let nodeID = await services.exchangeNodeID ?? ""
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            offerMediaError = "Missing local node ID."
            return
        }

        do {
            var offer = try await profileShellRefreshPrimaryOfferAfterEnsure(nodeID: trimmedNode)
            let previousHeroKey = PublicMediaURLSupport.storageKeyFromPublicMediaURL(offer.primaryImageURL)
            offer.primaryImageURL = nil
            offer.galleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                primary: nil,
                gallery: offer.galleryImageURLs
            )
            offer.updatedAt = Date()
            try await services.exchangeFacade.saveOffer(offer)
            await services.refreshSellerWorkspace()

            var staleHeroKeys: Set<String> = []
            if let previousHeroKey {
                staleHeroKeys.insert(previousHeroKey)
            }
            if let syncError = await services.afterSuccessfulSellerSurfaceMediaMutation(
                staleStorageKeys: staleHeroKeys,
                context: "profile-shell-clear-offer-hero"
            ) {
                offerMediaError = syncError
            }
        } catch {
            offerMediaError = "Could not clear hero image: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func removeOfferGalleryImage(removingRaw: String) async {
        offerMediaError = nil
        isUploadingOfferGalleryImage = true
        defer { isUploadingOfferGalleryImage = false }

        let key = removingRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }

        let nodeID = await services.exchangeNodeID ?? ""
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            offerMediaError = "Missing local node ID."
            return
        }

        do {
            var offer = try await profileShellRefreshPrimaryOfferAfterEnsure(nodeID: trimmedNode)
            let removedStorageKey = PublicMediaURLSupport.storageKeyFromPublicMediaURL(removingRaw)
            let filtered = offer.galleryImageURLs.filter {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != key
            }
            offer.galleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                primary: offer.primaryImageURL,
                gallery: filtered
            )
            offer.updatedAt = Date()
            try await services.exchangeFacade.saveOffer(offer)
            await services.refreshSellerWorkspace()

            var staleGalleryKeys: Set<String> = []
            if let removedStorageKey {
                staleGalleryKeys.insert(removedStorageKey)
            }
            if let syncError = await services.afterSuccessfulSellerSurfaceMediaMutation(
                staleStorageKeys: staleGalleryKeys,
                context: "profile-shell-remove-offer-gallery"
            ) {
                offerMediaError = syncError
            }
        } catch {
            offerMediaError = "Could not remove gallery image: \(error.localizedDescription)"
        }
    }

    private func hydrateQuickProfileDraftFromWorkspace() {
        let ws = services.sellerWorkspace
        if let pv = ws?.publicProfile {
            let p = pv.profile
            draftDisplayName = p.displayName ?? ""
            draftHeadline = p.headline ?? ""
            draftAboutYou = p.summary ?? ""
            draftLookingFor = p.openTo.joined(separator: ", ")
            draftInterests = p.interests.joined(separator: ", ")
            draftCurrentRoles = p.activityTags.joined(separator: ", ")
            draftRegion = p.regionTags.joined(separator: ", ")
        } else {
            draftDisplayName = ws?.ownerDisplayName ?? ""
            draftHeadline = ""
            draftAboutYou = ""
            draftLookingFor = ""
            draftInterests = ""
            draftCurrentRoles = ""
            draftRegion = ""
        }
    }

    @MainActor
    private func savePublicProfileQuickEdit() async {
        guard !isSavingQuickProfile else { return }
        isSavingQuickProfile = true
        quickProfileSaveError = nil
        defer { isSavingQuickProfile = false }

        do {
            let nodeID = await services.exchangeNodeID ?? ""
            let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedNode.isEmpty else {
                quickProfileSaveError = "Missing local node ID."
                return
            }

            var profile: ExchangePublicNodeProfile
            if let existing = services.sellerWorkspace?.publicProfile?.profile {
                profile = existing
            } else {
                profile = try await services.exchangeFacade.createSellerProfile(
                    ownerNodeID: trimmedNode,
                    ownerDisplayName: nilIfBlank(draftDisplayName)
                )
            }

            profile.displayName = nilIfBlank(draftDisplayName)
            profile.headline = nilIfBlank(draftHeadline)
            profile.summary = nilIfBlank(draftAboutYou)
            profile.openTo = splitCSV(draftLookingFor)
            profile.interests = splitCSV(draftInterests)
            profile.activityTags = splitCSV(draftCurrentRoles)
            profile.regionTags = splitCSV(draftRegion)
            profile.updatedAt = Date()

            try await services.exchangeFacade.savePublicProfile(profile)
            await services.refreshSellerWorkspace()
            publicProfileQuickEditOpenedSinceLastSave = false
            isPublicProfileQuickEditPresented = false
        } catch {
            quickProfileSaveError = error.localizedDescription
        }
    }

    // MARK: - Offering (same persistence path as `SecretarySellerSurfaceEditorView`)

    private func primaryOfferFromWorkspace() -> ExchangeModels.OfferView? {
        guard let ws = workspace else { return nil }
        if let active = ws.offers.first(where: { $0.offer.status == .active }) {
            return active
        }
        return ws.offers.first
    }

    private func profileShellPrimaryOfferIsValidForDiscovery(_ ws: ExchangeModels.SellerWorkspaceSummary) -> Bool {
        guard let ov = primaryOfferFromWorkspace() else { return false }
        let o = ov.offer
        guard o.status == .active else { return false }
        guard o.visibility == .publicDiscoverable else { return false }
        let t = o.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !profileShellOfferTitleFailsPublishPlaceholderGuard(t) else { return false }
        return true
    }

    private func ensurePublicProfileForOfferSave(nodeID: String) async throws -> ExchangePublicNodeProfile {
        let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNode.isEmpty else {
            throw NSError(
                domain: "UnifyProfileShell",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing local node ID."]
            )
        }
        if let existing = services.sellerWorkspace?.publicProfile?.profile {
            return existing
        }
        let ownerName = services.sellerWorkspace?.ownerDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayForCreate: String? = (ownerName?.isEmpty == false) ? ownerName : nil
        return try await services.exchangeFacade.createSellerProfile(
            ownerNodeID: trimmedNode,
            ownerDisplayName: displayForCreate
        )
    }

    private func ensureOfferForEditing(nodeID: String, publicProfileID: String) async throws -> ExchangeOffer {
        if let existing = primaryOfferFromWorkspace()?.offer {
            return existing
        }
        return try await services.exchangeFacade.createDraftOffer(
            ownerNodeID: nodeID,
            publicProfileID: publicProfileID,
            title: "New Offer",
            summary: nil
        )
    }

    private func hydrateOfferingRequiredDrafts() {
        guard let ov = primaryOfferFromWorkspace() else {
            offeringReqTitle = ""
            offeringReqSummary = ""
            offeringReqCategory = ""
            offeringReqRegionTags = ""
            offeringReqTags = ""
            return
        }
        let o = ov.offer
        offeringReqTitle = o.title
        offeringReqSummary = o.summary ?? ""
        offeringReqCategory = o.category ?? ""
        offeringReqRegionTags = o.serviceAreas.isEmpty
            ? o.regionTags.joined(separator: ", ")
            : ExchangeDeclaredServiceAreaSupport.projectRegionTags(from: o.serviceAreas).joined(separator: ", ")
        offeringReqTags = o.tags.joined(separator: ", ")
    }

    private func hydrateOfferingAdditionalDrafts() {
        guard let o = primaryOfferFromWorkspace()?.offer else {
            offAddContactName = ""
            offAddBusinessName = ""
            offAddEmail = ""
            offAddPhone = ""
            offAddWebsite = ""
            offAddPreferredMethod = ""
            offAddContactAvailability = ""
            offAddServiceAddress = ""
            offAddPriceDisplay = ""
            offAddPriceMin = ""
            offAddPriceMax = ""
            offAddCurrency = ""
            offAddPriceUnit = ""
            offAddPackages = ""
            offAddServiceAreaNote = ""
            offAddAvailabilityNote = ""
            offAddMinimumEngagement = ""
            offAddCancellation = ""
            offAddRefund = ""
            offAddWarranty = ""
            offAddRequiredInputs = ""
            offAddFAQs = ""
            offAddAutoPricing = false
            offAddAutoAvailability = false
            offAddAutoPolicies = true
            offAddAutoServiceArea = true
            offAddAutoFAQs = true
            offAddAutoCustomQuote = true
            return
        }
        let contact = o.contactInfo
        offAddContactName = contact?.contactName ?? ""
        offAddBusinessName = contact?.businessName ?? ""
        offAddEmail = contact?.email ?? ""
        offAddPhone = contact?.phone ?? ""
        offAddWebsite = contact?.website ?? ""
        offAddPreferredMethod = contact?.preferredContactMethod?.rawValue ?? ""
        offAddContactAvailability = contact?.availabilityNote ?? ""
        offAddServiceAddress = contact?.serviceAddressOrArea ?? ""

        let facts = o.commercialFacts
        offAddPriceDisplay = facts.priceDisplay ?? ""
        offAddPriceMin = profileShellDecimalText(facts.priceMin)
        offAddPriceMax = profileShellDecimalText(facts.priceMax)
        offAddCurrency = facts.currency ?? ""
        offAddPriceUnit = facts.priceUnit ?? ""
        offAddPackages = profileShellPackagesEditorText(from: facts.packages)
        offAddServiceAreaNote = facts.serviceAreaNote ?? ""
        offAddAvailabilityNote = facts.availabilityNote ?? ""
        offAddMinimumEngagement = facts.minimumEngagement ?? ""
        offAddCancellation = facts.cancellationPolicy ?? ""
        offAddRefund = facts.refundPolicy ?? ""
        offAddWarranty = facts.warrantyPolicy ?? ""
        offAddRequiredInputs = facts.requiredBuyerInputs.joined(separator: "\n")
        offAddFAQs = profileShellFAQsEditorText(from: facts.faqs)

        let ap = facts.autoAnswerPolicy
        offAddAutoPricing = ap.canAnswerPricing
        offAddAutoAvailability = ap.canAnswerAvailability
        offAddAutoPolicies = ap.canAnswerPolicies
        offAddAutoServiceArea = ap.canAnswerServiceArea
        offAddAutoFAQs = ap.canAnswerFAQs
        offAddAutoCustomQuote = ap.requiresApprovalForCustomQuote
    }

    @MainActor
    private func saveOfferingRequiredSheet() async {
        guard !isSavingOfferingRequired else { return }
        let trimmedTitle = offeringReqTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            offeringRequiredSaveError = "Offer title cannot be empty."
            return
        }

        isSavingOfferingRequired = true
        offeringRequiredSaveError = nil
        defer { isSavingOfferingRequired = false }

        do {
            let nodeID = await services.exchangeNodeID ?? ""
            let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedNode.isEmpty else {
                offeringRequiredSaveError = "Missing local node ID."
                return
            }

            let profile = try await ensurePublicProfileForOfferSave(nodeID: trimmedNode)
            var offer = try await ensureOfferForEditing(nodeID: trimmedNode, publicProfileID: profile.id)

            offer.title = trimmedTitle
            offer.summary = nilIfBlank(offeringReqSummary)
            offer.category = nilIfBlank(offeringReqCategory)
            let serviceAreaBatch = await services.resolveSellerServiceAreas(from: offeringReqRegionTags)
            serviceAreaResolveNotice = serviceAreaBatch.userNotice
            offer.serviceAreas = serviceAreaBatch.areas
            ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&offer)
            offer.tags = splitCSV(offeringReqTags)
            offer.status = .active
            offer.visibility = .publicDiscoverable
            offer.publicProfileID = profile.id
            offer.updatedAt = Date()

            try await services.exchangeFacade.saveOffer(offer)
            await services.refreshSellerWorkspace()
            if let pub = services.sellerWorkspace?.publicProfile?.profile {
                try await profileShellPersistDerivedPublicProfileOffersIfChanged(
                    publicProfile: pub,
                    primaryOffer: offer
                )
            }
            offeringRequiredOpenedSinceLastSave = false
            isOfferingRequiredSheetPresented = false
        } catch {
            offeringRequiredSaveError = error.localizedDescription
        }
    }

    @MainActor
    private func saveOfferingAdditionalSheet() async {
        guard !isSavingOfferingAdditional else { return }
        isSavingOfferingAdditional = true
        offeringAdditionalSaveError = nil
        defer { isSavingOfferingAdditional = false }

        do {
            let nodeID = await services.exchangeNodeID ?? ""
            let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedNode.isEmpty else {
                offeringAdditionalSaveError = "Missing local node ID."
                return
            }

            let profile = try await ensurePublicProfileForOfferSave(nodeID: trimmedNode)
            var offer = try await ensureOfferForEditing(nodeID: trimmedNode, publicProfileID: profile.id)

            offer.contactInfo = profileShellContactFromAdditionalDrafts()
            offer.commercialFacts = profileShellCommercialFactsFromAdditionalDrafts()
            offer.publicProfileID = profile.id
            offer.updatedAt = Date()

            try await services.exchangeFacade.saveOffer(offer)
            await services.refreshSellerWorkspace()
            offeringAdditionalOpenedSinceLastSave = false
            isSecretaryAutoInquiryRepliesPresented = false
        } catch {
            offeringAdditionalSaveError = error.localizedDescription
        }
    }

    // MARK: - Publish safety (dirty sheets + placeholder offer title)

    private var publicProfileQuickEditHasUnsavedSheetChanges: Bool {
        publicProfileQuickEditOpenedSinceLastSave && !quickProfileDraftsMatchWorkspace()
    }

    private var offeringRequiredHasUnsavedSheetChanges: Bool {
        offeringRequiredOpenedSinceLastSave && !offeringRequiredDraftsMatchWorkspace()
    }

    private var offeringAdditionalHasUnsavedSheetChanges: Bool {
        offeringAdditionalOpenedSinceLastSave && !offeringAdditionalDraftsMatchWorkspace()
    }

    private var profileShellHasAnyUnsavedProfileSheetChanges: Bool {
        publicProfileQuickEditHasUnsavedSheetChanges
            || offeringRequiredHasUnsavedSheetChanges
            || offeringAdditionalHasUnsavedSheetChanges
    }

    /// Compares quick-edit drafts to the current `sellerWorkspace` snapshot (same shape as `hydrateQuickProfileDraftFromWorkspace()`).
    private func quickProfileDraftsMatchWorkspace() -> Bool {
        let ws = services.sellerWorkspace
        if let pv = ws?.publicProfile {
            let p = pv.profile
            guard draftDisplayName == (p.displayName ?? "") else { return false }
            guard draftHeadline == (p.headline ?? "") else { return false }
            guard draftAboutYou == (p.summary ?? "") else { return false }
            guard draftLookingFor == p.openTo.joined(separator: ", ") else { return false }
            guard draftInterests == p.interests.joined(separator: ", ") else { return false }
            guard draftCurrentRoles == p.activityTags.joined(separator: ", ") else { return false }
            guard draftRegion == p.regionTags.joined(separator: ", ") else { return false }
        } else {
            guard draftDisplayName == (ws?.ownerDisplayName ?? "") else { return false }
            guard draftHeadline.isEmpty else { return false }
            guard draftAboutYou.isEmpty else { return false }
            guard draftLookingFor.isEmpty else { return false }
            guard draftInterests.isEmpty else { return false }
            guard draftCurrentRoles.isEmpty else { return false }
            guard draftRegion.isEmpty else { return false }
        }
        return true
    }

    private func offeringRequiredDraftsMatchWorkspace() -> Bool {
        guard let ov = primaryOfferFromWorkspace() else {
            return offeringReqTitle.isEmpty
                && offeringReqSummary.isEmpty
                && offeringReqCategory.isEmpty
                && offeringReqRegionTags.isEmpty
                && offeringReqTags.isEmpty
        }
        let o = ov.offer
        return offeringReqTitle == o.title
            && offeringReqSummary == (o.summary ?? "")
            && offeringReqCategory == (o.category ?? "")
            && offeringReqRegionTags == o.regionTags.joined(separator: ", ")
            && offeringReqTags == o.tags.joined(separator: ", ")
    }

    private func offeringAdditionalDraftsMatchWorkspace() -> Bool {
        guard let o = primaryOfferFromWorkspace()?.offer else {
            return offAddContactName.isEmpty
                && offAddBusinessName.isEmpty
                && offAddEmail.isEmpty
                && offAddPhone.isEmpty
                && offAddWebsite.isEmpty
                && offAddPreferredMethod.isEmpty
                && offAddContactAvailability.isEmpty
                && offAddServiceAddress.isEmpty
                && offAddPriceDisplay.isEmpty
                && offAddPriceMin.isEmpty
                && offAddPriceMax.isEmpty
                && offAddCurrency.isEmpty
                && offAddPriceUnit.isEmpty
                && offAddPackages.isEmpty
                && offAddServiceAreaNote.isEmpty
                && offAddAvailabilityNote.isEmpty
                && offAddMinimumEngagement.isEmpty
                && offAddCancellation.isEmpty
                && offAddRefund.isEmpty
                && offAddWarranty.isEmpty
                && offAddRequiredInputs.isEmpty
                && offAddFAQs.isEmpty
                && offAddAutoPricing == false
                && offAddAutoAvailability == false
                && offAddAutoPolicies == true
                && offAddAutoServiceArea == true
                && offAddAutoFAQs == true
                && offAddAutoCustomQuote == true
        }

        let contact = o.contactInfo
        guard offAddContactName == (contact?.contactName ?? "") else { return false }
        guard offAddBusinessName == (contact?.businessName ?? "") else { return false }
        guard offAddEmail == (contact?.email ?? "") else { return false }
        guard offAddPhone == (contact?.phone ?? "") else { return false }
        guard offAddWebsite == (contact?.website ?? "") else { return false }
        guard offAddPreferredMethod == (contact?.preferredContactMethod?.rawValue ?? "") else { return false }
        guard offAddContactAvailability == (contact?.availabilityNote ?? "") else { return false }
        guard offAddServiceAddress == (contact?.serviceAddressOrArea ?? "") else { return false }

        let facts = o.commercialFacts
        guard offAddPriceDisplay == (facts.priceDisplay ?? "") else { return false }
        guard offAddPriceMin == profileShellDecimalText(facts.priceMin) else { return false }
        guard offAddPriceMax == profileShellDecimalText(facts.priceMax) else { return false }
        guard offAddCurrency == (facts.currency ?? "") else { return false }
        guard offAddPriceUnit == (facts.priceUnit ?? "") else { return false }
        guard offAddPackages == profileShellPackagesEditorText(from: facts.packages) else { return false }
        guard offAddServiceAreaNote == (facts.serviceAreaNote ?? "") else { return false }
        guard offAddAvailabilityNote == (facts.availabilityNote ?? "") else { return false }
        guard offAddMinimumEngagement == (facts.minimumEngagement ?? "") else { return false }
        guard offAddCancellation == (facts.cancellationPolicy ?? "") else { return false }
        guard offAddRefund == (facts.refundPolicy ?? "") else { return false }
        guard offAddWarranty == (facts.warrantyPolicy ?? "") else { return false }
        guard offAddRequiredInputs == facts.requiredBuyerInputs.joined(separator: "\n") else { return false }
        guard offAddFAQs == profileShellFAQsEditorText(from: facts.faqs) else { return false }

        let ap = facts.autoAnswerPolicy
        guard offAddAutoPricing == ap.canAnswerPricing else { return false }
        guard offAddAutoAvailability == ap.canAnswerAvailability else { return false }
        guard offAddAutoPolicies == ap.canAnswerPolicies else { return false }
        guard offAddAutoServiceArea == ap.canAnswerServiceArea else { return false }
        guard offAddAutoFAQs == ap.canAnswerFAQs else { return false }
        guard offAddAutoCustomQuote == ap.requiresApprovalForCustomQuote else { return false }

        return true
    }

    private func profileShellOfferTitleFailsPublishPlaceholderGuard(_ raw: String) -> Bool {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        return Self.invalidPublishOfferTitlesLowercased.contains(t.lowercased())
    }

    /// Mirrors `ExchangePublicNodeProfile`'s private `normalizedTerms` behavior for `offers` only (AnumCore unchanged).
    private func profileShellNormalizePublicOfferTerms(_ terms: [String]) -> [String] {
        Array(
            Set(
                terms
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { token in
                        !token.isEmpty
                            && !profileShellOfferTermIsSemanticStopWord(token)
                            && token.count <= 100
                    }
            )
        )
        .sorted()
    }

    private func profileShellOfferTermIsSemanticStopWord(_ token: String) -> Bool {
        [
            "the", "a", "an", "for", "to", "with", "and", "or", "of", "in", "on",
            "my", "me", "our", "their", "service", "services", "business", "company",
        ].contains(token)
    }

    /// Merges legacy `publicProfile.offers` with short terms from the primary `ExchangeOffer` (title, category, tags, regionTags). When no non-placeholder derived terms exist, returns `existing` unchanged (does not wipe legacy offers).
    private func derivedProfileOfferTerms(from offer: ExchangeOffer, existing: [String]) -> [String] {
        var derived: [String] = []

        let title = offer.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !profileShellOfferTitleFailsPublishPlaceholderGuard(title) {
            derived.append(title)
        }

        if let cat = offer.category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty,
           !profileShellOfferTitleFailsPublishPlaceholderGuard(cat) {
            derived.append(cat)
        }

        for t in offer.tags {
            let x = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !x.isEmpty, !profileShellOfferTitleFailsPublishPlaceholderGuard(x) else { continue }
            derived.append(x)
        }

        for r in offer.regionTags {
            let x = r.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !x.isEmpty, !profileShellOfferTitleFailsPublishPlaceholderGuard(x) else { continue }
            derived.append(x)
        }

        guard !derived.isEmpty else { return existing }

        var merged: [String] = []
        var seenLower = Set<String>()

        func appendPreservingFirstCasing(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard seenLower.insert(key).inserted else { return }
            merged.append(trimmed)
        }

        for e in existing {
            appendPreservingFirstCasing(e)
        }
        for d in derived {
            appendPreservingFirstCasing(d)
        }

        let cap = 24
        if merged.count > cap {
            merged = Array(merged.prefix(cap))
        }

        return merged
    }

    /// Persists `publicProfile.offers` when derived+merge normalization differs from the stored list. Skips extra saves when unchanged.
    @MainActor
    private func profileShellPersistDerivedPublicProfileOffersIfChanged(
        publicProfile: ExchangePublicNodeProfile,
        primaryOffer: ExchangeOffer
    ) async throws {
        let merged = derivedProfileOfferTerms(from: primaryOffer, existing: publicProfile.offers)

        let next = profileShellNormalizePublicOfferTerms(merged)
        let prev = profileShellNormalizePublicOfferTerms(publicProfile.offers)
        guard next != prev else { return }

        var p = publicProfile
        p.offers = next
        p.updatedAt = Date()
        try await services.exchangeFacade.savePublicProfile(p)
        await services.refreshSellerWorkspace()
    }

    /// When exactly one section has unsaved changes, present that sheet without re-hydrating (keeps in-memory drafts).
    private func profileShellPresentSingleUnsavedSheetIfApplicable() {
        let q = publicProfileQuickEditHasUnsavedSheetChanges
        let r = offeringRequiredHasUnsavedSheetChanges
        let a = offeringAdditionalHasUnsavedSheetChanges
        let count = (q ? 1 : 0) + (r ? 1 : 0) + (a ? 1 : 0)
        guard count == 1 else { return }
        if q {
            quickProfileSaveError = nil
            isPublicProfileQuickEditPresented = true
        } else if r {
            offeringRequiredSaveError = nil
            isOfferingRequiredSheetPresented = true
        } else if a {
            offeringAdditionalSaveError = nil
            hydrateOfferingAdditionalDrafts()
            offeringSheetAdditionalInitiallyExpanded = true
            isOfferingRequiredSheetPresented = true
        }
    }

    // MARK: - Prepared publish (same facade sequence as `SecretarySellerSurfaceEditorView.publishSurface`)

    /// Persists public profile + primary offer from Profile drafts, then publishes. Preserves profile/offer fields Profile does not edit.
    @MainActor
    private func publishPreparedProfileSurface() async {
        publicationPreparedError = nil

        if profileShellHasAnyUnsavedProfileSheetChanges {
            publicationPreparedError = "Save changes before publishing."
            profileShellPresentSingleUnsavedSheetIfApplicable()
            return
        }

        isPublicationFooterBusy = true
        defer { isPublicationFooterBusy = false }

        do {
            let nodeID = await services.exchangeNodeID ?? ""
            let trimmedNode = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedNode.isEmpty else {
                publicationPreparedError = "Missing local node ID."
                return
            }

            // Sync offering drafts from workspace so publish does not wipe fields Profile does not edit
            // (additional auto-flags, packages, contact, etc.) when those sheets were never opened this session.
            hydrateOfferingRequiredDrafts()
            hydrateOfferingAdditionalDrafts()

            var profile: ExchangePublicNodeProfile
            if let existing = services.sellerWorkspace?.publicProfile?.profile {
                profile = profileShellMergedForPreparedPublish(base: existing)
            } else {
                let ownerName = services.sellerWorkspace?.ownerDisplayName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let displayForCreate: String? = (ownerName?.isEmpty == false) ? ownerName : nilIfBlank(draftDisplayName)
                let created = try await services.exchangeFacade.createSellerProfile(
                    ownerNodeID: trimmedNode,
                    ownerDisplayName: displayForCreate
                )
                profile = profileShellMergedForPreparedPublish(base: created)
            }

            try await services.exchangeFacade.savePublicProfile(profile)

            let serviceAreaBatch = await services.resolveSellerServiceAreas(from: offeringReqRegionTags)
            serviceAreaResolveNotice = serviceAreaBatch.userNotice

            let offerToSave: ExchangeOffer
            if let existingOffer = primaryOfferFromWorkspace()?.offer {
                offerToSave = offerShellMergedForPreparedPublish(
                    base: existingOffer,
                    publicProfileID: profile.id,
                    serviceAreas: serviceAreaBatch.areas
                )
            } else {
                let draft = try await services.exchangeFacade.createDraftOffer(
                    ownerNodeID: trimmedNode,
                    publicProfileID: profile.id,
                    title: "New Offer",
                    summary: nil
                )
                offerToSave = offerShellMergedForPreparedPublish(
                    base: draft,
                    publicProfileID: profile.id,
                    serviceAreas: serviceAreaBatch.areas
                )
            }

            let publishTitle = offerToSave.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if profileShellOfferTitleFailsPublishPlaceholderGuard(publishTitle) {
                publicationPreparedError = "Add a real offer title before publishing."
                hydrateOfferingRequiredDrafts()
                isOfferingRequiredSheetPresented = true
                return
            }

            try await services.exchangeFacade.saveOffer(offerToSave)
            try await profileShellPersistDerivedPublicProfileOffersIfChanged(
                publicProfile: profile,
                primaryOffer: offerToSave
            )

            let resolvedOwnerDisplayName: String? = {
                if let dn = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty {
                    return dn
                }
                return nil
            }()

            let ownerForPublish: String?
            if let resolvedOwnerDisplayName, !resolvedOwnerDisplayName.isEmpty {
                ownerForPublish = resolvedOwnerDisplayName
            } else {
                ownerForPublish = await services.localExchangeDisplayName()
            }

            _ = try await services.exchangeFacade.publishSellerSurface(
                ownerNodeID: trimmedNode,
                ownerDisplayName: ownerForPublish,
                now: Date()
            )

            await services.refreshSellerWorkspace()
            services.requestSecretaryRefresh(.sellerWorkspaceChanged)
        } catch {
            publicationPreparedError = error.localizedDescription
        }
    }

    /// Applies Profile quick-edit drafts when non-blank; otherwise keeps persisted values (avoids wiping fields when drafts were never opened).
    private func profileShellMergedForPreparedPublish(base: ExchangePublicNodeProfile) -> ExchangePublicNodeProfile {
        var p = base

        if !draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.displayName = nilIfBlank(draftDisplayName)
        }

        if !draftHeadline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.headline = nilIfBlank(draftHeadline)
        }

        if !draftAboutYou.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.summary = nilIfBlank(draftAboutYou)
        }

        if !draftLookingFor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.openTo = splitCSV(draftLookingFor)
        }

        if !draftInterests.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.interests = splitCSV(draftInterests)
        }

        if !draftCurrentRoles.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.activityTags = splitCSV(draftCurrentRoles)
        }

        if !draftRegion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.regionTags = splitCSV(draftRegion)
        }

        p.updatedAt = Date()
        return p
    }

    /// Applies Offering — Required / Additional drafts. Call `hydrateOfferingRequiredDrafts` / `hydrateOfferingAdditionalDrafts` first when drafts may be stale. Preserves id, nodeID, semantic, fulfillment, metadata, createdAt, images, canonical region fields.
    private func offerShellMergedForPreparedPublish(
        base: ExchangeOffer,
        publicProfileID: String,
        serviceAreas: [ExchangeDeclaredServiceArea]
    ) -> ExchangeOffer {
        var o = base
        o.publicProfileID = publicProfileID

        let trimmedTitle = offeringReqTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            o.title = trimmedTitle
        }

        o.summary = nilIfBlank(offeringReqSummary)
        o.category = nilIfBlank(offeringReqCategory)
        o.tags = splitCSV(offeringReqTags)
        o.serviceAreas = serviceAreas
        ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&o)
        o.status = .active
        o.visibility = .publicDiscoverable
        o.commercialFacts = profileShellCommercialFactsFromAdditionalDrafts()
        o.contactInfo = profileShellContactFromAdditionalDrafts()
        o.updatedAt = Date()
        return o
    }

    private func profileShellDecimalText(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return (value as NSDecimalNumber).stringValue
    }

    private func profileShellPackagesEditorText(from packages: [ExchangeOffer.PackageOption]) -> String {
        packages.map { pkg in
            var line = pkg.title

            if let summary = pkg.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                line += " — \(summary)"
            }

            if let price = pkg.priceDisplay?.trimmingCharacters(in: .whitespacesAndNewlines), !price.isEmpty {
                line += " (\(price))"
            }

            return line
        }
        .joined(separator: "\n")
    }

    private func profileShellFAQsEditorText(from faqs: [ExchangeOffer.FAQ]) -> String {
        faqs.map { faq in
            """
            Q: \(faq.question)
            A: \(faq.answer)
            """
        }
        .joined(separator: "\n\n")
    }

    private func profileShellParsedPackagesFromEditor() -> [ExchangeOffer.PackageOption] {
        offAddPackages
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line -> ExchangeOffer.PackageOption in
                let parts = line.components(separatedBy: " — ")
                let rawTitle = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? line

                guard parts.count > 1 else {
                    return ExchangeOffer.PackageOption(
                        title: rawTitle.isEmpty ? "Package" : rawTitle,
                        summary: nil,
                        priceDisplay: nil
                    )
                }

                let remainder = parts.dropFirst().joined(separator: " — ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                var summary: String?
                var priceDisplay: String?

                if let openParen = remainder.lastIndex(of: "("),
                   let closeParen = remainder.lastIndex(of: ")"),
                   openParen < closeParen {
                    let prefix = remainder[..<openParen].trimmingCharacters(in: .whitespacesAndNewlines)
                    summary = prefix.isEmpty ? nil : String(prefix)

                    let priceChunk = remainder[remainder.index(after: openParen)..<closeParen]
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    priceDisplay = priceChunk.isEmpty ? nil : String(priceChunk)
                } else {
                    summary = remainder.isEmpty ? nil : remainder
                }

                return ExchangeOffer.PackageOption(
                    title: rawTitle.isEmpty ? "Package" : rawTitle,
                    summary: summary,
                    priceDisplay: priceDisplay
                )
            }
    }

    private func profileShellParsedFAQsFromEditor() -> [ExchangeOffer.FAQ] {
        var results: [ExchangeOffer.FAQ] = []
        var pendingQuestion: String?

        for rawLine in offAddFAQs.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                pendingQuestion = nil
                continue
            }

            let lower = line.lowercased()

            if lower.hasPrefix("q:") {
                pendingQuestion = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if lower.hasPrefix("a:"), let q = pendingQuestion, !q.isEmpty {
                let answer = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                pendingQuestion = nil

                guard !answer.isEmpty else { continue }

                results.append(ExchangeOffer.FAQ(question: q, answer: answer))
            }
        }

        return results
    }

    private func profileShellParseOptionalDecimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }

    private func profileShellNormalizedRequiredBuyerInputs() -> [String] {
        offAddRequiredInputs
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func profileShellCommercialFactsFromAdditionalDrafts() -> ExchangeOffer.CommercialFacts {
        ExchangeOffer.CommercialFacts(
            priceDisplay: nilIfBlank(offAddPriceDisplay),
            priceMin: profileShellParseOptionalDecimal(offAddPriceMin),
            priceMax: profileShellParseOptionalDecimal(offAddPriceMax),
            currency: nilIfBlank(offAddCurrency),
            priceUnit: nilIfBlank(offAddPriceUnit),
            packages: profileShellParsedPackagesFromEditor(),
            serviceAreaNote: nilIfBlank(offAddServiceAreaNote),
            availabilityNote: nilIfBlank(offAddAvailabilityNote),
            minimumEngagement: nilIfBlank(offAddMinimumEngagement),
            cancellationPolicy: nilIfBlank(offAddCancellation),
            refundPolicy: nilIfBlank(offAddRefund),
            warrantyPolicy: nilIfBlank(offAddWarranty),
            requiredBuyerInputs: profileShellNormalizedRequiredBuyerInputs(),
            faqs: profileShellParsedFAQsFromEditor(),
            autoAnswerPolicy: ExchangeOffer.AutoAnswerPolicy(
                canAnswerPricing: offAddAutoPricing,
                canAnswerAvailability: offAddAutoAvailability,
                canAnswerPolicies: offAddAutoPolicies,
                canAnswerServiceArea: offAddAutoServiceArea,
                canAnswerFAQs: offAddAutoFAQs,
                requiresApprovalForCustomQuote: offAddAutoCustomQuote
            )
        )
    }

    private func profileShellContactFromAdditionalDrafts() -> ExchangeOffer.ContactInfo? {
        let methodRaw = offAddPreferredMethod.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let preferred = ExchangeOffer.ContactInfo.PreferredMethod(rawValue: methodRaw)
        let contact = ExchangeOffer.ContactInfo(
            contactName: nilIfBlank(offAddContactName),
            businessName: nilIfBlank(offAddBusinessName),
            email: nilIfBlank(offAddEmail),
            phone: nilIfBlank(offAddPhone),
            website: nilIfBlank(offAddWebsite),
            preferredContactMethod: preferred,
            availabilityNote: nilIfBlank(offAddContactAvailability),
            serviceAddressOrArea: nilIfBlank(offAddServiceAddress)
        ).normalized()
        return contact.isEmpty ? nil : contact
    }

    private func splitCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Your offering rows

/// Fixed-size media strip cell; prevents `AsyncImage` from expanding the profile scroll column when previews load.
private struct ProfileShellMediaStripSlotLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: UnifyProfileMediaStripMetrics.slotHeight)
    }
}

private extension View {
    func profileShellMediaStripSlotLayout() -> some View {
        modifier(ProfileShellMediaStripSlotLayout())
    }

    func profileShellOfferPhotosStripSlotLayout() -> some View {
        modifier(ProfileShellOfferPhotosStripSlotLayout())
    }
}

/// Fixed-size compact offer photo strip cell inside “Your offering”.
private struct ProfileShellOfferPhotosStripSlotLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(
                width: ProfileShellOfferPhotosStripMetrics.slotWidth,
                height: ProfileShellOfferPhotosStripMetrics.slotHeight
            )
    }
}

/// V1 Profile notification row: iOS denied guidance (delivery state is on `AppServices`).
private enum NotificationPermissionV1Alert: Identifiable {
    case deniedInSystemSettings

    var id: String {
        switch self {
        case .deniedInSystemSettings: return "deniedInSystemSettings"
        }
    }
}

private struct ProfileShellOfferingTapRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    var showRequiredCapsule: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if showRequiredCapsule {
                            Text("Required")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkOrange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(SecretaryTheme.darkOrange.opacity(0.22))
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .stroke(SecretaryTheme.darkOrange.opacity(0.45), lineWidth: 1)
                                        }
                                )
                        }
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile settings subpages (Offering — Required presentation pattern)

private struct ProfileGuardiansSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var store: SupportStore

    var body: some View {
        NavigationStack {
            ScrollView {
                GuardiansContentView(store: store)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Guardians")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(SecretaryTheme.darkOrange)
        .task {
            await store.loadProducts()
            await store.refreshEntitlements()
            await store.refreshAutoRenewStatus()
        }
    }
}

private struct ProfileSpecialThanksSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                SpecialThanksContentView()
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Special Thanks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(SecretaryTheme.darkOrange)
    }
}

private struct ProfileHelpSheet: View {
    @Binding var isPresented: Bool
    @State private var showCopied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                HelpContentView(showCopied: $showCopied)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(SecretaryTheme.darkOrange)
        .alert("Copied", isPresented: $showCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("admin@unifynow.ca copied to clipboard.")
        }
    }
}

private struct ProfileDataPrivacySheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                ProfileDataPrivacyContentView()
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Data & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(SecretaryTheme.darkOrange)
    }
}

/// Inner body for Data & Privacy (profile shell sheet; matches Help / Guardians panel pattern).
private struct ProfileDataPrivacyContentView: View {
    @EnvironmentObject private var services: AppServices

    @State private var isActionInFlight = false
    @State private var showDeleteSecretaryDataConfirm = false
    @State private var showDeleteAllLocalDataConfirm = false
    @State private var showResetFederationIdentityConfirm = false
    @State private var showResetFederationIdentityFinalConfirm = false
    @State private var showRemoveRemotePublishedDataConfirm = false
    @State private var resultAlert: ProfileDataPrivacyResultAlert?

    var body: some View {
        VStack(spacing: 12) {
            UnifyDarkCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    dataPrivacySubsectionHeader("Secretary Mode")

                    Button {
                        guard !isActionInFlight else { return }
                        showDeleteSecretaryDataConfirm = true
                    } label: {
                        ProfileShellDestructiveActionRow(
                            icon: "trash",
                            title: "Delete Secretary Data on This Device",
                            subtitle: "Deletes local Secretary threads, DMs, inbox/outbox, drafts, discovery state, notifications, and local public profile drafts from this device. Does not delete Companion data, reset federation identity, or delete remote published data.",
                            isBusy: isActionInFlight
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isActionInFlight)

                    dataPrivacyCardDivider

                    dataPrivacySubsectionHeader("Whole App")

                    Button {
                        guard !isActionInFlight else { return }
                        showDeleteAllLocalDataConfirm = true
                    } label: {
                        ProfileShellDestructiveActionRow(
                            icon: "trash.fill",
                            title: "Delete All Local Unify Data",
                            subtitle: "Deletes both Companion and Secretary data stored on this device. Does not reset federation identity or delete remote published data.",
                            isBusy: isActionInFlight
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isActionInFlight)

                    dataPrivacyCardDivider

                    dataPrivacySubsectionHeader("Identity")

                    Button {
                        guard !isActionInFlight else { return }
                        showResetFederationIdentityConfirm = true
                    } label: {
                        ProfileShellDestructiveActionRow(
                            icon: "person.crop.circle.badge.minus",
                            title: "Reset Federation Identity",
                            subtitle: "Creates a new local federation identity. Existing contacts may no longer recognize this device. This does not delete remote data already published or sent.",
                            isBusy: isActionInFlight
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isActionInFlight)

                    if isActionInFlight {
                        dataPrivacyCardDivider
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(SecretaryTheme.darkOrange)
                            Text("Working…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            UnifyDarkCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    dataPrivacySubsectionHeader("Public / Remote Data")
                        .padding(.top, 4)

                    Text(remotePublishedDataStatusLine)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)

                    Button {
                        guard !isActionInFlight, canRemoveRemotePublishedData else { return }
                        showRemoveRemotePublishedDataConfirm = true
                    } label: {
                        ProfileShellDestructiveActionRow(
                            icon: "eye.slash",
                            title: "Remove from Public Directory",
                            subtitle: remotePublishedDataActionSubtitle,
                            isBusy: isActionInFlight
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isActionInFlight || !canRemoveRemotePublishedData)

                    if isActionInFlight {
                        dataPrivacyCardDivider
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(SecretaryTheme.darkOrange)
                            Text("Working…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Text("Companion data is managed separately from Room Options.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .alert("Delete Secretary Data on This Device?", isPresented: $showDeleteSecretaryDataConfirm) {
            Button("Delete Secretary Data", role: .destructive) {
                Task { await performDeleteSecretaryDataOnDevice() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes local Secretary threads, DMs, inbox/outbox, drafts, discovery state, notifications, and local public profile drafts from this device. It does not delete Companion data, reset your federation identity, or delete remote published data.")
        }
        .alert("Delete All Local Unify Data?", isPresented: $showDeleteAllLocalDataConfirm) {
            Button("Delete Local Data", role: .destructive) {
                Task { await performDeleteAllLocalUnifyData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes both Companion and Secretary data stored on this device. It does not reset your federation identity or delete remote published data.")
        }
        .alert("Reset Federation Identity?", isPresented: $showResetFederationIdentityConfirm) {
            Button("Reset Identity", role: .destructive) {
                showResetFederationIdentityFinalConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This creates a new local federation identity. Existing contacts may no longer recognize this device. This does not delete remote data already published or sent.")
        }
        .alert("Confirm identity reset", isPresented: $showResetFederationIdentityFinalConfirm) {
            Button("Reset Identity", role: .destructive) {
                Task { await performResetFederationIdentity() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action is separate from deleting local data. Resetting your identity cannot be undone from the app.")
        }
        .alert("Remove from Public Directory?", isPresented: $showRemoveRemotePublishedDataConfirm) {
            Button("Remove from Directory", role: .destructive) {
                Task { await performRemoveRemotePublishedData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your published profile, offers, and discovery documents from the federation server. Local drafts on this device are kept. Messages you already sent are not deleted.")
        }
        .alert(item: $resultAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var dataPrivacyCardDivider: some View {
        Rectangle()
            .fill(SecretaryTheme.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 14)
    }

    private func dataPrivacySubsectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkMutedText)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private var remotePublishedDataStatusLine: String {
        let ws = services.sellerWorkspace
        if let statusText = ws?.publicProfile?.publicationStatusText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !statusText.isEmpty {
            return "Directory status: \(statusText)."
        }
        let statusLine = ws?.statusLine.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !statusLine.isEmpty {
            return "Directory status: \(statusLine)."
        }
        if ws?.publicProfile != nil {
            return "Directory status: Not published."
        }
        return "Set up your public profile before publishing or removing directory data."
    }

    private var canRemoveRemotePublishedData: Bool {
        switch services.sellerWorkspace?.publicationState?.status {
        case .published, .stale, .failed:
            return true
        default:
            return false
        }
    }

    private var remotePublishedDataActionSubtitle: String {
        if canRemoveRemotePublishedData {
            return "Removes your published profile, offers, and discovery documents from the federation server. Local drafts on this device are kept. Orphaned uploaded images are cleaned up when possible."
        }
        switch services.sellerWorkspace?.publicationState?.status {
        case .pendingUnpublish:
            return "Your seller surface is being withdrawn from the directory."
        case .paused, .archived:
            return "Your seller surface is not currently listed in the public directory."
        case .pendingPublish:
            return "Wait for publishing to finish before removing directory data."
        case .published, .stale, .failed:
            return "Removes your published profile, offers, and discovery documents from the federation server."
        default:
            return "Nothing is published to the directory yet."
        }
    }

    @MainActor
    private func performRemoveRemotePublishedData() async {
        guard !isActionInFlight else { return }
        isActionInFlight = true
        defer { isActionInFlight = false }

        do {
            try await services.unpublishRemotePublishedData()
            resultAlert = ProfileDataPrivacyResultAlert(
                title: "Removed from directory",
                message: "Your profile, offers, and discovery documents are no longer listed on the federation server. Local drafts on this device were kept."
            )
        } catch {
            resultAlert = ProfileDataPrivacyResultAlert(
                title: "Couldn't remove published data",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func performDeleteSecretaryDataOnDevice() async {
        guard !isActionInFlight else { return }
        isActionInFlight = true
        defer { isActionInFlight = false }

        let report = await services.wipeSecretaryLocalDataOnly()
        await services.refreshSellerWorkspace()
        presentResult(
            title: report.failures.isEmpty ? "Secretary data deleted" : "Secretary data partially deleted",
            report: report
        )
    }

    @MainActor
    private func performDeleteAllLocalUnifyData() async {
        guard !isActionInFlight else { return }
        isActionInFlight = true
        defer { isActionInFlight = false }

        let report = await services.wipeAllLocalUnifyData()
        await services.refreshSellerWorkspace()
        presentResult(
            title: report.failures.isEmpty ? "Local data deleted" : "Local data partially deleted",
            report: report
        )
    }

    @MainActor
    private func performResetFederationIdentity() async {
        guard !isActionInFlight else { return }
        isActionInFlight = true
        defer { isActionInFlight = false }

        do {
            let report = try services.resetFederationIdentity()
            await services.refreshSellerWorkspace()
            await services.refreshExchangeIdentityDebugSummary()
            presentResult(
                title: report.failures.isEmpty ? "Federation identity reset" : "Identity reset incomplete",
                report: report
            )
        } catch {
            resultAlert = ProfileDataPrivacyResultAlert(
                title: "Couldn’t reset identity",
                message: error.localizedDescription
            )
        }
    }

    private func presentResult(title: String, report: UnifyDataLifecycleReport) {
        resultAlert = ProfileDataPrivacyResultAlert(
            title: title,
            message: conciseDataPrivacySummary(for: report)
        )
    }

    private func conciseDataPrivacySummary(for report: UnifyDataLifecycleReport) -> String {
        if !report.failures.isEmpty {
            let detail = report.failures.prefix(2).joined(separator: " ")
            return "Completed with \(report.failures.count) issue\(report.failures.count == 1 ? "" : "s"). \(detail)"
        }

        var parts: [String] = []
        if !report.removedPaths.isEmpty {
            parts.append("\(report.removedPaths.count) local file\(report.removedPaths.count == 1 ? "" : "s") removed")
        }
        if !report.removedUserDefaultsKeys.isEmpty {
            parts.append("\(report.removedUserDefaultsKeys.count) setting\(report.removedUserDefaultsKeys.count == 1 ? "" : "s") cleared")
        }
        if parts.isEmpty {
            return "The operation finished on this device. Remote published data was not deleted."
        }
        return parts.joined(separator: " · ") + ". Remote published data was not deleted."
    }
}

// MARK: - Offering additional fields

private struct OfferingAdditionalFieldsContent: View {
    @Binding var contactName: String
    @Binding var contactBusinessName: String
    @Binding var contactEmail: String
    @Binding var contactPhone: String
    @Binding var contactWebsite: String
    @Binding var contactPreferredMethod: String
    @Binding var contactAvailabilityNote: String
    @Binding var contactServiceAddressOrArea: String
    @Binding var priceDisplay: String
    @Binding var priceMinText: String
    @Binding var priceMaxText: String
    @Binding var currency: String
    @Binding var priceUnit: String
    @Binding var packagesText: String
    @Binding var serviceAreaNote: String
    @Binding var availabilityNote: String
    @Binding var minimumEngagement: String
    @Binding var cancellationPolicy: String
    @Binding var refundPolicy: String
    @Binding var warrantyPolicy: String
    @Binding var requiredInputsText: String
    @Binding var faqsText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            addlSectionHeader("Contact")
            addlSingleLine("Name", $contactName, "Contact name")
            addlSingleLine("Business", $contactBusinessName, "Business or studio name")
            addlSingleLine("Email", $contactEmail, "you@example.com")
            addlSingleLine("Phone", $contactPhone, "+1 …")
            addlSingleLine("Website", $contactWebsite, "https://…")
            addlSingleLine("Preferred method", $contactPreferredMethod, "email, phone, website, message, any")
            addlMultiline("Contact availability note", $contactAvailabilityNote, "When you typically respond")
            addlMultiline("Service address / area", $contactServiceAddressOrArea, "Where you meet or ship from")

            addlSectionHeader("Pricing & packages")
            addlSingleLine("Price (display)", $priceDisplay, "e.g. from $120 / hr")
            addlSingleLine("Min", $priceMinText, "Optional minimum price")
            addlSingleLine("Max", $priceMaxText, "Optional maximum price")
            addlSingleLine("Currency", $currency, "USD, CAD, …")
            addlSingleLine("Unit", $priceUnit, "hour, session, project, …")
            addlMultiline("Packages", $packagesText, "One package per line: Title — summary (price)")

            addlSectionHeader("Service & availability")
            addlMultiline("Service area note", $serviceAreaNote, "Regions, travel radius, remote")
            addlMultiline("Availability note", $availabilityNote, "Lead times, seasons, capacity")
            addlMultiline("Minimum engagement", $minimumEngagement, "Minimum booking or spend")

            addlSectionHeader("Policies")
            addlMultiline("Cancellation", $cancellationPolicy, "")
            addlMultiline("Refund", $refundPolicy, "")
            addlMultiline("Warranty", $warrantyPolicy, "")

            addlSectionHeader("Buyer intake & FAQs")
            addlMultiline("What buyers should provide", $requiredInputsText, "One item per line")
            addlMultiline("FAQs (Q: / A: blocks)", $faqsText, "Q: …\nA: …")
        }
    }

    private func addlSectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
            Text("Optional")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    UnifyGlassCapsuleChrome()
                }
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.55), lineWidth: 1)
                )
        }
        .padding(.top, 4)
    }

    private func addlSingleLine(_ title: String, _ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(SecretaryTheme.darkMutedText))
                .font(.system(size: 15.5))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(addlFieldChrome)
        }
    }

    private func addlMultiline(_ title: String, _ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(prompt)
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
                TextField("", text: text, axis: .vertical)
                    .font(.system(size: 15.5))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .lineLimit(3...10)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(addlFieldChrome)
        }
    }

    private var addlFieldChrome: some View {
        UnifyGlassTextFieldChrome(cornerRadius: 14, strokeOpacity: 0.72)
    }
}

// MARK: - Offering — Required sheet

private struct OfferingRequiredSheet: View {
    @Binding var isPresented: Bool
    @Binding var draftTitle: String
    @Binding var draftSummary: String
    @Binding var draftCategory: String
    @Binding var draftRegionTags: String
    @Binding var draftTags: String
    @Binding var contactName: String
    @Binding var contactBusinessName: String
    @Binding var contactEmail: String
    @Binding var contactPhone: String
    @Binding var contactWebsite: String
    @Binding var contactPreferredMethod: String
    @Binding var contactAvailabilityNote: String
    @Binding var contactServiceAddressOrArea: String
    @Binding var priceDisplay: String
    @Binding var priceMinText: String
    @Binding var priceMaxText: String
    @Binding var currency: String
    @Binding var priceUnit: String
    @Binding var packagesText: String
    @Binding var serviceAreaNote: String
    @Binding var availabilityNote: String
    @Binding var minimumEngagement: String
    @Binding var cancellationPolicy: String
    @Binding var refundPolicy: String
    @Binding var warrantyPolicy: String
    @Binding var requiredInputsText: String
    @Binding var faqsText: String
    var initialAdditionalExpanded: Bool
    @Binding var isSavingRequired: Bool
    @Binding var isSavingAdditional: Bool
    @Binding var requiredSaveError: String?
    @Binding var additionalSaveError: String?
    @Binding var serviceAreaNotice: String?

    var onSave: () async -> Void

    @State private var isAdditionalExpanded = false

    private var isSaving: Bool {
        isSavingRequired || isSavingAdditional
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let requiredSaveError, !requiredSaveError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(requiredSaveError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                    }

                    if let serviceAreaNotice,
                       !serviceAreaNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(serviceAreaNotice)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    offeringReqField(
                        title: "Offer title",
                        badge: .required,
                        prompt: "Short name for what you offer",
                        text: $draftTitle,
                        multiline: false
                    )
                    offeringReqField(
                        title: "Offer details",
                        badge: .recommended,
                        prompt: "One or two sentences buyers will see first",
                        text: $draftSummary,
                        multiline: true
                    )
                    offeringReqField(
                        title: "Category",
                        badge: .recommended,
                        prompt: "e.g. consulting, repairs, coaching",
                        text: $draftCategory,
                        multiline: false
                    )
                    offeringReqField(
                        title: "Service areas",
                        badge: .recommended,
                        prompt: "Comma-separated cities or regions you serve (e.g. Aurora, GTA, Online)",
                        text: $draftRegionTags,
                        multiline: false
                    )
                    offeringReqField(
                        title: "Tags",
                        badge: .recommended,
                        prompt: "Comma-separated keywords",
                        text: $draftTags,
                        multiline: false
                    )

                    offeringAdditionalExpandableCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Offering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await onSave() } }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .disabled(isSaving)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                isAdditionalExpanded = initialAdditionalExpanded
            }
        }
        .tint(SecretaryTheme.darkOrange)
    }

    private var offeringAdditionalExpandableCard: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAdditionalExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Additional")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        Spacer(minLength: 0)
                        Image(systemName: isAdditionalExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isAdditionalExpanded {
                    if let additionalSaveError,
                       !additionalSaveError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(additionalSaveError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                            .padding(.top, 8)
                    }

                    OfferingAdditionalFieldsContent(
                        contactName: $contactName,
                        contactBusinessName: $contactBusinessName,
                        contactEmail: $contactEmail,
                        contactPhone: $contactPhone,
                        contactWebsite: $contactWebsite,
                        contactPreferredMethod: $contactPreferredMethod,
                        contactAvailabilityNote: $contactAvailabilityNote,
                        contactServiceAddressOrArea: $contactServiceAddressOrArea,
                        priceDisplay: $priceDisplay,
                        priceMinText: $priceMinText,
                        priceMaxText: $priceMaxText,
                        currency: $currency,
                        priceUnit: $priceUnit,
                        packagesText: $packagesText,
                        serviceAreaNote: $serviceAreaNote,
                        availabilityNote: $availabilityNote,
                        minimumEngagement: $minimumEngagement,
                        cancellationPolicy: $cancellationPolicy,
                        refundPolicy: $refundPolicy,
                        warrantyPolicy: $warrantyPolicy,
                        requiredInputsText: $requiredInputsText,
                        faqsText: $faqsText
                    )
                    .padding(.top, 10)
                }
            }
            .padding(14)
        }
    }

    private enum FieldBadge {
        case required
        case recommended
    }

    private func offeringReqField(
        title: String,
        badge: FieldBadge,
        prompt: String,
        text: Binding<String>,
        multiline: Bool
    ) -> some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    badgeView(badge)
                }
                if multiline {
                    ZStack(alignment: .topLeading) {
                        if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(prompt)
                                .font(.system(size: 15))
                                .foregroundStyle(SecretaryTheme.darkMutedText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .allowsHitTesting(false)
                        }
                        TextField("", text: text, axis: .vertical)
                            .font(.system(size: 15.5))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(3...8)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                    .background {
                        UnifyGlassTextFieldChrome(cornerRadius: 14, strokeOpacity: 0.72)
                    }
                } else {
                    TextField("", text: text, prompt: Text(prompt).foregroundStyle(SecretaryTheme.darkMutedText))
                        .font(.system(size: 15.5))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background {
                            UnifyGlassTextFieldChrome(cornerRadius: 14, strokeOpacity: 0.72)
                        }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: FieldBadge) -> some View {
        switch badge {
        case .required:
            Text("Required")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.darkOrange.opacity(0.22))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(SecretaryTheme.darkOrange.opacity(0.45), lineWidth: 1)
                        }
                )
        case .recommended:
            Text("Recommended")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    UnifyGlassCapsuleChrome()
                }
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.55), lineWidth: 1)
                )
        }
    }
}

// MARK: - Secretary auto inquiry & replies sheet

private struct SecretaryAutoInquiryRepliesSheet: View {
    @EnvironmentObject private var services: AppServices
    @Binding var isPresented: Bool
    @Binding var autoAnswerPricing: Bool
    @Binding var autoAnswerAvailability: Bool
    @Binding var autoAnswerPolicies: Bool
    @Binding var autoAnswerServiceArea: Bool
    @Binding var autoAnswerFAQs: Bool
    @Binding var autoAnswerCustomQuote: Bool
    @Binding var isSaving: Bool
    @Binding var saveError: String?

    var onSave: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(SecretaryStyleSettingsView.safeAutoFollowUpsDescription)
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle(isOn: Binding(
                        get: { services.allowSafeAutoFollowUps },
                        set: { services.setAllowSafeAutoFollowUps($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SecretaryStyleSettingsView.safeAutoFollowUpsTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkPrimaryText)

                            Text("When off, drafts are prepared but you approve every send.")
                                .font(.system(size: 13.5))
                                .foregroundStyle(SecretaryTheme.darkMutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(SecretaryTheme.darkOrange)

                    autoInquiryRepliesStatusLine

                    autoInquirySectionDivider

                    autoInquirySectionHeader("Offer auto-answer")
                    Text("Choose which offer questions your secretary can answer from your published offer details.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let saveError, !saveError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(saveError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                    }

                    Toggle("Auto-answer pricing questions", isOn: $autoAnswerPricing)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Toggle("Auto-answer availability questions", isOn: $autoAnswerAvailability)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Toggle("Auto-answer policy questions", isOn: $autoAnswerPolicies)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Toggle("Auto-answer service area questions", isOn: $autoAnswerServiceArea)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Toggle("Auto-answer FAQs", isOn: $autoAnswerFAQs)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    Toggle("Require approval for custom quotes", isOn: $autoAnswerCustomQuote)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Auto inquiry & replies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await onSave() } }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .disabled(isSaving)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(SecretaryTheme.darkOrange)
    }

    private var autoInquiryRepliesStatusLine: some View {
        let on = services.allowSafeAutoFollowUps
        return HStack(spacing: 8) {
            Image(systemName: on ? "checkmark.circle" : "pause.circle")
                .font(.system(size: 14, weight: .semibold))
            Text(on ? "Auto inquiry & replies are on." : "Auto inquiry & replies are off.")
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(on ? SecretaryTheme.darkOrange : SecretaryTheme.darkSecondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(
                    on
                        ? SecretaryTheme.darkOrangeSoft.opacity(0.42)
                        : SecretaryTheme.darkSurfaceStrong.opacity(0.5)
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    on
                        ? SecretaryTheme.darkOrange.opacity(0.35)
                        : SecretaryTheme.darkStroke.opacity(0.72),
                    lineWidth: 1
                )
        )
    }

    private var autoInquirySectionDivider: some View {
        Rectangle()
            .fill(SecretaryTheme.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private func autoInquirySectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkPrimaryText)
            .padding(.top, 4)
    }
}

// MARK: - Public profile quick edit sheet

private struct PublicProfileQuickEditSheet: View {
    @Binding var isPresented: Bool
    @Binding var draftDisplayName: String
    @Binding var draftHeadline: String
    @Binding var draftAboutYou: String
    @Binding var draftLookingFor: String
    @Binding var draftInterests: String
    @Binding var draftCurrentRoles: String
    @Binding var draftRegion: String
    @Binding var isSaving: Bool
    @Binding var saveError: String?

    var onSave: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Set how people see you in Discovery.")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let saveError, !saveError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(saveError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    quickFieldCard(title: "Name", icon: "person.fill") {
                        quickTextField(
                            text: $draftDisplayName,
                            prompt: "e.g. Riverdale Studio"
                        )
                    }

                    quickFieldCard(title: "Short Intro", icon: "text.quote") {
                        quickTextField(
                            text: $draftHeadline,
                            prompt: "e.g. Local design & build partner"
                        )
                    }

                    quickFieldCard(title: "About You", icon: "text.alignleft") {
                        quickMultilineField(
                            text: $draftAboutYou,
                            prompt: "A few sentences about what you do and how you work."
                        )
                    }

                    tagPairSection

                    tagPairSectionSecondRow
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Public profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await onSave() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .disabled(isSaving)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(SecretaryTheme.darkOrange)
    }

    private var tagPairSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                quickTagCard(title: "Looking For", icon: "binoculars.fill", prompt: "e.g. referrals, partners, gigs", text: $draftLookingFor)
                quickTagCard(title: "Interests", icon: "heart.fill", prompt: "e.g. sustainability, craft coffee", text: $draftInterests)
            }
            VStack(alignment: .leading, spacing: 12) {
                quickTagCard(title: "Looking For", icon: "binoculars.fill", prompt: "e.g. referrals, partners, gigs", text: $draftLookingFor)
                quickTagCard(title: "Interests", icon: "heart.fill", prompt: "e.g. sustainability, craft coffee", text: $draftInterests)
            }
        }
    }

    private var tagPairSectionSecondRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                quickTagCard(title: "Current Roles", icon: "person.3.fill", prompt: "e.g. founder, mentor, volunteer", text: $draftCurrentRoles)
                quickTagCard(title: "Region", icon: "mappin.and.ellipse", prompt: "e.g. PNW, NYC metro, remote", text: $draftRegion)
            }
            VStack(alignment: .leading, spacing: 12) {
                quickTagCard(title: "Current Roles", icon: "person.3.fill", prompt: "e.g. founder, mentor, volunteer", text: $draftCurrentRoles)
                quickTagCard(title: "Region", icon: "mappin.and.ellipse", prompt: "e.g. PNW, NYC metro, remote", text: $draftRegion)
            }
        }
    }

    private func quickFieldCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }
                content()
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickTagCard(title: String, icon: String, prompt: String, text: Binding<String>) -> some View {
        quickFieldCard(title: title, icon: icon) {
            quickTextField(text: text, prompt: prompt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickTextField(text: Binding<String>, prompt: String) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(SecretaryTheme.darkMutedText))
            .font(.system(size: 15.5))
            .foregroundStyle(SecretaryTheme.darkPrimaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background {
                UnifyGlassTextFieldChrome(cornerRadius: 14, strokeOpacity: 0.72)
            }
    }

    private func quickMultilineField(text: Binding<String>, prompt: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(prompt)
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
            TextField("", text: text, axis: .vertical)
                .font(.system(size: 15.5))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .lineLimit(4...12)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background {
            UnifyGlassTextFieldChrome(cornerRadius: 14, strokeOpacity: 0.72)
        }
    }
}

/// Keeps the profile tab column from inheriting the media strip’s full intrinsic width (fixes clipped / “zoomed” edges).
/// Skips capping when `measuredWidth` is tiny so the first `GeometryReader` pass never applies `maxWidth: 0`.
private struct ProfileRootColumnWidthCap: ViewModifier {
    let measuredWidth: CGFloat

    func body(content: Content) -> some View {
        if measuredWidth > 64 {
            content.frame(maxWidth: measuredWidth - 32, alignment: .leading)
        } else {
            content
        }
    }
}

// MARK: - Presentation Placeholder

private enum ProfileShellLayout {
    static let heroAvatarDiameter: CGFloat = 124
}

private enum ProfileShellPlaceholder {
    static let fallbackDisplayName = "Your workspace"
    static let fallbackPublicHeadline = "Public surface and offers appear here once your seller workspace is loaded."

    static let missingWorkspaceHint = "Connect your workspace to see live details · presentation shell"
    static let publicSurfaceNoProfile = "No public profile on this workspace snapshot yet"
    static let publicSurfaceNoHeadline = "Add a headline or summary on your public surface"
    static let reachabilityPlaceholder = "Reachability copy will follow your discoverability settings"
}

private struct ProfileDataPrivacyResultAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Destructive local-data action row for the profile Data & Privacy section.
private struct ProfileShellDestructiveActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isBusy: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.red.opacity(0.88))
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isBusy {
                ProgressView()
                    .tint(SecretaryTheme.darkOrange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

/// Visual-only row content for profile settings rows (tappable `Button` labels).
private struct ProfileShellSettingRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String?
    var showsDisclosure: Bool = true
    /// When `nil`, uses `SecretaryTheme.darkSecondaryText` (matches Guardians / Help rows).
    var iconTint: Color? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(iconTint ?? SecretaryTheme.darkSecondaryText)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

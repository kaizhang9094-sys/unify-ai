import SwiftUI
import PhotosUI
import AnumCore

#if canImport(UIKit)
import UIKit
#endif

struct SecretarySellerSurfaceEditorView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var serviceAreaResolveNotice: String?
    @State private var loadTask: Task<Void, Never>?

    @State private var sellerWorkspaceSnapshot: ExchangeModels.SellerWorkspaceSummary?
    @State private var sellerValidationIssuesSnapshot: [ExchangeSellerValidationIssue] = []

    @State private var profileID: String?
    @State private var displayName = ""
    @State private var headline = ""
    @State private var summary = ""
    @State private var openToText = ""
    @State private var offersText = ""
    @State private var interestText = ""
    @State private var activityText = ""
    @State private var regionText = ""

    @State private var offerID: String?
    @State private var offerTitle = ""
    @State private var offerSummary = ""
    @State private var offerCategory = ""
    @State private var offerTagsText = ""
    @State private var offerRegionText = ""
    @State private var hasHydratedForm = false

    // MARK: - Commercial facts

    @State private var commercialPriceDisplay = ""
    @State private var commercialPriceMinText = ""
    @State private var commercialPriceMaxText = ""
    @State private var commercialCurrency = ""
    @State private var commercialPriceUnit = ""
    @State private var commercialPackagesText = ""
    @State private var commercialServiceAreaNote = ""
    @State private var commercialAvailabilityNote = ""
    @State private var commercialMinimumEngagement = ""
    @State private var commercialCancellationPolicy = ""
    @State private var commercialRefundPolicy = ""
    @State private var commercialWarrantyPolicy = ""
    @State private var commercialRequiredInputsText = ""
    @State private var commercialFAQsText = ""
    @State private var autoAnswerPricing = false
    @State private var autoAnswerAvailability = false
    @State private var autoAnswerPolicies = true
    @State private var autoAnswerServiceArea = true
    @State private var autoAnswerFAQs = true
    @State private var autoAnswerCustomQuoteApproval = true

    // MARK: - Offer contact info (public, optional)

    @State private var contactName = ""
    @State private var contactBusinessName = ""
    @State private var contactEmail = ""
    @State private var contactPhone = ""
    @State private var contactWebsite = ""
    @State private var contactPreferredMethod = ""
    @State private var contactAvailabilityNote = ""
    @State private var contactServiceAddressOrArea = ""

    // MARK: - Public media

    @State private var profileImageURL: String?
    @State private var offerImageURL: String?

    @State private var profilePhotoItem: PhotosPickerItem?
    @State private var offerPhotoItem: PhotosPickerItem?

    @State private var isUploadingProfileImage = false
    @State private var isUploadingOfferImage = false
    @State private var isUploadingOfferGalleryImage = false

    @State private var offerGalleryImageURLs: [String] = []
    @State private var offerGalleryPhotoItem: PhotosPickerItem?

    @State private var imageGalleryPresentation: SecretaryImageGalleryPresentation?

    @State private var mediaUploadError: String?

    @State private var photoCropSourceImage: UIImage?
    @State private var showPhotoCropper = false
    @State private var pendingPhotoCropTarget: SellerEditorPhotoCropTarget?

    #if canImport(UIKit)
    @State private var profileImagePreview: UIImage?
    @State private var offerImagePreview: UIImage?
    #endif

    @FocusState private var focusedField: EditorField?

    private enum SellerEditorPhotoCropTarget {
        case profile
        case offerHero
        case offerGallery
    }

    private enum EditorField: Hashable {
        case displayName
        case headline
        case summary
        case openTo
        case broadOffers
        case interests
        case activities
        case regions
        case offerTitle
        case offerSummary
        case offerCategory
        case offerTags
        case offerRegions

        case contactName
        case contactBusinessName
        case contactEmail
        case contactPhone
        case contactWebsite
        case contactPreferredMethod
        case contactServiceAddressOrArea
        case contactAvailabilityNote

        case commercialPriceDisplay
        case commercialPriceMin
        case commercialPriceMax
        case commercialCurrency
        case commercialPriceUnit
        case commercialPackages
        case commercialServiceAreaNote
        case commercialAvailabilityNote
        case commercialMinimumEngagement
        case commercialCancellationPolicy
        case commercialRefundPolicy
        case commercialWarrantyPolicy
        case commercialRequiredInputsText
        case commercialFAQsText
    }

    /// Shared dark premium chrome for this editor (nested `Form*` types can reference this enum).
    private enum SellerEditorChrome {
        @ViewBuilder
        static func darkCard<Content: View>(
            cornerRadius: CGFloat = 28,
            @ViewBuilder content: () -> Content
        ) -> some View {
            let inner = content()
            UnifyDarkCard(cornerRadius: cornerRadius) {
                inner
                    .padding(SecretaryTheme.Layout.cardInteriorPadding)
            }
        }

        @ViewBuilder
        static func sectionHeader(title: String, systemImage: String) -> some View {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SecretaryTheme.darkOrangeSoft.opacity(0.38))
                    )
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            UnifyDarkBackground(showsSubtleVignette: true)

            LinearGradient(
                colors: [
                    SecretaryTheme.darkOrange.opacity(0.10),
                    SecretaryTheme.darkOrange.opacity(0.03),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    mediaUploadErrorBanner
                    publicIdentitySection
                    activeOfferingSection
                    bottomActionsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .tint(SecretaryTheme.darkOrange)
        .task {
            scheduleLoad(delayNanoseconds: 0)
        }
        .onAppear {
            services.setSellerSurfaceEditorPresented(true)
        }
        .onDisappear {
            services.setSellerSurfaceEditorPresented(false)
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: profilePhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                await presentSellerEditorPhotoCrop(from: newItem, target: .profile)
                profilePhotoItem = nil
            }
        }
        .onChange(of: offerPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                await presentSellerEditorPhotoCrop(from: newItem, target: .offerHero)
                offerPhotoItem = nil
            }
        }
        .onChange(of: offerGalleryPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                await handleOfferGalleryPhotoSelection(newItem)
            }
        }
        .sharedPhotoCropperCover(
            isPresented: $showPhotoCropper,
            sourceImage: photoCropSourceImage,
            preset: sellerEditorPhotoCropPreset,
            title: sellerEditorPhotoCropTitle,
            onCancel: { dismissSellerEditorPhotoCropper() },
            onUse: { cropped in
                Task { @MainActor in
                    await applySellerEditorCroppedPhoto(cropped)
                }
            }
        )
        .fullScreenCover(item: $imageGalleryPresentation) { presentation in
            SecretaryImageGalleryViewer(presentation: presentation) {
                imageGalleryPresentation = nil
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        SellerEditorChrome.darkCard(cornerRadius: SecretaryTheme.Layout.radiusLarge) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 11) {
                    SecretaryPhotoOrb(
                        initials: initials(from: displayName.isEmpty ? "You" : displayName),
                        systemImage: nil,
                        style: surfaceStyle,
                        size: 46
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Public surface")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.95))

                        Text(surfaceStatusLine)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }

                    Spacer(minLength: 0)

                    heroOutwardBadgePill(title: outwardBadge)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Help people know when to approach you.")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Create a simple public profile and one clear offer. Your secretary uses this to decide when a match makes sense.")
                        .font(.system(size: 15.5))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    heroStatusCapsule(
                        title: publicSurfacePrimaryLabel,
                        systemImage: publicSurfacePrimaryIcon,
                        attention: heroPrimaryLabelAttention
                    )

                    heroStatusCapsule(
                        title: primaryOfferView == nil ? "Offer needed" : "Offer ready",
                        systemImage: "shippingbox",
                        attention: primaryOfferView == nil
                    )

                    Spacer(minLength: 0)
                }

                if let serviceAreaResolveNotice,
                   !serviceAreaResolveNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(serviceAreaResolveNotice)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.95))
                        .multilineTextAlignment(.leading)
                }

                if let errorText, !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(errorText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var heroPrimaryLabelAttention: Bool {
        if !sellerValidationIssuesSnapshot.isEmpty { return true }
        guard let workspace = sellerWorkspaceSnapshot else { return false }
        if workspace.publicProfile == nil { return true }
        if workspace.offers.isEmpty { return true }
        switch workspace.publicationState?.status {
        case .failed, .pendingPublish: return true
        default: return false
        }
    }

    private func heroOutwardBadgePill(title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkOrange)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkOrangeSoft.opacity(0.48))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkOrange.opacity(0.38), lineWidth: 1)
            )
    }

    private func heroStatusCapsule(title: String, systemImage: String, attention: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(attention ? SecretaryTheme.darkOrange : SecretaryTheme.darkSecondaryText)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(
                    attention
                        ? SecretaryTheme.darkOrangeSoft.opacity(0.45)
                        : SecretaryTheme.darkSurfaceStrong.opacity(0.52)
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    attention
                        ? SecretaryTheme.darkOrange.opacity(0.35)
                        : SecretaryTheme.darkStroke.opacity(0.72),
                    lineWidth: 1
                )
        )
    }

    private var surfaceStatusLine: String {
        if isLoading { return "Loading your surface." }
        if isSaving { return "Saving changes." }
        if !sellerValidationIssuesSnapshot.isEmpty { return "Some details need attention." }
        if sellerWorkspaceSnapshot?.publicProfile == nil { return "Profile not set up yet." }
        if primaryOfferView == nil { return "Add an offer to be discoverable." }
        return "Ready."
    }

    // MARK: - Public identity

    private var publicIdentitySection: some View {
        SellerEditorChrome.darkCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionIntro(
                    title: "Your profile",
                    icon: "person.crop.square",
                    message: "Show who you are, what you are open to, and where people can find you."
                )

                publicImageCard(
                    title: "Profile image",
                    subtitle: "Shown on your public surface after publishing.",
                    currentURL: profileImageURL,
                    hasLocalPreview: profileImagePreviewExists,
                    isProfile: true,
                    isUploading: isUploadingProfileImage,
                    photoItem: $profilePhotoItem,
                    onClear: {
                        profileImageURL = nil
                        #if canImport(UIKit)
                        profileImagePreview = nil
                        #endif
                        profilePhotoItem = nil
                    },
                    onTapImage: {
                        guard let raw = profileImageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !raw.isEmpty
                        else { return }
                        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cap = headline.trimmingCharacters(in: .whitespacesAndNewlines)
                        imageGalleryPresentation = SecretaryImageGalleryPresentation(
                            imageURLs: [raw],
                            initialIndex: 0,
                            title: name.isEmpty ? nil : name,
                            caption: cap.isEmpty ? nil : cap
                        )
                    }
                )

                cozyTextField(
                    title: "Public name",
                    placeholder: "Kai, Unify Studio, Aurora Robotics…",
                    text: $displayName,
                    field: .displayName,
                    icon: "person"
                )

                cozyTextField(
                    title: "Short intro",
                    placeholder: "Local AI builder helping people coordinate privately…",
                    text: $headline,
                    field: .headline,
                    icon: "quote.opening"
                )

                cozyTextEditor(
                    title: "About you",
                    placeholder: "Say who you are, what you do, and what kind of people should reach out.",
                    text: $summary,
                    field: .summary,
                    lineLimit: 4...8,
                    icon: "text.alignleft"
                )

                cozyTextEditor(
                    title: "Open to",
                    placeholder: "Introductions, partnerships, local founders, product opportunities, coffee chats…",
                    text: $openToText,
                    field: .openTo,
                    lineLimit: 3...6,
                    icon: "door.left.hand.open"
                )

                cozyTextField(
                    title: "Interests",
                    placeholder: "AI, robotics, design, real estate, startups…",
                    text: $interestText,
                    field: .interests,
                    icon: "sparkles"
                )

                cozyTextField(
                    title: "Roles",
                    placeholder: "Founder, builder, investor, mentor, buyer, seller…",
                    text: $activityText,
                    field: .activities,
                    icon: "figure.walk"
                )

                cozyTextField(
                    title: "Regions",
                    placeholder: "Newmarket, Aurora, Toronto, Canada, Remote…",
                    text: $regionText,
                    field: .regions,
                    icon: "location"
                )

                suggestionRow(
                    title: "Good profiles are:",
                    chips: ["Clear", "Specific", "Human", "Easy to route"]
                )
            }
        }
    }

    // MARK: - Active offering

    /// Split into nested concrete `View` types to avoid runaway generic `some View` metadata
    /// instantiation (SIGSEGV in `swift_getTypeByMangledName` during body type metadata setup).
    private var activeOfferingSection: some View {
        SellerEditorChrome.darkCard {
            ActiveOfferingSectionContent(
                focusedField: $focusedField,
                offerTitle: $offerTitle,
                offerSummary: $offerSummary,
                offerCategory: $offerCategory,
                offerRegionText: $offerRegionText,
                offerTagsText: $offerTagsText,
                offerImageURL: $offerImageURL,
                offerPhotoItem: $offerPhotoItem,
                offerImagePreviewExists: offerImagePreviewExists,
                isUploadingOfferImage: isUploadingOfferImage,
                offerGalleryImageURLs: $offerGalleryImageURLs,
                offerGalleryPhotoItem: $offerGalleryPhotoItem,
                isUploadingOfferGalleryImage: isUploadingOfferGalleryImage,
                imageGalleryPresentation: $imageGalleryPresentation,
                onClearOfferImage: {
                    offerImageURL = nil
                    #if canImport(UIKit)
                    offerImagePreview = nil
                    #endif
                    offerPhotoItem = nil
                },
                contactName: $contactName,
                contactBusinessName: $contactBusinessName,
                contactEmail: $contactEmail,
                contactPhone: $contactPhone,
                contactWebsite: $contactWebsite,
                contactPreferredMethod: $contactPreferredMethod,
                contactServiceAddressOrArea: $contactServiceAddressOrArea,
                contactAvailabilityNote: $contactAvailabilityNote,
                commercialPriceDisplay: $commercialPriceDisplay,
                commercialPriceMinText: $commercialPriceMinText,
                commercialPriceMaxText: $commercialPriceMaxText,
                commercialCurrency: $commercialCurrency,
                commercialPriceUnit: $commercialPriceUnit,
                commercialPackagesText: $commercialPackagesText,
                commercialServiceAreaNote: $commercialServiceAreaNote,
                commercialAvailabilityNote: $commercialAvailabilityNote,
                commercialMinimumEngagement: $commercialMinimumEngagement,
                commercialCancellationPolicy: $commercialCancellationPolicy,
                commercialRefundPolicy: $commercialRefundPolicy,
                commercialWarrantyPolicy: $commercialWarrantyPolicy,
                commercialRequiredInputsText: $commercialRequiredInputsText,
                commercialFAQsText: $commercialFAQsText,
                autoAnswerPricing: $autoAnswerPricing,
                autoAnswerAvailability: $autoAnswerAvailability,
                autoAnswerPolicies: $autoAnswerPolicies,
                autoAnswerServiceArea: $autoAnswerServiceArea,
                autoAnswerFAQs: $autoAnswerFAQs,
                autoAnswerCustomQuoteApproval: $autoAnswerCustomQuoteApproval
            )
        }
    }

    // MARK: - Active offering (nested; reduces root `body` generic depth)

    private enum FormChrome {
        @ViewBuilder
        static func cozyTextField(
            focusedField: FocusState<EditorField?>.Binding,
            currentFocus: EditorField,
            title: String,
            placeholder: String,
            text: Binding<String>,
            icon: String
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                labelRow(title: title, icon: icon)

                TextField(placeholder, text: text)
                    .font(.system(size: 15.5))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .tint(SecretaryTheme.darkOrange)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .focused(focusedField, equals: currentFocus)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 48)
                    .background(inputBackground(isFocused: focusedField.wrappedValue == currentFocus))
                    .overlay(inputStroke(isFocused: focusedField.wrappedValue == currentFocus))
            }
        }

        @ViewBuilder
        static func cozyTextEditor(
            focusedField: FocusState<EditorField?>.Binding,
            currentFocus: EditorField,
            title: String,
            placeholder: String,
            text: Binding<String>,
            lineLimit: ClosedRange<Int>,
            icon: String
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                labelRow(title: title, icon: icon)

                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(.system(size: 15))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: text, axis: .vertical)
                        .font(.system(size: 15.5))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .tint(SecretaryTheme.darkOrange)
                        .lineLimit(lineLimit)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                        .focused(focusedField, equals: currentFocus)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                }
                .background(inputBackground(isFocused: focusedField.wrappedValue == currentFocus))
                .overlay(inputStroke(isFocused: focusedField.wrappedValue == currentFocus))
            }
        }

        @ViewBuilder
        private static func labelRow(title: String, icon: String) -> some View {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                Spacer(minLength: 0)
            }
        }

        private static func inputBackground(isFocused: Bool) -> some View {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isFocused
                        ? SecretaryTheme.darkSurfaceStrong.opacity(0.62)
                        : SecretaryTheme.darkSurfaceStrong.opacity(0.38)
                )
        }

        private static func inputStroke(isFocused: Bool) -> some View {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isFocused
                        ? SecretaryTheme.darkOrange.opacity(0.45)
                        : SecretaryTheme.darkStroke.opacity(0.78),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
    }

    private struct ActiveOfferingSectionContent: View {
        @FocusState.Binding var focusedField: SecretarySellerSurfaceEditorView.EditorField?

        @Binding var offerTitle: String
        @Binding var offerSummary: String
        @Binding var offerCategory: String
        @Binding var offerRegionText: String
        @Binding var offerTagsText: String
        @Binding var offerImageURL: String?
        @Binding var offerPhotoItem: PhotosPickerItem?
        let offerImagePreviewExists: Bool
        let isUploadingOfferImage: Bool
        @Binding var offerGalleryImageURLs: [String]
        @Binding var offerGalleryPhotoItem: PhotosPickerItem?
        let isUploadingOfferGalleryImage: Bool
        @Binding var imageGalleryPresentation: SecretaryImageGalleryPresentation?
        let onClearOfferImage: () -> Void

        @Binding var contactName: String
        @Binding var contactBusinessName: String
        @Binding var contactEmail: String
        @Binding var contactPhone: String
        @Binding var contactWebsite: String
        @Binding var contactPreferredMethod: String
        @Binding var contactServiceAddressOrArea: String
        @Binding var contactAvailabilityNote: String

        @Binding var commercialPriceDisplay: String
        @Binding var commercialPriceMinText: String
        @Binding var commercialPriceMaxText: String
        @Binding var commercialCurrency: String
        @Binding var commercialPriceUnit: String
        @Binding var commercialPackagesText: String
        @Binding var commercialServiceAreaNote: String
        @Binding var commercialAvailabilityNote: String
        @Binding var commercialMinimumEngagement: String
        @Binding var commercialCancellationPolicy: String
        @Binding var commercialRefundPolicy: String
        @Binding var commercialWarrantyPolicy: String
        @Binding var commercialRequiredInputsText: String
        @Binding var commercialFAQsText: String
        @Binding var autoAnswerPricing: Bool
        @Binding var autoAnswerAvailability: Bool
        @Binding var autoAnswerPolicies: Bool
        @Binding var autoAnswerServiceArea: Bool
        @Binding var autoAnswerFAQs: Bool
        @Binding var autoAnswerCustomQuoteApproval: Bool

        private var offerPresentationImageURLs: [String] {
            ExchangeOffer.limitedOrderedOfferImageURLs(
                primaryImageURL: offerImageURL,
                galleryImageURLs: offerGalleryImageURLs
            )
        }

        private var canAddMoreOfferGalleryImages: Bool {
            offerPresentationImageURLs.count < ExchangeOffer.maxPublicOfferImageCount
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                offerIntroHeader

                PublicSurfaceImageCard(
                    title: "Offer hero image",
                    subtitle: "Main photo for this offer. Up to \(ExchangeOffer.maxPublicOfferImageCount) images total including extras below.",
                    currentURL: offerImageURL,
                    hasLocalPreview: offerImagePreviewExists,
                    isProfile: false,
                    isUploading: isUploadingOfferImage,
                    photoItem: $offerPhotoItem,
                    onClear: onClearOfferImage,
                    onTapImage: {
                        let urls = offerPresentationImageURLs
                        guard !urls.isEmpty else { return }
                        let title = offerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cap = offerSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                        imageGalleryPresentation = SecretaryImageGalleryPresentation(
                            imageURLs: urls,
                            initialIndex: 0,
                            title: title.isEmpty ? nil : title,
                            caption: cap.isEmpty ? nil : cap
                        )
                    }
                )

                OfferGalleryAttachmentsEditor(
                    heroImageURL: $offerImageURL,
                    galleryURLs: $offerGalleryImageURLs,
                    galleryPhotoItem: $offerGalleryPhotoItem,
                    isUploading: isUploadingOfferGalleryImage,
                    canAddMore: canAddMoreOfferGalleryImages,
                    imageGalleryPresentation: $imageGalleryPresentation,
                    viewerTitle: offerTitle,
                    viewerCaption: offerSummary,
                    onRemoveGalleryIndex: { index in
                        guard offerGalleryImageURLs.indices.contains(index) else { return }
                        offerGalleryImageURLs.remove(at: index)
                    }
                )

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .offerTitle,
                    title: "Offer title",
                    placeholder: "Local AI consulting, piano lessons, event photography…",
                    text: $offerTitle,
                    icon: "sparkles.rectangle.stack"
                )

                FormChrome.cozyTextEditor(
                    focusedField: $focusedField,
                    currentFocus: .offerSummary,
                    title: "Offer details",
                    placeholder: "Explain what someone can come to you for, what is included, and who is a good fit.",
                    text: $offerSummary,
                    lineLimit: 4...8,
                    icon: "doc.text"
                )

                HStack(spacing: 10) {
                    FormChrome.cozyTextField(
                        focusedField: $focusedField,
                        currentFocus: .offerCategory,
                        title: "Category",
                        placeholder: "Service, product, social…",
                        text: $offerCategory,
                        icon: "square.grid.2x2"
                    )

                    FormChrome.cozyTextField(
                        focusedField: $focusedField,
                        currentFocus: .offerRegions,
                        title: "Service areas",
                        placeholder: "Aurora, GTA, Online, Remote…",
                        text: $offerRegionText,
                        icon: "mappin.and.ellipse"
                    )
                }

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .offerTags,
                    title: "Tags",
                    placeholder: "AI, sourcing, tutoring, events…",
                    text: $offerTagsText,
                    icon: "tag"
                )

                OfferContactInfoContent(
                    focusedField: $focusedField,
                    contactName: $contactName,
                    contactBusinessName: $contactBusinessName,
                    contactEmail: $contactEmail,
                    contactPhone: $contactPhone,
                    contactWebsite: $contactWebsite,
                    contactPreferredMethod: $contactPreferredMethod,
                    contactServiceAddressOrArea: $contactServiceAddressOrArea,
                    contactAvailabilityNote: $contactAvailabilityNote
                )

                CommercialFactsContent(
                    focusedField: $focusedField,
                    commercialPriceDisplay: $commercialPriceDisplay,
                    commercialPriceMinText: $commercialPriceMinText,
                    commercialPriceMaxText: $commercialPriceMaxText,
                    commercialCurrency: $commercialCurrency,
                    commercialPriceUnit: $commercialPriceUnit,
                    commercialPackagesText: $commercialPackagesText,
                    commercialServiceAreaNote: $commercialServiceAreaNote,
                    commercialAvailabilityNote: $commercialAvailabilityNote,
                    commercialMinimumEngagement: $commercialMinimumEngagement,
                    commercialCancellationPolicy: $commercialCancellationPolicy,
                    commercialRefundPolicy: $commercialRefundPolicy,
                    commercialWarrantyPolicy: $commercialWarrantyPolicy,
                    commercialRequiredInputsText: $commercialRequiredInputsText,
                    commercialFAQsText: $commercialFAQsText,
                    autoAnswerPricing: $autoAnswerPricing,
                    autoAnswerAvailability: $autoAnswerAvailability,
                    autoAnswerPolicies: $autoAnswerPolicies,
                    autoAnswerServiceArea: $autoAnswerServiceArea,
                    autoAnswerFAQs: $autoAnswerFAQs,
                    autoAnswerCustomQuoteApproval: $autoAnswerCustomQuoteApproval
                )
            }
        }

        private var offerIntroHeader: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    SecretaryIconBadge(systemImage: "shippingbox", style: .brand, size: 38)

                    Text("Your offer")
                        .font(.system(size: 23, weight: .regular, design: .serif))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Spacer(minLength: 0)
                }

                Text("Describe the main thing people can approach you for right now.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineSpacing(1.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct OfferContactInfoContent: View {
        @FocusState.Binding var focusedField: SecretarySellerSurfaceEditorView.EditorField?

        @Binding var contactName: String
        @Binding var contactBusinessName: String
        @Binding var contactEmail: String
        @Binding var contactPhone: String
        @Binding var contactWebsite: String
        @Binding var contactPreferredMethod: String
        @Binding var contactServiceAddressOrArea: String
        @Binding var contactAvailabilityNote: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                SellerEditorChrome.sectionHeader(
                    title: "Contact info",
                    systemImage: "phone.badge.waveform"
                )

                Text("Optional. This may be shown publicly with this offer when published.")
                    .font(.system(size: 14))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineSpacing(1.3)
                    .fixedSize(horizontal: false, vertical: true)

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .contactName,
                    title: "Contact name",
                    placeholder: "Kai Arora",
                    text: $contactName,
                    icon: "person.text.rectangle"
                )

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .contactBusinessName,
                    title: "Business name",
                    placeholder: "Unify Studio",
                    text: $contactBusinessName,
                    icon: "building.2"
                )

                HStack(spacing: 10) {
                    FormChrome.cozyTextField(
                        focusedField: $focusedField,
                        currentFocus: .contactEmail,
                        title: "Email",
                        placeholder: "hello@example.com",
                        text: $contactEmail,
                        icon: "envelope"
                    )

                    FormChrome.cozyTextField(
                        focusedField: $focusedField,
                        currentFocus: .contactPhone,
                        title: "Phone",
                        placeholder: "+1 555 123 4567",
                        text: $contactPhone,
                        icon: "phone"
                    )
                }

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .contactWebsite,
                    title: "Website",
                    placeholder: "example.com",
                    text: $contactWebsite,
                    icon: "globe"
                )

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .contactPreferredMethod,
                    title: "Preferred method",
                    placeholder: "email, phone, website, message, any",
                    text: $contactPreferredMethod,
                    icon: "paperplane"
                )

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .contactServiceAddressOrArea,
                    title: "Service area/address",
                    placeholder: "Toronto + GTA, remote worldwide…",
                    text: $contactServiceAddressOrArea,
                    icon: "mappin.and.ellipse"
                )

                FormChrome.cozyTextEditor(
                    focusedField: $focusedField,
                    currentFocus: .contactAvailabilityNote,
                    title: "Availability/contact note",
                    placeholder: "Best time to reach you, response window, booking note…",
                    text: $contactAvailabilityNote,
                    lineLimit: 2...8,
                    icon: "clock.badge.questionmark"
                )
            }
            .padding(.top, 4)
        }
    }

    private struct CommercialFactsContent: View {
        @FocusState.Binding var focusedField: SecretarySellerSurfaceEditorView.EditorField?

        @Binding var commercialPriceDisplay: String
        @Binding var commercialPriceMinText: String
        @Binding var commercialPriceMaxText: String
        @Binding var commercialCurrency: String
        @Binding var commercialPriceUnit: String
        @Binding var commercialPackagesText: String
        @Binding var commercialServiceAreaNote: String
        @Binding var commercialAvailabilityNote: String
        @Binding var commercialMinimumEngagement: String
        @Binding var commercialCancellationPolicy: String
        @Binding var commercialRefundPolicy: String
        @Binding var commercialWarrantyPolicy: String
        @Binding var commercialRequiredInputsText: String
        @Binding var commercialFAQsText: String
        @Binding var autoAnswerPricing: Bool
        @Binding var autoAnswerAvailability: Bool
        @Binding var autoAnswerPolicies: Bool
        @Binding var autoAnswerServiceArea: Bool
        @Binding var autoAnswerFAQs: Bool
        @Binding var autoAnswerCustomQuoteApproval: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                SellerEditorChrome.sectionHeader(
                    title: "Useful details",
                    systemImage: "doc.text.magnifyingglass"
                )

                Text("Optional. Add pricing, availability, policies, and FAQs so your secretary can answer simple questions.")
                    .font(.system(size: 14))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineSpacing(1.35)
                    .fixedSize(horizontal: false, vertical: true)

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .commercialPriceDisplay,
                    title: "Price",
                    placeholder: "From $199 / session, $2k–$4k project range…",
                    text: $commercialPriceDisplay,
                    icon: "dollarsign.circle"
                )

                HStack(spacing: 10) {
                    FormChrome.cozyTextField(
                        focusedField: $focusedField,
                        currentFocus: .commercialPriceMin,
                        title: "Min",
                        placeholder: "",
                        text: $commercialPriceMinText,
                        icon: "number"
                    )

                    FormChrome.cozyTextField(
                        focusedField: $focusedField,
                        currentFocus: .commercialPriceMax,
                        title: "Max",
                        placeholder: "",
                        text: $commercialPriceMaxText,
                        icon: "number"
                    )
                }

                HStack(spacing: 10) {
                    FormChrome.cozyTextField(
                        focusedField: $focusedField,
                        currentFocus: .commercialCurrency,
                        title: "Currency",
                        placeholder: "CAD, USD…",
                        text: $commercialCurrency,
                        icon: "centsign.circle"
                    )

                    FormChrome.cozyTextField(
                        focusedField: $focusedField,
                        currentFocus: .commercialPriceUnit,
                        title: "Unit",
                        placeholder: "/ hour, / session…",
                        text: $commercialPriceUnit,
                        icon: "clock"
                    )
                }

                FormChrome.cozyTextEditor(
                    focusedField: $focusedField,
                    currentFocus: .commercialPackages,
                    title: "Packages",
                    placeholder: "One option per line. Example: Starter — 1 hour intro call — ($99)",
                    text: $commercialPackagesText,
                    lineLimit: 3...12,
                    icon: "square.stack"
                )

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .commercialServiceAreaNote,
                    title: "Service area",
                    placeholder: "Remote, GTA only, 30km radius…",
                    text: $commercialServiceAreaNote,
                    icon: "map"
                )

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .commercialAvailabilityNote,
                    title: "Availability",
                    placeholder: "Weekends, 2-week lead time, evenings only…",
                    text: $commercialAvailabilityNote,
                    icon: "calendar"
                )

                FormChrome.cozyTextField(
                    focusedField: $focusedField,
                    currentFocus: .commercialMinimumEngagement,
                    title: "Minimum",
                    placeholder: "Minimum hours, deposit, project size…",
                    text: $commercialMinimumEngagement,
                    icon: "hourglass"
                )

                FormChrome.cozyTextEditor(
                    focusedField: $focusedField,
                    currentFocus: .commercialCancellationPolicy,
                    title: "Cancellation policy",
                    placeholder: "Optional.",
                    text: $commercialCancellationPolicy,
                    lineLimit: 2...10,
                    icon: "xmark.circle"
                )

                FormChrome.cozyTextEditor(
                    focusedField: $focusedField,
                    currentFocus: .commercialRefundPolicy,
                    title: "Refund policy",
                    placeholder: "Optional.",
                    text: $commercialRefundPolicy,
                    lineLimit: 2...10,
                    icon: "arrow.uturn.backward.circle"
                )

                FormChrome.cozyTextEditor(
                    focusedField: $focusedField,
                    currentFocus: .commercialWarrantyPolicy,
                    title: "Warranty policy",
                    placeholder: "Optional.",
                    text: $commercialWarrantyPolicy,
                    lineLimit: 2...10,
                    icon: "checkmark.shield"
                )

                FormChrome.cozyTextEditor(
                    focusedField: $focusedField,
                    currentFocus: .commercialRequiredInputsText,
                    title: "What buyers should provide",
                    placeholder: "Budget\nDeadline\nLocation\nRequirements",
                    text: $commercialRequiredInputsText,
                    lineLimit: 2...10,
                    icon: "list.bullet.clipboard"
                )

                FormChrome.cozyTextEditor(
                    focusedField: $focusedField,
                    currentFocus: .commercialFAQsText,
                    title: "FAQs",
                    placeholder: """
                    Q: What is included?
                    A: ...

                    Q: Do you offer rush service?
                    A: ...
                    """,
                    text: $commercialFAQsText,
                    lineLimit: 4...16,
                    icon: "questionmark.bubble"
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("What your secretary can answer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Toggle("Pricing", isOn: $autoAnswerPricing)
                    Toggle("Availability", isOn: $autoAnswerAvailability)
                    Toggle("Policies", isOn: $autoAnswerPolicies)
                    Toggle("Service area", isOn: $autoAnswerServiceArea)
                    Toggle("FAQs", isOn: $autoAnswerFAQs)
                    Toggle("Ask me before custom quotes", isOn: $autoAnswerCustomQuoteApproval)
                }
                .tint(SecretaryTheme.darkOrange)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Bottom actions

    private var bottomActionsCard: some View {
        SellerEditorChrome.darkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    SecretaryIconBadge(
                        systemImage: "checkmark.seal",
                        style: .brand,
                        size: 38
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Save or publish")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)

                        Text("Save keeps it private. Publish makes it discoverable.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Cancel")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)

                    Spacer(minLength: 0)

                    Button {
                        Task { @MainActor in
                            await saveProfile()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                            Text(isSaving ? "Saving…" : "Save")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || isLoading)

                    Button {
                        Task { @MainActor in
                            await publishSurface()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12, weight: .semibold))
                            Text(isSaving ? "Publishing…" : "Publish")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SecretaryTheme.darkOrange)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(SecretaryTheme.darkOrange.opacity(0.55), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || isLoading)
                }
            }
        }
    }

    // MARK: - Reusable UI

    private func sectionIntro(
        title: String,
        icon: String,
        message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SecretaryIconBadge(systemImage: icon, style: .brand, size: 38)

                Text(title)
                    .font(.system(size: 23, weight: .regular, design: .serif))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                Spacer(minLength: 0)
            }

            Text(message)
                .font(.system(size: 14.5))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .lineSpacing(1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cozyTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: EditorField,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labelRow(title: title, icon: icon)

            TextField(placeholder, text: text)
                .font(.system(size: 15.5))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .tint(SecretaryTheme.darkOrange)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .focused($focusedField, equals: field)
                .padding(.horizontal, 13)
                .frame(minHeight: 48)
                .background(inputBackground(isFocused: focusedField == field))
                .overlay(inputStroke(isFocused: focusedField == field))
        }
    }

    private func cozyTextEditor(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: EditorField,
        lineLimit: ClosedRange<Int>,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labelRow(title: title, icon: icon)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }

                TextField("", text: text, axis: .vertical)
                    .font(.system(size: 15.5))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .tint(SecretaryTheme.darkOrange)
                    .lineLimit(lineLimit)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .focused($focusedField, equals: field)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
            }
            .background(inputBackground(isFocused: focusedField == field))
            .overlay(inputStroke(isFocused: focusedField == field))
        }
    }

    private func labelRow(title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkOrange)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            Spacer(minLength: 0)
        }
    }

    private func inputBackground(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                isFocused
                    ? SecretaryTheme.darkSurfaceStrong.opacity(0.62)
                    : SecretaryTheme.darkSurfaceStrong.opacity(0.38)
            )
    }

    private func inputStroke(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                isFocused
                    ? SecretaryTheme.darkOrange.opacity(0.45)
                    : SecretaryTheme.darkStroke.opacity(0.78),
                lineWidth: isFocused ? 1.5 : 1
            )
    }

    private func suggestionChipLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SecretaryTheme.darkSecondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.52))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.72), lineWidth: 1)
            )
    }

    private func suggestionRow(title: String, chips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        suggestionChipLabel(chip)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Derived state

    private var primaryOfferView: ExchangeModels.OfferView? {
        sellerWorkspaceSnapshot?.offers.first(where: { $0.offer.status == .active })
        ?? sellerWorkspaceSnapshot?.offers.first
    }

    private var existingEditableOffer: ExchangeOffer? {
        if let offerID {
            return sellerWorkspaceSnapshot?.offers
                .map(\.offer)
                .first(where: { $0.id == offerID })
        }

        return sellerWorkspaceSnapshot?.offers.first(where: { $0.offer.status == .active })?.offer
            ?? sellerWorkspaceSnapshot?.offers.first?.offer
    }

    private var surfaceStyle: SecretaryStateChip.Style {
        if !sellerValidationIssuesSnapshot.isEmpty { return .warning }

        guard let workspace = sellerWorkspaceSnapshot else {
            return .neutral
        }

        if workspace.publicProfile == nil { return .neutral }
        if workspace.offers.isEmpty { return .warning }

        switch workspace.publicationState?.status {
        case .published:
            return .neutral
        case .failed:
            return .blocked
        case .pendingPublish, .draft, .stale, .paused, .pendingUnpublish, .archived, .none:
            return .neutral
        }
    }

    private var outwardBadge: String {
        if let badge = SecretaryProjectionEngine.nonEmpty(sellerWorkspaceSnapshot?.publicationBadgeText) {
            return badge
        }

        guard let workspace = sellerWorkspaceSnapshot else { return "Setup" }
        if workspace.publicProfile == nil { return "Setup" }
        if !sellerValidationIssuesSnapshot.isEmpty { return "Needs work" }
        if workspace.offers.isEmpty { return "Add offer" }

        switch workspace.publicationState?.status {
        case .draft: return "Ready"
        case .pendingPublish: return "Publishing"
        case .published: return "Visible"
        case .stale: return "Update"
        case .paused: return "Paused"
        case .pendingUnpublish: return "Withdrawing"
        case .archived: return "Archived"
        case .failed: return "Failed"
        case .none: return "Ready"
        }
    }

    private var publicSurfacePrimaryLabel: String {
        guard let workspace = sellerWorkspaceSnapshot else { return "Not set up" }
        if workspace.publicProfile == nil { return "Profile needed" }
        if !sellerValidationIssuesSnapshot.isEmpty { return "Needs care" }
        if workspace.offers.isEmpty { return "Offer needed" }

        switch workspace.publicationState?.status {
        case .published:
            return "Published"
        case .pendingPublish:
            return "Publishing"
        case .paused:
            return "Paused"
        case .failed:
            return "Publish failed"
        case .draft, .stale, .pendingUnpublish, .archived, .none:
            return "Ready"
        }
    }

    private var publicSurfacePrimaryIcon: String {
        guard let workspace = sellerWorkspaceSnapshot else { return "person.crop.circle" }
        if workspace.publicProfile == nil { return "person.crop.circle" }
        if !sellerValidationIssuesSnapshot.isEmpty { return "exclamationmark.shield" }
        if workspace.offers.isEmpty { return "shippingbox" }

        switch workspace.publicationState?.status {
        case .published:
            return "sparkles"
        case .failed:
            return "exclamationmark.shield"
        default:
            return "sparkles.rectangle.stack"
        }
    }

    // MARK: - Loading

    @MainActor
    private func scheduleLoad(
        delayNanoseconds: UInt64 = 150_000_000
    ) {
        loadTask?.cancel()

        loadTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard !Task.isCancelled else { return }
            await load()
        }
    }

    @MainActor
    private func load() async {
        if hasHydratedForm { return }

        isLoading = true
        errorText = nil

        await services.refreshSellerWorkspace(force: true)

        guard !Task.isCancelled else { return }

        sellerWorkspaceSnapshot = services.sellerWorkspace
        sellerValidationIssuesSnapshot = services.sellerValidationIssues

        hydrateFormFromSnapshotIfNeeded()

        isLoading = false
    }

    @MainActor
    private func refreshLocalSellerSnapshot() async {
        await services.refreshSellerWorkspace(force: true)

        guard !Task.isCancelled else { return }

        sellerWorkspaceSnapshot = services.sellerWorkspace
        sellerValidationIssuesSnapshot = services.sellerValidationIssues
    }

    @MainActor
    private func hydrateFormFromSnapshotIfNeeded() {
        guard !hasHydratedForm else { return }

        if let profile = sellerWorkspaceSnapshot?.publicProfile?.profile {
            profileID = profile.id
            displayName = profile.displayName ?? ""
            headline = profile.headline ?? ""
            summary = profile.summary ?? ""
            openToText = profile.openTo.joined(separator: ", ")
            offersText = profile.offers.joined(separator: ", ")
            interestText = profile.interests.joined(separator: ", ")
            activityText = profile.activityTags.joined(separator: ", ")
            regionText = profile.regionTags.joined(separator: ", ")
            profileImageURL = profile.primaryImageURL
        }

        if let editableOffer = existingEditableOffer {
            offerID = editableOffer.id
            offerTitle = editableOffer.title
            offerSummary = editableOffer.summary ?? ""
            offerCategory = editableOffer.category ?? ""
            offerTagsText = editableOffer.tags.joined(separator: ", ")
            offerRegionText = Self.serviceAreasCSV(from: editableOffer)
            offerImageURL = editableOffer.primaryImageURL
            offerGalleryImageURLs = editableOffer.galleryImageURLs

            hydrateCommercialFields(editableOffer.commercialFacts)
            hydrateContactFields(editableOffer.contactInfo)
        } else {
            offerID = nil
            offerTitle = ""
            offerSummary = ""
            offerCategory = ""
            offerTagsText = ""
            offerRegionText = ""
            offerImageURL = nil
            offerGalleryImageURLs = []
            hydrateCommercialFields(.empty)
            hydrateContactFields(nil)
        }

        hasHydratedForm = true
    }

    // MARK: - Save / publish

    private func upsertProfile(nodeID: String) async throws -> ExchangePublicNodeProfile {
        if let existingProfile = sellerWorkspaceSnapshot?.publicProfile?.profile {
            var updated = existingProfile
            updated.displayName = nilIfBlank(displayName)
            updated.headline = nilIfBlank(headline)
            updated.summary = nilIfBlank(summary)
            updated.openTo = splitCSV(openToText)
            updated.offers = splitCSV(offersText)
            updated.interests = splitCSV(interestText)
            updated.activityTags = splitCSV(activityText)
            updated.regionTags = splitCSV(regionText)
            updated.primaryImageURL = profileImageURL?.nilIfBlankOrNil
            updated.updatedAt = Date()

            try await services.exchangeFacade.savePublicProfile(updated)
            profileID = updated.id
            return updated
        } else {
            let created = try await services.exchangeFacade.createSellerProfile(
                ownerNodeID: nodeID,
                ownerDisplayName: nilIfBlank(displayName)
            )

            var updated = created
            updated.displayName = nilIfBlank(displayName)
            updated.headline = nilIfBlank(headline)
            updated.summary = nilIfBlank(summary)
            updated.openTo = splitCSV(openToText)
            updated.offers = splitCSV(offersText)
            updated.interests = splitCSV(interestText)
            updated.activityTags = splitCSV(activityText)
            updated.regionTags = splitCSV(regionText)
            updated.primaryImageURL = profileImageURL?.nilIfBlankOrNil
            updated.updatedAt = Date()

            try await services.exchangeFacade.savePublicProfile(updated)
            profileID = updated.id
            return updated
        }
    }

    private func persistedMediaStorageKeysFromSnapshot() -> Set<String> {
        PublicMediaURLSupport.storageKeys(
            profileImageURL: sellerWorkspaceSnapshot?.publicProfile?.profile.primaryImageURL,
            offerImageURL: existingEditableOffer?.primaryImageURL,
            offerGalleryImageURLs: existingEditableOffer?.galleryImageURLs ?? []
        )
    }

    @MainActor
    private func saveProfile() async {
        guard !isSaving else { return }

        isSaving = true
        errorText = nil
        defer { isSaving = false }

        do {
            let nodeID = await services.exchangeNodeID ?? ""
            guard !nodeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorText = "Missing local node ID."
                return
            }

            let previousMediaKeys = persistedMediaStorageKeysFromSnapshot()

            let finalProfile = try await upsertProfile(nodeID: nodeID)
            try await savePrimaryOffer(
                nodeID: nodeID,
                publicProfileID: finalProfile.id
            )

            await refreshLocalSellerSnapshot()

            await services.cleanupRemotePublicMediaAfterSellerSurfaceSave(
                previousStorageKeys: previousMediaKeys,
                profileImageURL: profileImageURL,
                offerImageURL: offerImageURL,
                offerGalleryImageURLs: offerGalleryImageURLs
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func publishSurface() async {
        guard !isSaving else { return }

        isSaving = true
        errorText = nil
        defer { isSaving = false }

        do {
            let nodeID = await services.exchangeNodeID ?? ""
            guard !nodeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorText = "Missing local node ID."
                return
            }

            let previousMediaKeys = persistedMediaStorageKeysFromSnapshot()

            let finalProfile = try await upsertProfile(nodeID: nodeID)
            try await savePrimaryOffer(
                nodeID: nodeID,
                publicProfileID: finalProfile.id
            )

            _ = try await services.exchangeFacade.publishSellerSurface(
                ownerNodeID: nodeID,
                ownerDisplayName: nilIfBlank(displayName),
                now: Date()
            )

            await refreshLocalSellerSnapshot()

            await services.cleanupRemotePublicMediaAfterSellerSurfaceSave(
                previousStorageKeys: previousMediaKeys,
                profileImageURL: profileImageURL,
                offerImageURL: offerImageURL,
                offerGalleryImageURLs: offerGalleryImageURLs
            )

            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func resolvedServiceAreasForSave(csv: String) async -> [ExchangeDeclaredServiceArea] {
        let batch = await services.resolveSellerServiceAreas(from: csv)
        serviceAreaResolveNotice = batch.userNotice
        return batch.areas
    }

    private func savePrimaryOffer(
        nodeID: String,
        publicProfileID: String
    ) async throws {
        let cleanedTitle = nilIfBlank(offerTitle)
        let cleanedSummary = nilIfBlank(offerSummary)
        let cleanedCategory = nilIfBlank(offerCategory)
        let cleanedTags = splitCSV(offerTagsText)
        let cleanedRegions = splitCSV(offerRegionText)
        let resolvedServiceAreas = await resolvedServiceAreasForSave(csv: offerRegionText)

        let cf = commercialFactsBuilt(merging: existingEditableOffer?.commercialFacts ?? .empty)
        let contactInfo = offerContactInfoBuilt()

        let hasCommercialEditorContent =
            cf.hasPublishedCommercialSurface ||
            cf.autoAnswerPolicy != ExchangeOffer.AutoAnswerPolicy.conservativeDefaults

        let hasAnyLaneContent =
            cleanedTitle != nil ||
            cleanedSummary != nil ||
            cleanedCategory != nil ||
            !cleanedTags.isEmpty ||
            !cleanedRegions.isEmpty ||
            hasCommercialEditorContent ||
            contactInfo != nil

        if !hasAnyLaneContent {
            if existingEditableOffer == nil {
                return
            } else {
                throw NSError(
                    domain: "SecretarySellerSurfaceEditor",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Your offer is empty. Add at least a title or summary before saving."
                    ]
                )
            }
        }

        if let existing = existingEditableOffer {
            var updated = existing
            updated.publicProfileID = publicProfileID
            updated.title = cleanedTitle ?? existing.title
            updated.summary = cleanedSummary
            updated.category = cleanedCategory
            updated.tags = cleanedTags
            updated.serviceAreas = resolvedServiceAreas
            ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&updated)
            updated.status = .active
            updated.visibility = .publicDiscoverable
            let hero = offerImageURL?.nilIfBlankOrNil
            updated.primaryImageURL = hero
            updated.galleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                primary: hero,
                gallery: offerGalleryImageURLs
            )
            updated.updatedAt = Date()
            updated.commercialFacts = cf
            updated.contactInfo = contactInfo

            try await services.exchangeFacade.saveOffer(updated)
            offerID = updated.id
        } else {
            let hero = offerImageURL?.nilIfBlankOrNil
            var created = ExchangeOffer(
                id: offerID ?? UUID().uuidString.lowercased(),
                nodeID: nodeID,
                publicProfileID: publicProfileID,
                title: cleanedTitle ?? "Active offer",
                summary: cleanedSummary,
                category: cleanedCategory,
                tags: cleanedTags,
                serviceAreas: resolvedServiceAreas,
                fulfillment: .init(
                    pricingMode: .undisclosed,
                    commitmentMode: .exploratory,
                    remoteFriendly: true
                ),
                status: .active,
                visibility: .publicDiscoverable,
                createdAt: Date(),
                updatedAt: Date(),
                primaryImageURL: hero,
                galleryImageURLs: offerGalleryImageURLs,
                commercialFacts: cf,
                contactInfo: contactInfo
            )
            ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&created)

            try await services.exchangeFacade.saveOffer(created)
            offerID = created.id
        }
    }

    private func hydrateCommercialFields(_ facts: ExchangeOffer.CommercialFacts) {
        commercialPriceDisplay = facts.priceDisplay ?? ""
        commercialPriceMinText = decimalText(facts.priceMin)
        commercialPriceMaxText = decimalText(facts.priceMax)
        commercialCurrency = facts.currency ?? ""
        commercialPriceUnit = facts.priceUnit ?? ""
        commercialPackagesText = packagesEditorText(from: facts.packages)
        commercialServiceAreaNote = facts.serviceAreaNote ?? ""
        commercialAvailabilityNote = facts.availabilityNote ?? ""
        commercialMinimumEngagement = facts.minimumEngagement ?? ""
        commercialCancellationPolicy = facts.cancellationPolicy ?? ""
        commercialRefundPolicy = facts.refundPolicy ?? ""
        commercialWarrantyPolicy = facts.warrantyPolicy ?? ""
        commercialRequiredInputsText = facts.requiredBuyerInputs.joined(separator: "\n")
        commercialFAQsText = faqsEditorText(from: facts.faqs)

        let ap = facts.autoAnswerPolicy
        autoAnswerPricing = ap.canAnswerPricing
        autoAnswerAvailability = ap.canAnswerAvailability
        autoAnswerPolicies = ap.canAnswerPolicies
        autoAnswerServiceArea = ap.canAnswerServiceArea
        autoAnswerFAQs = ap.canAnswerFAQs
        autoAnswerCustomQuoteApproval = ap.requiresApprovalForCustomQuote
    }

    private func hydrateContactFields(_ contact: ExchangeOffer.ContactInfo?) {
        contactName = contact?.contactName ?? ""
        contactBusinessName = contact?.businessName ?? ""
        contactEmail = contact?.email ?? ""
        contactPhone = contact?.phone ?? ""
        contactWebsite = contact?.website ?? ""
        contactPreferredMethod = contact?.preferredContactMethod?.rawValue ?? ""
        contactAvailabilityNote = contact?.availabilityNote ?? ""
        contactServiceAddressOrArea = contact?.serviceAddressOrArea ?? ""
    }

    private func decimalText(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return (value as NSDecimalNumber).stringValue
    }

    private func packagesEditorText(from packages: [ExchangeOffer.PackageOption]) -> String {
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

    private func faqsEditorText(from faqs: [ExchangeOffer.FAQ]) -> String {
        faqs.map { faq in
            """
            Q: \(faq.question)
            A: \(faq.answer)
            """
        }
        .joined(separator: "\n\n")
    }

    private func parsedPackagesFromEditor() -> [ExchangeOffer.PackageOption] {
        commercialPackagesText
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

    private func parsedFAQsFromEditor() -> [ExchangeOffer.FAQ] {
        var results: [ExchangeOffer.FAQ] = []
        var pendingQuestion: String?

        for rawLine in commercialFAQsText.split(separator: "\n", omittingEmptySubsequences: false) {
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

    private func parseOptionalDecimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }

    private func normalizedRequiredBuyerInputs() -> [String] {
        commercialRequiredInputsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func commercialFactsBuilt(
        merging _: ExchangeOffer.CommercialFacts
    ) -> ExchangeOffer.CommercialFacts {
        ExchangeOffer.CommercialFacts(
            priceDisplay: nilIfBlank(commercialPriceDisplay),
            priceMin: parseOptionalDecimal(commercialPriceMinText),
            priceMax: parseOptionalDecimal(commercialPriceMaxText),
            currency: nilIfBlank(commercialCurrency),
            priceUnit: nilIfBlank(commercialPriceUnit),
            packages: parsedPackagesFromEditor(),
            serviceAreaNote: nilIfBlank(commercialServiceAreaNote),
            availabilityNote: nilIfBlank(commercialAvailabilityNote),
            minimumEngagement: nilIfBlank(commercialMinimumEngagement),
            cancellationPolicy: nilIfBlank(commercialCancellationPolicy),
            refundPolicy: nilIfBlank(commercialRefundPolicy),
            warrantyPolicy: nilIfBlank(commercialWarrantyPolicy),
            requiredBuyerInputs: normalizedRequiredBuyerInputs(),
            faqs: parsedFAQsFromEditor(),
            autoAnswerPolicy: ExchangeOffer.AutoAnswerPolicy(
                canAnswerPricing: autoAnswerPricing,
                canAnswerAvailability: autoAnswerAvailability,
                canAnswerPolicies: autoAnswerPolicies,
                canAnswerServiceArea: autoAnswerServiceArea,
                canAnswerFAQs: autoAnswerFAQs,
                requiresApprovalForCustomQuote: autoAnswerCustomQuoteApproval
            )
        )
    }

    private func offerContactInfoBuilt() -> ExchangeOffer.ContactInfo? {
        let methodRaw = contactPreferredMethod.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let preferred = ExchangeOffer.ContactInfo.PreferredMethod(rawValue: methodRaw)
        let contact = ExchangeOffer.ContactInfo(
            contactName: nilIfBlank(contactName),
            businessName: nilIfBlank(contactBusinessName),
            email: nilIfBlank(contactEmail),
            phone: nilIfBlank(contactPhone),
            website: nilIfBlank(contactWebsite),
            preferredContactMethod: preferred,
            availabilityNote: nilIfBlank(contactAvailabilityNote),
            serviceAddressOrArea: nilIfBlank(contactServiceAddressOrArea)
        ).normalized()
        return contact.isEmpty ? nil : contact
    }

    // MARK: - Helpers

    private static func serviceAreasCSV(from offer: ExchangeOffer) -> String {
        let tags = offer.serviceAreas.isEmpty
            ? offer.regionTags
            : ExchangeDeclaredServiceAreaSupport.projectRegionTags(from: offer.serviceAreas)
        return tags.joined(separator: ", ")
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

    private func initials(from value: String) -> String {
        let pieces = value
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let result = String(pieces).uppercased()
        return result.isEmpty ? "U" : result
    }

    // MARK: - Public media

    private var profileImagePreviewExists: Bool {
        #if canImport(UIKit)
        return profileImagePreview != nil
        #else
        return false
        #endif
    }

    private var offerImagePreviewExists: Bool {
        #if canImport(UIKit)
        return offerImagePreview != nil
        #else
        return false
        #endif
    }

    private func publicImageCard(
        title: String,
        subtitle: String,
        currentURL: String?,
        hasLocalPreview: Bool,
        isProfile: Bool,
        isUploading: Bool,
        photoItem: Binding<PhotosPickerItem?>,
        onClear: @escaping () -> Void,
        onTapImage: (() -> Void)? = nil
    ) -> some View {
        PublicSurfaceImageCard(
            title: title,
            subtitle: subtitle,
            currentURL: currentURL,
            hasLocalPreview: hasLocalPreview,
            isProfile: isProfile,
            isUploading: isUploading,
            photoItem: photoItem,
            onClear: onClear,
            onTapImage: onTapImage
        )
    }

    @ViewBuilder
    private var mediaUploadErrorBanner: some View {
        if let mediaUploadError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkOrange)

                Text(mediaUploadError)
                    .font(.system(size: 12))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                Spacer(minLength: 0)

                Button {
                    self.mediaUploadError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SecretaryTheme.darkOrangeSoft.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SecretaryTheme.darkOrange.opacity(0.28), lineWidth: 1)
            )
        }
    }

    private var sellerEditorPhotoCropTitle: String {
        switch pendingPhotoCropTarget {
        case .profile: return "Adjust Profile Photo"
        case .offerHero: return "Adjust Offer Photo"
        case .offerGallery: return "Adjust Gallery Photo"
        case .none: return "Adjust Photo"
        }
    }

    private var sellerEditorPhotoCropPreset: SharedPhotoCropperView.Preset {
        switch pendingPhotoCropTarget {
        case .profile:
            return .profileAvatar
        case .offerHero, .offerGallery:
            return .profileMediaStrip
        case .none:
            return .profileMediaStrip
        }
    }

    @MainActor
    private func presentSellerEditorPhotoCrop(
        from item: PhotosPickerItem,
        target: SellerEditorPhotoCropTarget
    ) async {
        let pickerContext: String = {
            switch target {
            case .profile: return "sellerEditorProfilePhotoPicker"
            case .offerHero: return "sellerEditorOfferHeroPicker"
            case .offerGallery: return "sellerEditorOfferGalleryPicker"
            }
        }()
        guard let image = await SharedPhotoEditFlow.loadUIImage(from: item, context: pickerContext) else {
            mediaUploadError = "Selected photo could not be loaded."
            return
        }
        pendingPhotoCropTarget = target
        photoCropSourceImage = image
        showPhotoCropper = true
    }

    @MainActor
    private func dismissSellerEditorPhotoCropper() {
        showPhotoCropper = false
        photoCropSourceImage = nil
        pendingPhotoCropTarget = nil
    }

    @MainActor
    private func applySellerEditorCroppedPhoto(_ editedImage: UIImage) async {
        let target = pendingPhotoCropTarget
        dismissSellerEditorPhotoCropper()
        switch target {
        case .profile:
            await uploadSelectedPhoto(editedImage: editedImage, role: "primaryProfile", isProfile: true)
        case .offerHero:
            await uploadSelectedPhoto(editedImage: editedImage, role: "primaryOffer", isProfile: false)
        case .offerGallery:
            await uploadOfferGalleryPhoto(editedImage: editedImage)
        case .none:
            break
        }
    }

    @MainActor
    private func uploadSelectedPhoto(
        editedImage: UIImage,
        role: String,
        isProfile: Bool
    ) async {
        mediaUploadError = nil

        if isProfile {
            isUploadingProfileImage = true
        } else {
            isUploadingOfferImage = true
        }

        defer {
            if isProfile {
                isUploadingProfileImage = false
            } else {
                isUploadingOfferImage = false
            }
        }

        let prepContext = isProfile ? "sellerEditorProfilePhoto" : "sellerEditorOfferHero"
        let prepared = SellerEditorImagePrep.prepareForUpload(editedImage, context: prepContext)
        let uploadData = prepared.data
        let mimeType = prepared.mimeType

        #if canImport(UIKit)
        if isProfile {
            profileImagePreview = prepared.previewImage
        } else {
            offerImagePreview = prepared.previewImage
        }
        #endif

        do {
            let uploadedURL = try await services.uploadPublicMedia(
                data: uploadData,
                mimeType: mimeType,
                role: role,
                publicProfileID: profileID,
                offerID: isProfile ? nil : offerID
            )

            if isProfile {
                profileImageURL = uploadedURL
            } else {
                offerImageURL = uploadedURL
                offerGalleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                    primary: uploadedURL,
                    gallery: offerGalleryImageURLs
                )
            }
        } catch {
            mediaUploadError = "Could not upload public image: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func handleOfferGalleryPhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let atCap = ExchangeOffer.limitedOrderedOfferImageURLs(
            primaryImageURL: offerImageURL,
            galleryImageURLs: offerGalleryImageURLs
        ).count >= ExchangeOffer.maxPublicOfferImageCount
        if atCap {
            offerGalleryPhotoItem = nil
            return
        }
        await presentSellerEditorPhotoCrop(from: item, target: .offerGallery)
        offerGalleryPhotoItem = nil
    }

    @MainActor
    private func uploadOfferGalleryPhoto(editedImage: UIImage) async {
        mediaUploadError = nil
        isUploadingOfferGalleryImage = true
        defer { isUploadingOfferGalleryImage = false }

        let prepared = SellerEditorImagePrep.prepareForUpload(editedImage, context: "sellerEditorOfferGallery")
        let uploadData = prepared.data
        let mimeType = prepared.mimeType

        do {
            let uploadedURL = try await services.uploadPublicMedia(
                data: uploadData,
                mimeType: mimeType,
                role: "offerGallery",
                publicProfileID: profileID,
                offerID: offerID
            )

            var merged = offerGalleryImageURLs
            merged.append(uploadedURL)
            offerGalleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                primary: offerImageURL?.nilIfBlankOrNil,
                gallery: merged
            )
        } catch {
            mediaUploadError = "Could not upload public image: \(error.localizedDescription)"
        }
    }
}

// MARK: - Image resize/compress helper
//
// Internal: shared by seller surface editor and Unify profile shell for `uploadPublicMedia` prep.

enum SellerEditorImagePrep {
    struct Result {
        let data: Data
        let mimeType: String

        #if canImport(UIKit)
        let previewImage: UIImage?
        #endif
    }

    #if DEBUG
    private static func debugLogPrep(
        context: String,
        stage: String,
        originalBytes: Int?,
        image: UIImage?,
        outputBytes: Int,
        mimeType: String
    ) {
        let pointW = Int(image?.size.width ?? 0)
        let pointH = Int(image?.size.height ?? 0)
        let pixelW = image?.cgImage?.width ?? 0
        let pixelH = image?.cgImage?.height ?? 0
        let orig = originalBytes.map(String.init) ?? "n/a"
        print(
            "[ImageUploadPrep] context=\(context) stage=\(stage) " +
            "originalBytes=\(orig) points=\(pointW)x\(pointH) pixels=\(pixelW)x\(pixelH) " +
            "bytes=\(outputBytes) mime=\(mimeType)"
        )
    }
    #endif

    static func prepareForUpload(_ image: UIImage, context: String = "federationMedia") -> Result {
        #if DEBUG
        let preBytes = image.jpegData(compressionQuality: 0.95)?.count
        #endif
        guard let data = image.jpegData(compressionQuality: 0.95), !data.isEmpty else {
            #if canImport(UIKit)
            return Result(data: Data(), mimeType: "image/jpeg", previewImage: image)
            #else
            return Result(data: Data(), mimeType: "image/jpeg")
            #endif
        }
        #if DEBUG
        debugLogPrep(
            context: context,
            stage: "postCropJPEG0.95",
            originalBytes: preBytes,
            image: image,
            outputBytes: data.count,
            mimeType: "image/jpeg"
        )
        #endif
        return prepareForUpload(data, context: context)
    }

    static func prepareForUpload(_ original: Data, context: String = "federationMedia") -> Result {
        #if canImport(UIKit)
        let maxLongestSide: CGFloat = 1024
        let jpegQuality: CGFloat = 0.78
        let smallEnoughOriginalThreshold = 600 * 1024

        guard let image = UIImage(data: original) else {
            #if DEBUG
            debugLogPrep(
                context: context,
                stage: "decodeFailedPassThrough",
                originalBytes: original.count,
                image: nil,
                outputBytes: original.count,
                mimeType: "image/jpeg"
            )
            #endif
            return Result(
                data: original,
                mimeType: "image/jpeg",
                previewImage: nil
            )
        }

        #if DEBUG
        debugLogPrep(
            context: context,
            stage: "pickerDecoded",
            originalBytes: original.count,
            image: image,
            outputBytes: original.count,
            mimeType: "image/jpeg"
        )
        #endif

        let originalSize = image.size
        let longestSide = max(originalSize.width, originalSize.height)
        let scale: CGFloat = longestSide > maxLongestSide ? (maxLongestSide / longestSide) : 1.0
        let targetSize = CGSize(
            width: floor(originalSize.width * scale),
            height: floor(originalSize.height * scale)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        if let resizedData = resized.jpegData(compressionQuality: jpegQuality) {
            let result = Result(
                data: resizedData,
                mimeType: "image/jpeg",
                previewImage: resized
            )
            #if DEBUG
            debugLogPrep(
                context: context,
                stage: "resized1024q0.78",
                originalBytes: original.count,
                image: resized,
                outputBytes: result.data.count,
                mimeType: result.mimeType
            )
            #endif
            return result
        }

        if original.count <= smallEnoughOriginalThreshold {
            let result = Result(
                data: original,
                mimeType: "image/jpeg",
                previewImage: image
            )
            #if DEBUG
            debugLogPrep(
                context: context,
                stage: "smallOriginalPassThrough",
                originalBytes: original.count,
                image: image,
                outputBytes: result.data.count,
                mimeType: result.mimeType
            )
            #endif
            return result
        }

        if let jpegData = image.jpegData(compressionQuality: jpegQuality) {
            let result = Result(
                data: jpegData,
                mimeType: "image/jpeg",
                previewImage: image
            )
            #if DEBUG
            debugLogPrep(
                context: context,
                stage: "fullSizeJPEGq0.78",
                originalBytes: original.count,
                image: image,
                outputBytes: result.data.count,
                mimeType: result.mimeType
            )
            #endif
            return result
        }

        let result = Result(
            data: original,
            mimeType: "image/jpeg",
            previewImage: image
        )
        #if DEBUG
        debugLogPrep(
            context: context,
            stage: "lastResortOriginalPassThrough",
            originalBytes: original.count,
            image: image,
            outputBytes: result.data.count,
            mimeType: result.mimeType
        )
        #endif
        return result
        #else
        return Result(data: original, mimeType: "image/jpeg")
        #endif
    }
}

// MARK: - Offer gallery attachments (extras)

private struct OfferGalleryAttachmentsEditor: View {
    @Binding var heroImageURL: String?
    @Binding var galleryURLs: [String]
    @Binding var galleryPhotoItem: PhotosPickerItem?
    let isUploading: Bool
    let canAddMore: Bool
    @Binding var imageGalleryPresentation: SecretaryImageGalleryPresentation?
    let viewerTitle: String
    let viewerCaption: String
    let onRemoveGalleryIndex: (Int) -> Void

    private var orderedURLs: [String] {
        ExchangeOffer.limitedOrderedOfferImageURLs(
            primaryImageURL: heroImageURL,
            galleryImageURLs: galleryURLs
        )
    }

    private func presentationIndex(forGalleryIndex index: Int) -> Int {
        let hasHero = !(heroImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        return (hasHero ? 1 : 0) + index
    }

    private var titleForViewer: String? {
        let t = viewerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var captionForViewer: String? {
        let t = viewerCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Additional offer photos")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Text("Optional. Hero image above is shown first; extras appear after. Max \(ExchangeOffer.maxPublicOfferImageCount) images total.")
                .font(.system(size: 12))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(orderedURLs.count) / \(ExchangeOffer.maxPublicOfferImageCount) images")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkMutedText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(galleryURLs.indices, id: \.self) { index in
                        let raw = galleryURLs[index]
                        OfferGalleryThumbCell(
                            urlString: raw,
                            onTap: {
                                guard !orderedURLs.isEmpty else { return }
                                let start = presentationIndex(forGalleryIndex: index)
                                let clamped = min(max(0, start), max(0, orderedURLs.count - 1))
                                imageGalleryPresentation = SecretaryImageGalleryPresentation(
                                    imageURLs: orderedURLs,
                                    initialIndex: clamped,
                                    title: titleForViewer,
                                    caption: captionForViewer
                                )
                            },
                            onRemove: {
                                onRemoveGalleryIndex(index)
                            }
                        )
                    }

                    PhotosPicker(
                        selection: $galleryPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 4) {
                            if isUploading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(SecretaryTheme.darkOrange)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text(isUploading ? "…" : "Add")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(width: 62, height: 62)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.48))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
                        )
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                    .tint(SecretaryTheme.darkOrange)
                    .disabled(!canAddMore || isUploading)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct OfferGalleryThumbCell: View {
    let urlString: String
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let url = safeURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            SecretaryTheme.darkSurfaceStrong.opacity(0.55)
                        case .empty:
                            ProgressView()
                                .tint(SecretaryTheme.darkOrange)
                        @unknown default:
                            SecretaryTheme.darkSurfaceStrong.opacity(0.55)
                        }
                    }
                } else {
                    SecretaryTheme.darkSurfaceStrong.opacity(0.45)
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private var safeURL: URL? {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return nil
        }
        return url
    }
}

// MARK: - Public image card

private struct PublicSurfaceImageCard: View {
    let title: String
    let subtitle: String
    let currentURL: String?
    let hasLocalPreview: Bool
    let isProfile: Bool
    let isUploading: Bool
    let photoItem: Binding<PhotosPickerItem?>
    let onClear: () -> Void
    let onTapImage: (() -> Void)?

    private var hasExistingImage: Bool {
        hasLocalPreview || currentURL?.nilIfBlankOrNil != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let onTapImage, hasExistingImage {
                        PublicSurfaceImageThumbnail(
                            urlString: currentURL,
                            hasLocalPreview: hasLocalPreview,
                            isProfile: isProfile
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onTapImage)
                    } else {
                        PublicSurfaceImageThumbnail(
                            urlString: currentURL,
                            hasLocalPreview: hasLocalPreview,
                            isProfile: isProfile
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(
                        selection: photoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 6) {
                            if isUploading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(SecretaryTheme.darkOrange)
                            } else {
                                Image(systemName: hasExistingImage ? "arrow.triangle.2.circlepath" : "photo.badge.plus")
                                    .font(.system(size: 12, weight: .medium))
                            }

                            Text(isUploading ? "Uploading…" : (hasExistingImage ? "Replace" : "Choose photo"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
                        )
                        .overlay(
                            Capsule()
                                .stroke(SecretaryTheme.darkStroke.opacity(0.78), lineWidth: 1)
                        )
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    }
                    .tint(SecretaryTheme.darkOrange)
                    .disabled(isUploading)

                    if hasExistingImage {
                        Button(role: .destructive) {
                            onClear()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .medium))

                                Text("Remove image")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                        }
                        .buttonStyle(.plain)
                        .disabled(isUploading)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct PublicSurfaceImageThumbnail: View {
    let urlString: String?
    let hasLocalPreview: Bool
    let isProfile: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.42))

            if hasLocalPreview {
                Image(systemName: "photo.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
            } else if let url = safeURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                            .tint(SecretaryTheme.darkOrange)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.82), lineWidth: 1)
        )
    }

    private var safeURL: URL? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return nil
        }

        return url
    }

    @ViewBuilder
    private var placeholder: some View {
        Image(systemName: isProfile ? "person.crop.square" : "photo")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkMutedText)
    }
}

// MARK: - Small string helper

private extension String {
    var nilIfBlankOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

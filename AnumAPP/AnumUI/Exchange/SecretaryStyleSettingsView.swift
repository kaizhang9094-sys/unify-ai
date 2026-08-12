import SwiftUI
import PhotosUI
import UIKit

struct SecretaryStyleSettingsView: View {
    private static let secretaryAvatarDiameter: CGFloat = 64
    static let safeAutoFollowUpsTitle = "Autonomous inquiry & replies"
    static let safeAutoFollowUpsDescription = "Let your secretary ask safe follow-up questions and reply to routine inquiries."

    static let defaultConstitutionPlaceholder = """
    Represent me clearly and respectfully. Answer from my published facts. For narrow questions, answer narrowly. If facts are missing, say what needs confirmation.
    """

    static let defaultStylePlaceholder = "Warm, clear, concise, and low-pressure."

    @EnvironmentObject private var services: AppServices

    let onClose: () -> Void

    @State private var draftConstitution: String = ""
    @State private var draftStyle: String = ""
    @State private var isSaving = false
    @State private var didLoad = false

    /// Same companion disk avatar path as the former Threads `secretaryStatusCard` orb picker.
    @State private var pickedCompanionAvatarItem: PhotosPickerItem?
    @State private var companionAvatarCropSourceImage: UIImage?
    @State private var showCompanionAvatarCropper = false
    @AppStorage(CompanionAvatarDiskStorage.thumbFilenameKey) private var companionAvatarThumbFilename: String = ""
    @AppStorage(CompanionAvatarDiskStorage.fullFilenameKey) private var companionAvatarFullFilename: String = ""

    private let maxConstitutionCharacters = 1400
    private let maxStyleCharacters = 1400

    private enum MultilineCharacterLimitPolicy {
        /// Truncates pasted/typed input to `maxCharacters` (Style & tone).
        case clampAtMax
        /// Shows stored text even when longer than `maxCharacters`; blocks growth until within limit; always allows shortening.
        case allowShrinkOnlyWhenOverMax
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    avatarSection
                    constitutionSection
                    styleSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Secretary Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
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
                        (isSaving || !canSaveSecretaryInstructions)
                            ? SecretaryTheme.darkMutedText
                            : SecretaryTheme.darkOrange
                    )
                    .disabled(isSaving || !canSaveSecretaryInstructions)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                guard !didLoad else { return }
                didLoad = true
                draftConstitution = services.secretaryConstitutionText
                draftStyle = services.secretaryStyleText
                logSecretaryAvatarLoad(source: "panelOpen")
            }
        }
        .sharedPhotoCropperCover(
            isPresented: $showCompanionAvatarCropper,
            sourceImage: companionAvatarCropSourceImage,
            preset: .profileAvatar,
            title: "Adjust Avatar",
            onCancel: { dismissCompanionAvatarCropper() },
            onUse: { cropped in
                CompanionAvatarDiskStorage.saveReplacingAvatar(withPickedImage: cropped)
                #if DEBUG
                let thumb = UserDefaults.standard.string(forKey: CompanionAvatarDiskStorage.thumbFilenameKey) ?? ""
                let full = UserDefaults.standard.string(forKey: CompanionAvatarDiskStorage.fullFilenameKey) ?? ""
                print(
                    "[SecretaryAvatar] save succeeded path=Application Support/Avatars thumb=\(thumb) full=\(full)"
                )
                #endif
                dismissCompanionAvatarCropper()
            }
        )
        .preferredColorScheme(.dark)
        .tint(SecretaryTheme.darkOrange)
    }

    private var canSaveSecretaryInstructions: Bool {
        !constitutionExceedsMaxLength
    }

    private var constitutionExceedsMaxLength: Bool {
        draftConstitution.count > maxConstitutionCharacters
    }

    // MARK: - Dark chrome

    @ViewBuilder
    private func styleSettingsDarkCard<Content: View>(
        cornerRadius: CGFloat = 28,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        UnifyDarkCard(cornerRadius: cornerRadius) {
            inner
                .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
    }

    private func styleSettingsSectionHeader(title: String, systemImage: String) -> some View {
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

    private var trimmedConstitution: String {
        draftConstitution.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedStyle: String {
        draftStyle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var remainingConstitution: Int {
        max(0, maxConstitutionCharacters - draftConstitution.count)
    }

    private var remainingStyle: Int {
        max(0, maxStyleCharacters - draftStyle.count)
    }

    // MARK: - Secretary avatar (companion disk store; same as former Threads strip)

    private var avatarSection: some View {
        styleSettingsDarkCard {
            PhotosPicker(selection: $pickedCompanionAvatarItem, matching: .images) {
                HStack(alignment: .center, spacing: 14) {
                    CompanionAvatarThreadsHeroOrb(diameter: Self.secretaryAvatarDiameter)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Secretary avatar")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)

                        Text("Shown where your secretary appears in Threads and settings.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineSpacing(1.2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Change avatar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .onChange(of: pickedCompanionAvatarItem) { _, newItem in
                guard let newItem else { return }
                Task { @MainActor in
                    await presentCompanionAvatarCrop(from: newItem)
                    pickedCompanionAvatarItem = nil
                }
            }
            .onAppear {
                logSecretaryAvatarLoad(source: "avatarSectionAppear")
            }
            .onChange(of: companionAvatarThumbFilename) { _, _ in
                logSecretaryAvatarLoad(source: "thumbFilenameChanged")
            }
            .onChange(of: companionAvatarFullFilename) { _, _ in
                logSecretaryAvatarLoad(source: "fullFilenameChanged")
            }
        }
    }

    @MainActor
    private func presentCompanionAvatarCrop(from item: PhotosPickerItem) async {
        guard let ui = await SharedPhotoEditFlow.loadUIImage(from: item, context: "secretaryInstructionsAvatar") else {
            #if DEBUG
            print("[SecretaryAvatar] save failed error=pickerDecodeFailed")
            #endif
            return
        }
        #if DEBUG
        let byteCount = ui.jpegData(compressionQuality: 1.0)?.count ?? 0
        print("[SecretaryAvatar] picker selected bytes=\(byteCount)")
        #endif
        companionAvatarCropSourceImage = ui
        showCompanionAvatarCropper = true
    }

    @MainActor
    private func dismissCompanionAvatarCropper() {
        showCompanionAvatarCropper = false
        companionAvatarCropSourceImage = nil
    }

    private func logSecretaryAvatarLoad(source: String) {
        #if DEBUG
        let thumb = companionAvatarThumbFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = companionAvatarFullFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImage = CompanionAvatarDiskStorage.loadUIImage(thumbFilename: thumb, fullFilename: full) != nil
        print(
            "[SecretaryAvatar] load source=\(source) hasImage=\(hasImage) " +
            "thumb=\(thumb.isEmpty ? "empty" : thumb) full=\(full.isEmpty ? "empty" : full)"
        )
        #endif
    }

    // MARK: - Constitution

    private var constitutionSection: some View {
        styleSettingsDarkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    styleSettingsSectionHeader(
                        title: "Constitution",
                        systemImage: "person.text.rectangle"
                    )
                    Spacer(minLength: 8)
                    Text("\(remainingConstitution) left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            remainingConstitution < 120
                                ? SecretaryTheme.darkOrange
                                : SecretaryTheme.darkSecondaryText
                        )
                        .multilineTextAlignment(.trailing)
                }

                Text("Define how your secretary represents you and what boundaries it should keep.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineSpacing(1.2)
                    .fixedSize(horizontal: false, vertical: true)

                if constitutionExceedsMaxLength {
                    Text(
                        "This text is longer than \(maxConstitutionCharacters) characters. Shorten it to save — " +
                            "your stored copy is unchanged until you save."
                    )
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                multilineEditor(
                    text: $draftConstitution,
                    maxCharacters: maxConstitutionCharacters,
                    minHeight: 200,
                    showPlaceholder: trimmedConstitution.isEmpty,
                    emptyHint: Self.defaultConstitutionPlaceholder,
                    characterLimitPolicy: .allowShrinkOnlyWhenOverMax
                )

                if !trimmedConstitution.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            draftConstitution = ""
                        }
                    } label: {
                        Text("Clear constitution")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Style & tone

    private var styleSection: some View {
        styleSettingsDarkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    styleSettingsSectionHeader(
                        title: "Style & tone",
                        systemImage: "text.quote"
                    )
                    Spacer(minLength: 8)
                    Text("\(remainingStyle) left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            remainingStyle < 120
                                ? SecretaryTheme.darkOrange
                                : SecretaryTheme.darkSecondaryText
                        )
                        .multilineTextAlignment(.trailing)
                }

                Text("Choose the voice. Style does not change facts, permissions, or approvals.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineSpacing(1.2)
                    .fixedSize(horizontal: false, vertical: true)

                multilineEditor(
                    text: $draftStyle,
                    maxCharacters: maxStyleCharacters,
                    minHeight: 160,
                    showPlaceholder: trimmedStyle.isEmpty,
                    emptyHint: Self.defaultStylePlaceholder,
                    characterLimitPolicy: .clampAtMax
                )

                if !trimmedStyle.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            draftStyle = ""
                        }
                    } label: {
                        Text("Clear style")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func multilineEditor(
        text: Binding<String>,
        maxCharacters: Int,
        minHeight: CGFloat,
        showPlaceholder: Bool,
        emptyHint: String,
        characterLimitPolicy: MultilineCharacterLimitPolicy
    ) -> some View {
        let limitedBinding = Binding(
            get: { text.wrappedValue },
            set: { newValue in
                switch characterLimitPolicy {
                case .clampAtMax:
                    if newValue.count <= maxCharacters {
                        text.wrappedValue = newValue
                    } else {
                        text.wrappedValue = String(newValue.prefix(maxCharacters))
                    }
                case .allowShrinkOnlyWhenOverMax:
                    if newValue.count <= maxCharacters {
                        text.wrappedValue = newValue
                    } else if newValue.count < text.wrappedValue.count {
                        text.wrappedValue = newValue
                    }
                }
            }
        )

        return ZStack(alignment: .topLeading) {
            UnifySoftVeilRoundedRectangle(cornerRadius: 22, strokeOpacity: 0.88)

            TextEditor(text: limitedBinding)
                .font(.system(size: 15))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                .tint(SecretaryTheme.darkOrange)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: minHeight)

            if showPlaceholder {
                Text(emptyHint)
                    .font(.system(size: 15))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        guard canSaveSecretaryInstructions else { return }

        isSaving = true

        Task { @MainActor in
            services.saveSecretaryConstitutionText(trimmedConstitution)
            services.saveSecretaryStyleText(trimmedStyle)

            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil
            )

            isSaving = false
            onClose()
        }
    }
}

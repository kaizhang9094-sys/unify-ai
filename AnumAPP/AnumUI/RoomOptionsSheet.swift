import SwiftUI
import Foundation
import PhotosUI
import UIKit
import StoreKit
import Combine
import AnumCore

struct RoomOptionsSheet: View {
    // Kept for compatibility with older call sites. No longer used.
    private let onResetOnboarding: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices

    @State private var exchangePendingCount: Int = 0
    
    init(onResetOnboarding: @escaping () -> Void = {}) {
        self.onResetOnboarding = onResetOnboarding
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                PremiumOptionsBackground()

                contentList
            }
            .navigationTitle("Your Space")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.white)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            Task {
                await refreshExchangeBadge()
            }
        }
        .tint(.white)
        .background(Color.clear)
        .presentationBackground(.clear)
        .presentationCornerRadius(26)
    }
    
    private var contentList: some View {
        ScrollView {
            VStack(spacing: 12) {
                NavigationLink {
                    AvatarPresenceView()
                } label: {
                    PremiumNavRow(
                        title: "Avatar & Presence",
                        subtitle: "Avatar and background"
                    )
                }

                NavigationLink {
                    PrologueView()
                } label: {
                    PremiumNavRow(
                        title: "Prologue",
                        subtitle: "Set the stage in short phrases"
                    )
                }

                NavigationLink {
                    MemoryView()
                } label: {
                    PremiumNavRow(
                        title: "Memory",
                        subtitle: "Clear, export, delete"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }

    private func refreshExchangeBadge() async {
        do {
            let approvals = try await services.exchangeFacade.listPendingApprovals()
            await MainActor.run {
                exchangePendingCount = approvals.count
            }
        } catch {
            await MainActor.run {
                exchangePendingCount = 0
            }
        }
    }
}

// MARK: - Common Row

private struct PremiumOptionsBackground: View {
    var body: some View {
        ZStack {
            // Transparent base.
            Color.black.opacity(0.001).ignoresSafeArea()

            // Glass blur so the room image still reads behind.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            // Dark-to-clear tint: slightly darker at the top, fades out as you go down.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.02),
                    Color.black.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Frost / milky wash that gets *lighter* toward the bottom.
            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.white.opacity(0.035),
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.085)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

private struct PremiumCard: View {
    let content: AnyView

    init<Content: View>(@ViewBuilder _ content: () -> Content) {
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct PremiumNavRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        PremiumCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
    }
}

private struct PremiumSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

private struct PremiumActionRow: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let role: ButtonRole?
    let action: () -> Void

    init(title: String, subtitle: String? = nil, icon: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            action()
        } label: {
            PremiumCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(role == .destructive ? Color.red.opacity(0.95) : .white)

                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    Spacer(minLength: 8)

                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Offering — Required-style cards (profile subpanels)

/// Tappable row using the same glass card shell as **Offering — Required** (`UnifyDarkCard(cornerRadius: 18)` + 14pt inner padding).
private struct UnifyOfferingStyleActionRow: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let role: ButtonRole?
    let action: () -> Void

    init(title: String, subtitle: String? = nil, icon: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            action()
        } label: {
            UnifyDarkCard(cornerRadius: 18) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(role == .destructive ? Color.red.opacity(0.95) : SecretaryTheme.darkPrimaryText)

                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        }
                    }

                    Spacer(minLength: 8)

                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
                }
                .contentShape(Rectangle())
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Navigation row label using the same card shell as **Offering — Required**.
private struct UnifyOfferingStyleNavCardLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        UnifyDarkCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }
            .contentShape(Rectangle())
            .padding(14)
        }
    }
}

// MARK: - Avatar & Presence

private struct AvatarPresenceView: View {
    // Shared keys with RoomView
    @AppStorage("companionAvatarThumbFilename") private var avatarThumbFilename: String = ""
    @AppStorage("companionAvatarFullFilename") private var avatarFullFilename: String = ""
    @AppStorage("companionBackgroundThumbFilename") private var bgThumbFilename: String = ""
    @AppStorage("companionBackgroundFullFilename") private var bgFullFilename: String = ""

    @State private var avatarThumbUIImage: UIImage? = nil
    @State private var avatarFullUIImage: UIImage? = nil
    @State private var bgThumbUIImage: UIImage? = nil
    @State private var bgFullUIImage: UIImage? = nil

    @State private var showAvatarViewer: Bool = false
    @State private var showAvatarPicker: Bool = false
    @State private var pickedAvatarItem: PhotosPickerItem? = nil

    @State private var showBgViewer: Bool = false
    @State private var showBgPicker: Bool = false
    @State private var pickedBgItem: PhotosPickerItem? = nil

    // Cropper
    @State private var showCropper: Bool = false
    @State private var cropTarget: CropTarget? = nil
    @State private var cropSourceImage: UIImage? = nil

    private enum CropTarget {
        case avatar
        case background
    }

    var body: some View {
        ZStack {
            PremiumOptionsBackground()

            ScrollView {
                VStack(spacing: 12) {
                    PremiumCard {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))

                            Text("Everything stays on this device.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))

                            Spacer(minLength: 0)
                        }
                    }

                    PremiumActionRow(title: "Avatar photo", subtitle: nil, icon: avatarFullUIImage != nil ? "chevron.right" : "photo") {
                        if avatarFullUIImage != nil {
                            showAvatarViewer = true
                        } else {
                            showAvatarPicker = true
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if let thumb = avatarThumbUIImage {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )
                                .padding(.trailing, 44)
                        }
                    }

                    PremiumActionRow(title: "Background photo", subtitle: nil, icon: bgFullUIImage != nil ? "chevron.right" : "photo") {
                        if bgFullUIImage != nil {
                            showBgViewer = true
                        } else {
                            showBgPicker = true
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if let thumb = bgThumbUIImage {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )
                                .padding(.trailing, 44)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Avatar & Presence")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.white)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { loadFromDisk() }
        .onChange(of: avatarThumbFilename) { _, _ in loadFromDisk() }
        .onChange(of: avatarFullFilename) { _, _ in loadFromDisk() }
        .onChange(of: bgThumbFilename) { _, _ in loadFromDisk() }
        .onChange(of: bgFullFilename) { _, _ in loadFromDisk() }
        // Avatar
        .photosPicker(isPresented: $showAvatarPicker, selection: $pickedAvatarItem, matching: .images)
        .onChange(of: pickedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePickedAvatar(newItem) }
        }
        .fullScreenCover(isPresented: $showAvatarViewer) {
            if let full = avatarFullUIImage {
                PhotoViewer(
                    image: full,
                    title: "Avatar",
                    onChangePhoto: {
                        showAvatarViewer = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showAvatarPicker = true
                        }
                    },
                    onRemovePhoto: {
                        removeAvatar()
                        showAvatarViewer = false
                    }
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        // Background
        .photosPicker(isPresented: $showBgPicker, selection: $pickedBgItem, matching: .images)
        .onChange(of: pickedBgItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePickedBackground(newItem) }
        }
        .fullScreenCover(isPresented: $showBgViewer) {
            if let full = bgFullUIImage {
                PhotoViewer(
                    image: full,
                    title: "Background",
                    onChangePhoto: {
                        showBgViewer = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showBgPicker = true
                        }
                    },
                    onRemovePhoto: {
                        removeBackground()
                        showBgViewer = false
                    }
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        // Cropper (used for both avatar and background)
        .fullScreenCover(isPresented: $showCropper) {
            if let img = cropSourceImage, let target = cropTarget {
                SharedPhotoCropperView(
                    sourceImage: img,
                    preset: target == .avatar
                        ? .profileAvatar
                        : .custom(
                            aspectRatio: UIScreen.main.bounds.width / UIScreen.main.bounds.height,
                            maxCropWidth: 340,
                            maxCropHeight: 460,
                            maskCornerRadius: 14,
                            initialScale: .aspectFill,
                            maskStyle: .roundedRectangle
                        ),
                    title: target == .avatar ? "Adjust Avatar" : "Adjust Background",
                    onCancel: {
                        cropSourceImage = nil
                        cropTarget = nil
                        showCropper = false
                    },
                    onUse: { cropped in
                        showCropper = false
                        if target == .avatar {
                            saveCroppedAvatar(cropped)
                        } else {
                            saveCroppedBackground(cropped)
                        }
                        cropSourceImage = nil
                        cropTarget = nil
                    }
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }

    private func row(title: String, thumb: UIImage?) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private func deleteAssetIfExists(_ filename: String) {
        guard !filename.isEmpty else { return }
        let url = assetsDirURL().appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Disk IO (shared with RoomView)

    private func assetsDirURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Avatars", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func loadImage(named filename: String) -> UIImage? {
        let url = assetsDirURL().appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func saveJPEG(_ image: UIImage, filename: String, quality: CGFloat) {
        let url = assetsDirURL().appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: quality) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func loadFromDisk() {
        avatarThumbUIImage = avatarThumbFilename.isEmpty ? nil : loadImage(named: avatarThumbFilename)
        avatarFullUIImage = avatarFullFilename.isEmpty ? nil : loadImage(named: avatarFullFilename)
        bgThumbUIImage = bgThumbFilename.isEmpty ? nil : loadImage(named: bgThumbFilename)
        bgFullUIImage = bgFullFilename.isEmpty ? nil : loadImage(named: bgFullFilename)
    }

    // MARK: - Image processing


    private func resizeToSquare(_ image: UIImage, side: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func resizeLongestEdge(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    @MainActor
    private func handlePickedAvatar(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }

        // Open cropper so the user can pan/zoom to choose framing.
        cropTarget = .avatar
        cropSourceImage = ui
        showCropper = true

        pickedAvatarItem = nil
    }

    private func removeAvatar() {
        deleteAssetIfExists(avatarThumbFilename)
        deleteAssetIfExists(avatarFullFilename)
        avatarThumbFilename = ""
        avatarFullFilename = ""
        loadFromDisk()
    }

    @MainActor
    private func handlePickedBackground(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }

        // Open cropper so the user can pan/zoom to choose framing.
        cropTarget = .background
        cropSourceImage = ui
        showCropper = true

        pickedBgItem = nil
    }

    private func saveCroppedAvatar(_ cropped: UIImage) {
        // For avatar: cropped is square.
        let full = resizeLongestEdge(cropped, maxEdge: 2048)
        let thumb = resizeToSquare(cropped, side: 256)

        // Remove previous files to avoid accumulation.
        deleteAssetIfExists(avatarThumbFilename)
        deleteAssetIfExists(avatarFullFilename)

        let stamp = UUID().uuidString
        let thumbName = "companion_avatar_thumb_\(stamp).jpg"
        let fullName = "companion_avatar_full_\(stamp).jpg"

        saveJPEG(thumb, filename: thumbName, quality: 0.82)
        saveJPEG(full, filename: fullName, quality: 0.85)

        // IMPORTANT: new filenames force @AppStorage change so RoomView updates immediately.
        avatarThumbFilename = thumbName
        avatarFullFilename = fullName
        loadFromDisk()
    }

    private func saveCroppedBackground(_ cropped: UIImage) {
        let full = resizeLongestEdge(cropped, maxEdge: 2048)
        let thumb = resizeLongestEdge(cropped, maxEdge: 512)

        // Remove previous files to avoid accumulation.
        deleteAssetIfExists(bgThumbFilename)
        deleteAssetIfExists(bgFullFilename)

        let stamp = UUID().uuidString
        let thumbName = "companion_bg_thumb_\(stamp).jpg"
        let fullName = "companion_bg_full_\(stamp).jpg"

        saveJPEG(thumb, filename: thumbName, quality: 0.80)
        saveJPEG(full, filename: fullName, quality: 0.85)

        // IMPORTANT: new filenames force @AppStorage change so RoomView updates immediately.
        bgThumbFilename = thumbName
        bgFullFilename = fullName
        loadFromDisk()
    }

    private func removeBackground() {
        deleteAssetIfExists(bgThumbFilename)
        deleteAssetIfExists(bgFullFilename)
        bgThumbFilename = ""
        bgFullFilename = ""
        loadFromDisk()
    }
}

// MARK: - Prologue

private struct PrologueView: View {
    @AppStorage("companionPrologue") private var savedPrologue: String = ""
    @State private var draft: String = ""
    @State private var showSavedAlert: Bool = false

    private let limit: Int = 300

    var body: some View {
        ZStack {
            PremiumOptionsBackground()

            ScrollView {
                VStack(spacing: 12) {
                    PremiumCard {
                        Text("Use this to set the starting environment: roles, relationship, current moment and more. Short phrases work best.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PremiumCard {
                        VStack(alignment: .leading, spacing: 10) {
                            TextEditor(text: $draft)
                                .frame(minHeight: 180)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .foregroundStyle(.white)
                                .onChange(of: draft) { _, newValue in
                                    if newValue.count > limit {
                                        draft = String(newValue.prefix(limit))
                                    }
                                }

                            HStack {
                                Spacer()
                                Text("\(draft.count)/\(limit)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        PremiumActionRow(title: "Save", subtitle: nil, icon: nil) {
                            savedPrologue = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            showSavedAlert = true
                        }

                        PremiumActionRow(title: "Clear", subtitle: nil, icon: nil, role: .destructive) {
                            draft = ""
                            savedPrologue = ""
                        }
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Prologue")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.white)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { draft = savedPrologue }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your prologue has been saved.")
        }
    }
}

// MARK: - Memory

private struct MemoryView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var chat: ChatViewModel

    // Onboarding state (hard reset).
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = false
    @AppStorage("companionName") private var companionName: String = ""
    @AppStorage("companionGenderRaw") private var companionGenderRaw: String = ""
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userGenderRaw") private var userGenderRaw: String = ""

    @State private var showClearConfirm: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isWipingCompanionData: Bool = false

    @State private var isExporting: Bool = false
    @State private var exportURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportErrorMessage: String = ""
    @State private var showExportError: Bool = false

    var body: some View {
        ZStack {
            PremiumOptionsBackground()

            ScrollView {
                VStack(spacing: 12) {
                    // Move the note to the top.
                    PremiumCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Private by design")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)

                            Text("Everything stays on this device. Nothing is sent to servers.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    #if DEBUG
                    exchangeIdentityDebugCard
                    #endif

                    // Non-destructive action(s).
                    PremiumActionRow(title: "Export my data", subtitle: nil, icon: isExporting ? nil : "square.and.arrow.up") {
                        guard !isExporting else { return }
                        isExporting = true
                        Task {
                            do {
                                let url = try await services.exportMyDataZip()
                                await MainActor.run {
                                    self.exportURL = url
                                    self.isExporting = false
                                    self.showShareSheet = true
                                }
                            } catch {
                                await MainActor.run {
                                    self.isExporting = false
                                    self.exportErrorMessage = String(describing: error)
                                    self.showExportError = true
                                }
                            }
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if isExporting {
                            ProgressView()
                                .padding(.trailing, 44)
                        }
                    }
                    .disabled(isExporting || isWipingCompanionData)

                    // Group destructive actions together.

                    PremiumActionRow(title: "Clear recent chat", subtitle: nil, icon: nil, role: .destructive) {
                        showClearConfirm = true
                    }
                    .disabled(isWipingCompanionData)

                    PremiumActionRow(title: "Delete Companion Data", subtitle: "Companion chat, memory, and avatars on this device", icon: "trash", role: .destructive) {
                        guard !isWipingCompanionData else { return }
                        DispatchQueue.main.async { showDeleteConfirm = true }
                    }
                    .disabled(isWipingCompanionData)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .overlay {
                if isWipingCompanionData {
                    PremiumCard {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Deleting…")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.white)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog("Clear recent chat?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                chat.clearRecentChat()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the visible conversation in this room.")
        }
        .alert("Delete Companion Data?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                showDeleteConfirm = false
                Task {
                    await MainActor.run {
                        isWipingCompanionData = true
                        // Clear in-memory chat immediately so it doesn’t reappear after reset.
                        chat.clearRecentChat()
                    }

                    // Do the actual wipe.
                    await services.wipeCompanionDataOnly()

                    // Give the UI a moment to dismiss the alert/sheet cleanly.
                    try? await Task.sleep(nanoseconds: 350_000_000)

                    await MainActor.run {
                        // Defensive: ensure chat is empty even if wipeCompanionDataOnly missed transcript deletion.
                        chat.clearRecentChat()
                        isWipingCompanionData = false

                        // Hard reset onboarding without triggering an additional confirmation UI.
                        hardResetOnboardingState()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                guard !isWipingCompanionData else { return }
                showDeleteConfirm = false
            }
        } message: {
            Text("This removes Companion chat, on-device memory, and room avatars. Secretary and Exchange data on this device are not deleted.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing export…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding()
            }
        }
        .alert("Export failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
        #if DEBUG
        .task {
            await services.refreshExchangeIdentityDebugSummary()
        }
        #endif
    }
    // Helper to hard-reset onboarding AppStorage keys without triggering extra UI.
    private func hardResetOnboardingState() {
        // Avoid triggering any additional confirmation UI elsewhere.
        // Switching this flag will cause RootView to show onboarding.
        hasOnboarded = false

        // Reset the core onboarding fields.
        companionName = ""
        companionGenderRaw = ""
        userName = ""
        userGenderRaw = ""
        UnifyOnboardingKeys.clearV2Keys()
    }

    #if DEBUG
    private var exchangeIdentityDebugCard: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Exchange identity (debug)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                if let summary = services.exchangeIdentityDebugSummary {
                    debugLine("Node ID", summary.nodeID ?? "Unavailable")
                    debugLine("Public Key ID", summary.publicKeyID ?? "Unavailable")
                    debugLine("Display Name", summary.displayName ?? "Unavailable")
                    debugLine("Identity Source", summary.sourceLabel)
                    debugLine("Exchange DB", "\(summary.databaseStatus) · \(summary.databasePath)")
                    debugLine("Local Profile", summary.localProfileExists ? "Yes" : "No")
                    debugLine("Local Offers", "\(summary.localOfferCount)")
                    debugLine("Local Threads", "\(summary.localThreadCount)")
                    debugLine("Local Inbox", "\(summary.localInboxCount)")
                    debugLine("Seller Workspace", summary.sellerWorkspaceExists ? "Yes" : "No")

                    if summary.restoredIdentityWithEmptyLocalStore {
                        Text("Node identity restored. Local Exchange history may be missing after reinstall. Republish or re-sync before testing continuity.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.orange.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Loading local debug identity info…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text("This is local debug identity info.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.40))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func debugLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.70))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    #endif
}

// MARK: - Special Thanks

/// Inner body for Special Thanks (shared: profile shell sheet + any future full-screen host).
struct SpecialThanksContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            UnifyDarkCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Thank You")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Text("To the open-source and research communities, especially the teams behind Qwen and ChatGPT. No affiliation or endorsement implied.")
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            NavigationLink {
                LicensesView()
            } label: {
                UnifyOfferingStyleNavCardLabel(title: "Licenses", subtitle: "Licenses & notices")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }
}

struct SpecialThanksView: View {
    var body: some View {
        ZStack {
            PremiumOptionsBackground()

            ScrollView {
                SpecialThanksContentView()
            }
        }
        .navigationTitle("Special Thanks")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.white)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Licenses

struct LicensesView: View {
    // Full texts are intentionally embedded so they ship with the app.
    private let apache2Text: String = """
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      \"License\" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      \"Licensor\" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      \"Legal Entity\" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      \"control\" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      \"You\" (or \"Your\") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      \"Source\" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      \"Object\" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      \"Work\" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      \"Derivative Works\" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      \"Contribution\" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, \"submitted\"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as \"Not a Contribution.\"

      \"Contributor\" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a \"NOTICE\" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an \"AS IS\" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      Copyright [yyyy] [name of copyright owner]

      Licensed under the Apache License, Version 2.0 (the \"License\");
      you may not use this file except in compliance with the License.
      You may obtain a copy of the License at

          http://www.apache.org/licenses/LICENSE-2.0

      Unless required by applicable law or agreed to in writing, software
      distributed under the License is distributed on an \"AS IS\" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
      See the License for the specific language governing permissions and
      limitations under the License.
"""

    private let mitText: String = """
MIT License

Copyright (c) the llama.cpp contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the \"Software\"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                UnifyDarkCard(cornerRadius: 18, strokeOpacity: 0.88) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Third-Party Licenses")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)

                        Text("This app includes software and model weights. Licenses are provided for attribution.")
                            .font(.system(size: 13))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }

                UnifyDarkCard(cornerRadius: 18, strokeOpacity: 0.88) {
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup {
                            Text(apache2Text)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Qwen LLM")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                                Text("Apache License 2.0")
                                    .font(.system(size: 13))
                                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            }
                        }

                        Rectangle()
                            .fill(SecretaryTheme.darkStroke.opacity(0.35))
                            .frame(height: 1)

                        DisclosureGroup {
                            Text(mitText)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Llama")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                                Text("MIT License")
                                    .font(.system(size: 13))
                                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(UnifyIceShellBackground())
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
        .tint(SecretaryTheme.darkOrange)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}


private struct TermsLinksCard: View {
    let termsURL: URL?
    let privacyURL: URL?

    var body: some View {
        UnifyDarkCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Terms of Use")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)

                VStack(spacing: 0) {
                    if let url = termsURL {
                        Link(destination: url) {
                            termsRow(title: "EULA", subtitle: "Apple EULA")
                        }
                        .buttonStyle(.plain)
                    }

                    if termsURL != nil && privacyURL != nil {
                        Rectangle()
                            .fill(SecretaryTheme.darkStroke.opacity(0.35))
                            .frame(height: 1)
                            .padding(.vertical, 4)
                    }

                    if let url = privacyURL {
                        Link(destination: url) {
                            termsRow(title: "Privacy Policy", subtitle: "Unify privacy policy")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func termsRow(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Guardians (shared content)

/// Inner body for Guardians / StoreKit support (parent supplies scroll, background, navigation, and `.task`).
struct GuardiansContentView: View {
    @ObservedObject var store: SupportStore
    @State private var isPurchasingMonthly: Bool = false
    @State private var isRestoring: Bool = false
    @State private var isOpeningManage: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            UnifyDarkCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Guardians of Unify")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)

                    Text("Support a local-first, user-owned AI network.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Text("Unify is built to stay user-owned: private by design, end-to-end encrypted, and without ads, tracking, user profiling, or behavior-shaping feeds. Becoming a Guardian helps protect this direction and fund ongoing development so Unify can keep improving without compromise.")
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Text("Guardianship keeps the project independent, aligned, and improving.")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            UnifyOfferingStyleActionRow(
                title: store.isSupportingMonthly ? (store.isMonthlyAutoRenewOn ? "Guardian — Active" : "Guardian — Active (Canceled)") : "Guardianship (Monthly)",
                subtitle: store.isSupportingMonthly
                    ? "Thank you for guarding Unify"
                    : (store.monthlyDisplayPrice.map { "Ongoing support • \($0)" } ?? "Loading price…"),
                icon: isPurchasingMonthly ? nil : (store.isSupportingMonthly ? "checkmark.seal.fill" : "star")
            ) {
                Task { await purchaseMonthly() }
            }
            .overlay(alignment: .trailing) {
                if isPurchasingMonthly {
                    ProgressView()
                        .padding(.trailing, 44)
                }
            }
            .disabled(isPurchasingMonthly)

            UnifyOfferingStyleActionRow(
                title: "Restore Purchases",
                subtitle: "Re-check Apple entitlements",
                icon: isRestoring ? nil : "arrow.clockwise"
            ) {
                Task { await restorePurchases() }
            }
            .overlay(alignment: .trailing) {
                if isRestoring {
                    ProgressView()
                        .padding(.trailing, 44)
                }
            }
            .disabled(isRestoring || isPurchasingMonthly)

            if store.isSupportingMonthly {
                UnifyOfferingStyleActionRow(
                    title: "Manage Subscription",
                    subtitle: "Cancel subscription",
                    icon: isOpeningManage ? nil : "gearshape"
                ) {
                    Task { await openManageSubscriptions() }
                }
                .overlay(alignment: .trailing) {
                    if isOpeningManage {
                        ProgressView()
                            .padding(.trailing, 44)
                    }
                }
                .disabled(isOpeningManage || isPurchasingMonthly)
            }

            if let msg = store.lastMessage {
                UnifyDarkCard(cornerRadius: 18) {
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    @MainActor
    private func purchaseMonthly() async {
        guard !isPurchasingMonthly else { return }
        isPurchasingMonthly = true
        defer { isPurchasingMonthly = false }
        await store.purchase(productID: SupportStore.monthlyID)
        await store.refreshEntitlements()
        await store.refreshAutoRenewStatus()
    }

    @MainActor
    private func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            store.lastMessage = "Restored. Checking status…"
        } catch {
            store.lastMessage = error.localizedDescription
        }
        await store.refreshEntitlements()
        await store.refreshAutoRenewStatus()
    }

    @MainActor
    private func openManageSubscriptions() async {
        guard !isOpeningManage else { return }
        isOpeningManage = true
        defer { isOpeningManage = false }

        guard let scene = activeWindowScene() else {
            store.lastMessage = "Unable to open Apple subscription settings on this device. You can manage it in Settings → Apple ID → Subscriptions."
            return
        }

        do {
            try await AppStore.showManageSubscriptions(in: scene)
            try? await AppStore.sync()
            await store.refreshEntitlements()
            await store.refreshAutoRenewStatus()
        } catch {
            store.lastMessage = "Unable to open Apple subscription settings on this device. You can manage it in Settings → Apple ID → Subscriptions."
        }
    }

    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active
        }
        return scenes.first
    }
}

// MARK: - Help

/// Inner body for Help (shared: profile shell sheet + `HelpView` room-style host).
struct HelpContentView: View {
    private let feedbackEmail: String = "admin@unifynow.ca"

    private let termsURLString: String = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    private let privacyURLString: String = "https://www.unify-now.com/pages/unify-private-ai-support"

    private var termsURL: URL? { URL(string: termsURLString) }
    private var privacyURL: URL? { URL(string: privacyURLString) }

    @Binding var showCopied: Bool

    var body: some View {
        VStack(spacing: 12) {
            UnifyDarkCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        UIPasteboard.general.string = feedbackEmail
                        showCopied = true
                    } label: {
                        HStack {
                            Text("Send Feedback")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            Spacer()
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(feedbackEmail)
                        .font(.system(size: 13))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .textSelection(.enabled)

                    Text("Tap to copy the email address.")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            NavigationLink {
                SafetyPrivacyView(feedbackEmail: feedbackEmail)
            } label: {
                UnifyOfferingStyleNavCardLabel(title: "Safety & Privacy", subtitle: "Guidelines and privacy")
            }
            .buttonStyle(.plain)

            TermsLinksCard(termsURL: termsURL, privacyURL: privacyURL)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }
}

struct HelpView: View {
    private let feedbackEmail: String = "admin@unifynow.ca"

    @State private var showCopied: Bool = false

    var body: some View {
        ZStack {
            PremiumOptionsBackground()

            ScrollView {
                HelpContentView(showCopied: $showCopied)
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.white)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Copied", isPresented: $showCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(feedbackEmail) copied to clipboard.")
        }
    }
}


// MARK: - ShareSheet Helper

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - PhotoViewer Helper

private struct PhotoViewer: View {
    let image: UIImage
    let title: String
    let onChangePhoto: () -> Void
    let onRemovePhoto: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showEdit: Bool = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnify)
                    .gesture(pan)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if scale > 1 {
                                scale = 1
                                lastScale = 1
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2
                                lastScale = 2
                            }
                        }
                    }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }
                        .foregroundStyle(.white)
                }
            }
            .confirmationDialog("Edit", isPresented: $showEdit, titleVisibility: .visible) {
                Button("Change Photo") { onChangePhoto() }
                Button("Remove Photo", role: .destructive) { onRemovePhoto() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .tint(.white)
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                let newScale = scale * delta
                scale = min(max(newScale, 1), 4)
                lastScale = value
            }
            .onEnded { _ in
                lastScale = 1
                if scale <= 1 {
                    scale = 1
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}


// MARK: - StoreKit Support (Tips + Monthly)

@MainActor
final class SupportStore: ObservableObject {
    // IMPORTANT: These product IDs must match your .storekit config and App Store Connect.
    // If you used different IDs in the .storekit file, update these strings.
    static let monthlyID  = "ca.unifynow.AnumAPP.support.monthly" // Display name: “Coffee on Me!”

    @Published var isSupportingMonthly: Bool = false
    @Published var isMonthlyAutoRenewOn: Bool = true
    @Published var lastMessage: String? = nil

    @Published var monthlyProduct: Product? = nil

    var monthlyDisplayPrice: String? {
        monthlyProduct?.displayPrice
    }

    private var updatesTask: Task<Void, Never>?

    func start() {
        // Idempotent
        if updatesTask != nil { return }
        updatesTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshEntitlements()
            await self.refreshAutoRenewStatus()
            for await update in Transaction.updates {
                // Always verify + finish updates; then refresh.
                if let txn = try? self.requireVerified(update) {
                    await txn.finish()
                }
                await self.refreshEntitlements()
                await self.refreshAutoRenewStatus()
            }
        }
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.monthlyID])
            monthlyProduct = products.first(where: { $0.id == Self.monthlyID })
            if monthlyProduct == nil {
                lastMessage = "Product not found for ID: \(Self.monthlyID)."
            }
        } catch {
            monthlyProduct = nil
            lastMessage = error.localizedDescription
        }
    }

    func purchase(productID: String) async {
        lastMessage = nil
        do {
            let product: Product?
            if productID == Self.monthlyID, let cached = monthlyProduct {
                product = cached
            } else {
                let products = try await Product.products(for: [productID])
                product = products.first
            }

            guard let product else {
                // Refresh cache so the UI shows a concrete diagnostic.
                await loadProducts()
                if lastMessage == nil {
                    lastMessage = "Product not found for ID: \(productID)."
                }
                return
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let txn = try requireVerified(verification)
                await txn.finish()
                lastMessage = "Thank you — guardianship is active."
                await refreshEntitlements()
                await refreshAutoRenewStatus()
            case .userCancelled:
                break
            case .pending:
                lastMessage = "Purchase pending approval."
            @unknown default:
                lastMessage = "Unknown purchase state."
            }
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var activeMonthly = false
        for await entitlement in Transaction.currentEntitlements {
            do {
                let txn = try requireVerified(entitlement)
                if txn.productID == Self.monthlyID, txn.revocationDate == nil {
                    activeMonthly = true
                }
            } catch {
                // Ignore unverified entitlements
            }
        }
        isSupportingMonthly = activeMonthly
        updateGuardianMessageIfNeeded()
    }

    func refreshAutoRenewStatus() async {
        // Default to ON so we don't show a scary “canceled” state if status fetch fails.
        var autoRenewOn = true

        do {
            let products = try await Product.products(for: [Self.monthlyID])
            guard let product = products.first, let sub = product.subscription else {
                isMonthlyAutoRenewOn = autoRenewOn
                updateGuardianMessageIfNeeded()
                return
            }

            // StoreKit returns an array of Status for the subscription group.
            let statuses = try await sub.status

            // Prefer an active-like status if present.
            let best = statuses.first(where: { status in
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    return true
                default:
                    return false
                }
            }) ?? statuses.first

            guard let best else {
                isMonthlyAutoRenewOn = autoRenewOn
                updateGuardianMessageIfNeeded()
                return
            }

            // If the subscription is not active anymore, auto-renew is effectively off.
            switch best.state {
            case .expired, .revoked:
                autoRenewOn = false
            default:
                // Use RenewalInfo.willAutoRenew to detect “canceled but still active”.
                do {
                    let renewalInfo = try requireVerified(best.renewalInfo)
                    autoRenewOn = renewalInfo.willAutoRenew
                } catch {
                    // If we can't verify renewal info, keep the safe default.
                    autoRenewOn = true
                }
            }
        } catch {
            // Ignore; keep default.
        }

        isMonthlyAutoRenewOn = autoRenewOn
        updateGuardianMessageIfNeeded()
    }

    private func updateGuardianMessageIfNeeded() {
        // Only overwrite status-style messages; never clobber real error diagnostics.
        let isStatusMessage: (String) -> Bool = { msg in
            msg.hasPrefix("Thank you") ||
            msg.hasPrefix("Auto‑renew") ||
            msg.hasPrefix("Restored")
        }

        if isSupportingMonthly {
            if isMonthlyAutoRenewOn {
                if let msg = lastMessage {
                    if isStatusMessage(msg) {
                        lastMessage = "Thank you — guardianship is active."
                    }
                } else {
                    lastMessage = "Thank you — guardianship is active."
                }
            } else {
                // Canceled but still active until period end.
                if let msg = lastMessage {
                    if isStatusMessage(msg) {
                        lastMessage = "Auto‑renew is off. Guardianship remains active until the end of the current billing period."
                    }
                } else {
                    lastMessage = "Auto‑renew is off. Guardianship remains active until the end of the current billing period."
                }
            }
        } else {
            // If the user is not a guardian anymore, clear stale status messaging.
            if let msg = lastMessage, isStatusMessage(msg) {
                lastMessage = nil
            }
        }
    }

    private func requireVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let signed):
            return signed
        case .unverified:
            throw NSError(
                domain: "SupportStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unverified StoreKit transaction."]
            )
        }
    }
}

private extension Product.SubscriptionInfo.RenewalState {
    var sortOrder: Int {
        // Prefer active-like states first.
        switch self {
        case .subscribed: return 0
        case .inGracePeriod: return 1
        case .inBillingRetryPeriod: return 2
        case .revoked: return 3
        case .expired: return 4
        default: return 99
        }
    }
}

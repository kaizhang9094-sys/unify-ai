import SwiftUI
import PhotosUI

struct RoomView: View {
    @Binding var companionName: String
    @Binding var userName: String

    @EnvironmentObject private var services: AppServices

    let onResetOnboarding: () -> Void

    @AppStorage("companionAvatarThumbFilename") private var avatarThumbFilename: String = ""
    @AppStorage("companionAvatarFullFilename") private var avatarFullFilename: String = ""
    @AppStorage("companionBackgroundThumbFilename") private var bgThumbFilename: String = ""
    @AppStorage("companionBackgroundFullFilename") private var bgFullFilename: String = ""

    @State private var avatarThumbUIImage: UIImage? = nil
    @State private var avatarFullUIImage: UIImage? = nil
    @State private var bgFullUIImage: UIImage? = nil

    @State private var showAvatarViewer: Bool = false
    @State private var showAvatarEditDialog: Bool = false
    @State private var showAvatarPicker: Bool = false
    @State private var pickedAvatarItem: PhotosPickerItem? = nil

    @State private var showOptions: Bool = false
    @State private var showComposer: Bool = true
    @State private var showResetConfirm: Bool = false

    /// Persisted UI mode; when the key is absent (fresh install), defaults to Secretary per product default.
    @AppStorage("Anum.room.isSecretaryMode") private var isSecretaryMode = true
    @State private var secretaryRoute: SecretaryWorkspaceView.Route = .dashboard

    @State private var didBootstrapRuntimeMode: Bool = false

    private var avatarDisplayImage: Image {
        if let image = avatarThumbUIImage {
            return Image(uiImage: image)
        }
        return Image("default_avatar")
    }

    private var backgroundDisplayImage: Image {
        if let image = bgFullUIImage {
            return Image(uiImage: image)
        }
        return Image("default_background")
    }

    private var companionScreen: some View {
        ZStack {
            RoomShellView(
                companionName: companionName,
                avatarImage: avatarDisplayImage,
                backgroundImage: backgroundDisplayImage,
                onAvatarTap: handleAvatarTap,
                onAvatarLongPress: handleAvatarLongPress,
                showOptionsButton: true,
                isResponding: services.chat.isAnyBusy,
                isSecretaryMode: isSecretaryMode,
                onToggleSecretaryMode: handleSecretaryToggle,
                onOptions: handleOptionsTap
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatView(
                companionName: companionName,
                userName: userName,
                showComposer: showComposer,
                isSecretaryMode: false,
                onOpenSecretaryWorkspace: handleOpenSecretaryWorkspace
            )
        }
    }

    private var secretaryScreen: some View {
        SecretaryWorkspaceView(
            initialRoute: secretaryRoute,
            onReturnToCompanion: {
                enterCompanionMode()
            }
        )
        .environmentObject(services)
        .transition(.opacity)
    }

    var body: some View {
        ZStack {
            if isSecretaryMode {
                secretaryScreen
            } else {
                companionScreen
            }
        }
        .animation(.easeInOut(duration: 0.20), value: isSecretaryMode)
        .onAppear {
            loadAvatarFromDiskIfAny()
            loadBackgroundFromDiskIfAny()
            bootstrapRuntimeModeIfNeeded()
        }
        .onChange(of: avatarThumbFilename) { _, _ in
            if avatarThumbFilename.isEmpty {
                avatarThumbUIImage = nil
            } else {
                avatarThumbUIImage = loadImage(named: avatarThumbFilename)
            }
        }
        .onChange(of: avatarFullFilename) { _, _ in
            if avatarFullFilename.isEmpty {
                avatarFullUIImage = nil
            } else {
                avatarFullUIImage = loadImage(named: avatarFullFilename)
            }
        }
        .onChange(of: bgFullFilename) { _, _ in
            if bgFullFilename.isEmpty {
                bgFullUIImage = nil
            } else {
                bgFullUIImage = loadImage(named: bgFullFilename)
            }
        }
        .sheet(isPresented: $showOptions) {
            RoomOptionsSheet(
                onResetOnboarding: {
                    showResetConfirm = true
                }
            )
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
        .alert("Reset onboarding?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                onResetOnboarding()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will bring back the intro pages and clear the saved names on this device.")
        }
        .photosPicker(isPresented: $showAvatarPicker, selection: $pickedAvatarItem, matching: .images)
        .onChange(of: pickedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePickedAvatar(newItem) }
        }
        .confirmationDialog("Avatar", isPresented: $showAvatarEditDialog, titleVisibility: .visible) {
            if avatarFullUIImage != nil {
                Button("View Photo") { showAvatarViewer = true }
            }
            Button("Choose Photo") { showAvatarPicker = true }
            if avatarFullUIImage != nil {
                Button("Remove Photo", role: .destructive) { removeAvatar() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your avatar stays on this device.")
        }
        .fullScreenCover(isPresented: $showAvatarViewer) {
            if let full = avatarFullUIImage {
                AvatarViewer(
                    image: full,
                    title: companionName,
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
    }

    // MARK: - Mode switching / runtime ownership

    private func bootstrapRuntimeModeIfNeeded() {
        guard !didBootstrapRuntimeMode else { return }
        didBootstrapRuntimeMode = true

        if isSecretaryMode {
            services.chat.enterSecretaryRuntimeMode()
        } else {
            services.chat.enterCompanionRuntimeMode(afterSecretary: false)
        }
    }

    private func enterSecretaryMode(route: SecretaryWorkspaceView.Route = .dashboard) {
        secretaryRoute = route

        // Companion -> Secretary.
        // This should invalidate companion runtime state and start secretary-side kernel warmup
        // inside ChatViewModel.enterSecretaryRuntimeMode().
        services.chat.enterSecretaryRuntimeMode()

        withAnimation(.easeInOut(duration: 0.18)) {
            isSecretaryMode = true
        }
    }

    private func enterCompanionMode() {
        // Secretary -> Companion.
        // This should invalidate secretary runtime state and start companion scaffold/prefix warmup
        // inside ChatViewModel.enterCompanionRuntimeMode().
        services.chat.enterCompanionRuntimeMode(afterSecretary: true)

        withAnimation(.easeInOut(duration: 0.18)) {
            isSecretaryMode = false
            secretaryRoute = .dashboard
        }
    }

    private func handleOpenSecretaryWorkspace(_ route: SecretaryWorkspaceView.Route) {
        enterSecretaryMode(route: route)
    }

    private func handleSecretaryToggle() {
        if isSecretaryMode {
            enterCompanionMode()
        } else {
            enterSecretaryMode(route: .dashboard)
        }
    }

    // MARK: - UI actions

    private func handleAvatarTap() {
        if avatarFullUIImage != nil {
            showAvatarViewer = true
        } else {
            showAvatarPicker = true
        }
    }

    private func handleAvatarLongPress() {
        showAvatarEditDialog = true
    }

    private func handleOptionsTap() {
        showOptions = true
    }

    // MARK: - Disk IO

    private func avatarDirURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Avatars", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func loadAvatarFromDiskIfAny() {
        if !avatarThumbFilename.isEmpty {
            avatarThumbUIImage = loadImage(named: avatarThumbFilename)
        }
        if !avatarFullFilename.isEmpty {
            avatarFullUIImage = loadImage(named: avatarFullFilename)
        }
    }

    private func loadBackgroundFromDiskIfAny() {
        if !bgFullFilename.isEmpty {
            bgFullUIImage = loadImage(named: bgFullFilename)
        } else {
            bgFullUIImage = nil
        }
    }

    private func loadImage(named filename: String) -> UIImage? {
        let url = avatarDirURL().appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func saveJPEG(_ image: UIImage, filename: String, quality: CGFloat) {
        let url = avatarDirURL().appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: quality) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func removeAvatar() {
        if !avatarThumbFilename.isEmpty {
            let url = avatarDirURL().appendingPathComponent(avatarThumbFilename)
            try? FileManager.default.removeItem(at: url)
        }

        if !avatarFullFilename.isEmpty {
            let url = avatarDirURL().appendingPathComponent(avatarFullFilename)
            try? FileManager.default.removeItem(at: url)
        }

        avatarThumbFilename = ""
        avatarFullFilename = ""
        avatarThumbUIImage = nil
        avatarFullUIImage = nil
    }

    // MARK: - Image processing

    private func centerCropSquare(_ image: UIImage) -> UIImage {
        let size = image.size
        let side = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )
        let rect = CGRect(
            origin: origin,
            size: CGSize(width: side, height: side)
        ).integral

        guard let cg = image.cgImage?.cropping(to: rect) else {
            return image
        }

        return UIImage(
            cgImage: cg,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }

    private func resizeToSquare(_ image: UIImage, side: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side)
        )

        return renderer.image { _ in
            image.draw(
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: side,
                    height: side
                )
            )
        }
    }

    private func resizeLongestEdge(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)

        guard longest > maxEdge, longest > 0 else {
            return image
        }

        let scale = maxEdge / longest
        let newSize = CGSize(
            width: w * scale,
            height: h * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    @MainActor
    private func handlePickedAvatar(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else {
            return
        }

        let full = resizeLongestEdge(ui, maxEdge: 2048)
        let square = centerCropSquare(ui)
        let thumb = resizeToSquare(square, side: 256)

        let thumbName = "companion_avatar_thumb.jpg"
        let fullName = "companion_avatar_full.jpg"

        saveJPEG(thumb, filename: thumbName, quality: 0.82)
        saveJPEG(full, filename: fullName, quality: 0.85)

        avatarThumbFilename = thumbName
        avatarFullFilename = fullName

        avatarThumbUIImage = thumb
        avatarFullUIImage = full

        pickedAvatarItem = nil
    }

    // MARK: - Viewer

    private struct AvatarViewer: View {
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
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundStyle(.white)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") {
                            showEdit = true
                        }
                        .foregroundStyle(.white)
                    }
                }
                .confirmationDialog("Avatar", isPresented: $showEdit, titleVisibility: .visible) {
                    Button("Change Photo") {
                        onChangePhoto()
                    }

                    Button("Remove Photo", role: .destructive) {
                        onRemovePhoto()
                    }

                    Button("Cancel", role: .cancel) {}
                }
            }
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
}

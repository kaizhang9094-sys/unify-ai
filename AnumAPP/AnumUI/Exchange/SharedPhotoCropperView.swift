import SwiftUI
import PhotosUI
import UIKit

// MARK: - Shared photo cropper (Companion Avatar & Presence editor; reused in Secretary)

/// Interactive pinch/drag crop UI aligned to real Unify image display targets (not full-screen generic boxes).
struct SharedPhotoCropperView: View {
    /// Display-target presets — aspect ratio, editor cap size, mask, and initial scale match final `scaledToFill` / `scaledToFit` usage.
    enum Preset: Equatable {
        /// Profile shell header orb (`ProfileShellLayout.heroAvatarDiameter`, circle, `scaledToFill`).
        case profileAvatar
        /// Profile media strip Main / gallery (`UnifyProfileMediaStripMetrics`, rounded rect, `scaledToFill`).
        case profileMediaStrip
        /// Dashboard “Suggested for you” swipe card (`forYouCardHeight` 500pt shell, `scaledToFill`).
        case discoveryForYouHero
        /// Thread pulled-surface hero (`aspectRatio(335/468)`, `scaledToFill`).
        case threadPulledHero
        /// Room / background or other custom targets.
        case custom(
            aspectRatio: CGFloat,
            maxCropWidth: CGFloat,
            maxCropHeight: CGFloat,
            maskCornerRadius: CGFloat,
            initialScale: InitialScaleBehavior,
            maskStyle: MaskStyle
        )

        fileprivate var spec: CropPresetSpec {
            switch self {
            case .profileAvatar:
                return CropPresetSpec(
                    aspectRatio: 1,
                    maxCropWidth: 320,
                    maxCropHeight: 320,
                    maskCornerRadius: 0,
                    initialScale: .aspectFill,
                    maskStyle: .circle
                )
            case .profileMediaStrip:
                let w = UnifyProfileMediaStripMetrics.slotWidth
                let h = UnifyProfileMediaStripMetrics.slotHeight
                return CropPresetSpec(
                    aspectRatio: w / h,
                    maxCropWidth: 320,
                    maxCropHeight: 340,
                    maskCornerRadius: UnifyProfileMediaStripMetrics.slotCornerRadius,
                    initialScale: .aspectFill,
                    maskStyle: .roundedRectangle
                )
            case .discoveryForYouHero:
                // SecretaryDashboardView `forYouTallGlassCardShell`: full width × 500pt, corner 24, scaledToFill.
                let referenceWidth: CGFloat = 343
                let referenceHeight: CGFloat = 500
                return CropPresetSpec(
                    aspectRatio: referenceWidth / referenceHeight,
                    maxCropWidth: 340,
                    maxCropHeight: 460,
                    maskCornerRadius: 24,
                    initialScale: .aspectFill,
                    maskStyle: .roundedRectangle
                )
            case .threadPulledHero:
                return CropPresetSpec(
                    aspectRatio: 335.0 / 468.0,
                    maxCropWidth: 340,
                    maxCropHeight: 475,
                    maskCornerRadius: 24,
                    initialScale: .aspectFill,
                    maskStyle: .roundedRectangle
                )
            case .custom(let aspectRatio, let maxCropWidth, let maxCropHeight, let maskCornerRadius, let initialScale, let maskStyle):
                return CropPresetSpec(
                    aspectRatio: aspectRatio,
                    maxCropWidth: maxCropWidth,
                    maxCropHeight: maxCropHeight,
                    maskCornerRadius: maskCornerRadius,
                    initialScale: initialScale,
                    maskStyle: maskStyle
                )
            }
        }
    }

    enum InitialScaleBehavior: Equatable {
        /// Match UI that uses `scaledToFill` — crop window fully covered on load (no letterboxing).
        case aspectFill
        /// Match UI that uses `scaledToFit` — entire image visible inside the window on load.
        case aspectFit
    }

    enum MaskStyle: Equatable {
        case roundedRectangle
        case circle
    }

    fileprivate struct CropPresetSpec: Equatable {
        let aspectRatio: CGFloat
        let maxCropWidth: CGFloat
        let maxCropHeight: CGFloat
        let maskCornerRadius: CGFloat
        let initialScale: InitialScaleBehavior
        let maskStyle: MaskStyle
    }

    let sourceImage: UIImage
    let preset: Preset
    let title: String
    let onCancel: () -> Void
    let onUse: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var userScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var editorContainerSize: CGSize = .zero

    private var presetSpec: CropPresetSpec { preset.spec }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let container = proxy.size
                let cropSize = cropWindowSize(in: container)
                let base = baseScale(for: cropSize)
                let rawDrawScale = base * userScale
                let drawScale: CGFloat = (rawDrawScale.isFinite && rawDrawScale > 0) ? rawDrawScale : 1

                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: sourceImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(
                            width: sourceImage.size.width * drawScale,
                            height: sourceImage.size.height * drawScale
                        )
                        .position(
                            x: container.width / 2 + offset.width,
                            y: container.height / 2 + offset.height
                        )
                        .gesture(magnifyGesture(cropSize: cropSize, baseScale: base))
                        .gesture(panGesture(cropSize: cropSize, baseScale: base))

                    cropMaskOverlay(cropSize: cropSize, container: container)
                    cropBorder(cropSize: cropSize)

                    VStack {
                        Spacer()
                        Text("Pinch to zoom • Drag to reposition")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.bottom, 18)
                    }
                    .allowsHitTesting(false)
                }
                .onAppear {
                    editorContainerSize = container
                }
                .onChange(of: container) { _, newSize in
                    editorContainerSize = newSize
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use") {
                        if let cropped = renderCroppedImage() {
                            onUse(cropped)
                        }
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            userScale = 1
                            lastScale = 1
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .tint(.white)
    }

    @ViewBuilder
    private func cropBorder(cropSize: CGSize) -> some View {
        switch presetSpec.maskStyle {
        case .circle:
            Circle()
                .stroke(.white.opacity(0.85), lineWidth: 1)
                .frame(width: cropSize.width, height: cropSize.height)
                .allowsHitTesting(false)
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: presetSpec.maskCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.85), lineWidth: 1)
                .frame(width: cropSize.width, height: cropSize.height)
                .allowsHitTesting(false)
        }
    }

    private func safePositive(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return fallback }
        return value
    }

    private func cropWindowSize(in container: CGSize) -> CGSize {
        let spec = presetSpec
        let cw = safePositive(container.width, fallback: UIScreen.main.bounds.width)
        let ch = safePositive(container.height, fallback: UIScreen.main.bounds.height)

        let horizontalMargin: CGFloat = 32
        let verticalChrome: CGFloat = 160
        let containerMaxW = max(1, cw - horizontalMargin)
        let containerMaxH = max(1, ch - verticalChrome)

        let maxW = min(spec.maxCropWidth, containerMaxW)
        let maxH = min(spec.maxCropHeight, containerMaxH)
        let ratio = max(0.2, min(spec.aspectRatio, 2.5))

        var w = maxW
        var h = w / ratio
        if h > maxH {
            h = maxH
            w = h * ratio
        }

        w = safePositive(w, fallback: maxW)
        h = safePositive(h, fallback: maxH)
        return CGSize(width: w, height: h)
    }

    private func aspectFitScale(for cropSize: CGSize) -> CGFloat {
        let iw = safePositive(sourceImage.size.width, fallback: 1)
        let ih = safePositive(sourceImage.size.height, fallback: 1)
        let cw = safePositive(cropSize.width, fallback: 1)
        let ch = safePositive(cropSize.height, fallback: 1)
        let s = min(cw / iw, ch / ih)
        return (s.isFinite && s > 0) ? s : 1
    }

    private func coverScale(for cropSize: CGSize) -> CGFloat {
        let iw = safePositive(sourceImage.size.width, fallback: 1)
        let ih = safePositive(sourceImage.size.height, fallback: 1)
        let cw = safePositive(cropSize.width, fallback: 1)
        let ch = safePositive(cropSize.height, fallback: 1)
        let s = max(cw / iw, ch / ih)
        return (s.isFinite && s > 0) ? s : 1
    }

    private func baseScale(for cropSize: CGSize) -> CGFloat {
        switch presetSpec.initialScale {
        case .aspectFill:
            return coverScale(for: cropSize)
        case .aspectFit:
            return aspectFitScale(for: cropSize)
        }
    }

    private func magnifyGesture(cropSize: CGSize, baseScale: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                let proposed = userScale * delta
                userScale = min(max(proposed, 1), 4)
                lastScale = value
                offset = clamped(offset: offset, cropSize: cropSize, baseScale: baseScale)
            }
            .onEnded { _ in
                lastScale = 1
                offset = clamped(offset: offset, cropSize: cropSize, baseScale: baseScale)
                lastOffset = offset
            }
    }

    private func panGesture(cropSize: CGSize, baseScale: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clamped(offset: proposed, cropSize: cropSize, baseScale: baseScale)
            }
            .onEnded { _ in
                offset = clamped(offset: offset, cropSize: cropSize, baseScale: baseScale)
                lastOffset = offset
            }
    }

    private func clamped(offset: CGSize, cropSize: CGSize, baseScale: CGFloat) -> CGSize {
        let drawScale = baseScale * userScale
        let cover = coverScale(for: cropSize)
        guard drawScale >= cover - 0.001 else {
            return .zero
        }
        let drawnW = sourceImage.size.width * drawScale
        let drawnH = sourceImage.size.height * drawScale
        let maxX = max(0, (drawnW - cropSize.width) / 2)
        let maxY = max(0, (drawnH - cropSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func cropMaskOverlay(cropSize: CGSize, container: CGSize) -> some View {
        let rect = CGRect(
            x: (container.width - cropSize.width) / 2,
            y: (container.height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        )
        let corner = presetSpec.maskCornerRadius

        return GeometryReader { _ in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: container))
                switch presetSpec.maskStyle {
                case .circle:
                    path.addEllipse(in: rect)
                case .roundedRectangle:
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner))
                }
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
        }
    }

    private func renderCroppedImage() -> UIImage? {
        let container = editorContainerSize.width > 1 && editorContainerSize.height > 1
            ? editorContainerSize
            : UIScreen.main.bounds.size
        let cropSize = cropWindowSize(in: container)
        let base = baseScale(for: cropSize)
        let drawScale = base * userScale

        let containerCenter = CGPoint(x: container.width / 2, y: container.height / 2)
        let imageSizeInPoints = CGSize(
            width: sourceImage.size.width * drawScale,
            height: sourceImage.size.height * drawScale
        )
        let imageOrigin = CGPoint(
            x: containerCenter.x - imageSizeInPoints.width / 2 + offset.width,
            y: containerCenter.y - imageSizeInPoints.height / 2 + offset.height
        )

        let cropOriginInPoints = CGPoint(
            x: (container.width - cropSize.width) / 2,
            y: (container.height - cropSize.height) / 2
        )

        let x = (cropOriginInPoints.x - imageOrigin.x) / drawScale
        let y = (cropOriginInPoints.y - imageOrigin.y) / drawScale
        let w = cropSize.width / drawScale
        let h = cropSize.height / drawScale

        let rect = CGRect(x: x, y: y, width: w, height: h).integral

        guard let cg = sourceImage.cgImage else { return nil }
        let bounded = rect.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let croppedCG = cg.cropping(to: bounded) else { return nil }
        return UIImage(cgImage: croppedCG, scale: sourceImage.scale, orientation: sourceImage.imageOrientation)
    }
}

// MARK: - Picker → crop presentation helpers

enum SharedPhotoEditFlow {
    @MainActor
    static func loadUIImage(from item: PhotosPickerItem, context: String = "photoPicker") async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return nil
        }
        #if DEBUG
        let byteCount = data.count
        #endif
        guard let image = UIImage(data: data) else {
            #if DEBUG
            print("[ImageUploadPrep] context=\(context) stage=pickerDecodeFailed originalBytes=\(data.count)")
            #endif
            return nil
        }
        #if DEBUG
        let pixelW = image.cgImage?.width ?? 0
        let pixelH = image.cgImage?.height ?? 0
        print(
            "[ImageUploadPrep] context=\(context) stage=pickerLoaded " +
            "originalBytes=\(byteCount) points=\(Int(image.size.width))x\(Int(image.size.height)) " +
            "pixels=\(pixelW)x\(pixelH)"
        )
        #endif
        return image
    }
}

extension View {
    /// Presents the shared full-screen crop editor used in Companion Avatar & Presence.
    func sharedPhotoCropperCover(
        isPresented: Binding<Bool>,
        sourceImage: UIImage?,
        preset: SharedPhotoCropperView.Preset,
        title: String,
        onCancel: @escaping () -> Void,
        onUse: @escaping (UIImage) -> Void
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            if let sourceImage {
                SharedPhotoCropperView(
                    sourceImage: sourceImage,
                    preset: preset,
                    title: title,
                    onCancel: onCancel,
                    onUse: onUse
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }
}

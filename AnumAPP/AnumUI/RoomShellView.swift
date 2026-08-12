import SwiftUI
import UIKit

struct RoomShellView: View {
    let companionName: String
    var avatarImage: Image? = nil
    var backgroundImage: Image? = nil
    var onAvatarTap: (() -> Void)? = nil
    var onAvatarLongPress: (() -> Void)? = nil
    var showOptionsButton: Bool = true
    var isResponding: Bool = false
    var isSecretaryMode: Bool = false
    var onToggleSecretaryMode: (() -> Void)? = nil
    let onOptions: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if let backgroundImage {
                    backgroundImage
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .saturation(1.08)
                        .overlay(.black.opacity(0.10))
                }

                LinearGradient(
                    colors: [Color.black, Color(.systemGray6).opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .clear, location: 0.45),
                            .init(color: .black, location: 0.66),
                            .init(color: .black, location: 1.00)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                VStack(spacing: 0) {
                    Spacer()
                    Spacer(minLength: 160)
                    Spacer()
                }

                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, max(0, proxy.safeAreaInsets.top - 40))
                    .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var topBar: some View {
        ZStack {
            Text(centerTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 120)

            HStack(spacing: 10) {
                avatarChip

                Spacer()

                modeSwitchButton

                if showOptionsButton {
                    Button(action: onOptions) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Room Options")
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
            }
        }
        .frame(height: 44)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
    }

    private var centerTitle: String {
        isSecretaryMode ? "Secretary" : companionName
    }

    /// Same capsule geometry and chrome as `SecretaryWorkspaceView.modeSwitchButton` (destination: briefcase → Secretary, bubbles → Chat).
    private var modeSwitchButton: some View {
        Button {
            onToggleSecretaryMode?()
        } label: {
            Image(systemName: isSecretaryMode ? "bubble.left.and.bubble.right.fill" : "briefcase.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.darkSurface.opacity(0.92))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.75), lineWidth: 1)
                )
                .shadow(color: SecretaryTheme.darkShadow.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(modeSwitchAccessibilityLabel)
    }

    private var modeSwitchAccessibilityLabel: String {
        isSecretaryMode ? "Switch to Chat" : "Switch to Secretary"
    }

    private var avatarChip: some View {
        Button {
            onAvatarTap?()
        } label: {
            Group {
                if let avatarImage {
                    avatarImage
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(width: 40, height: 40)
            .background(.white.opacity(0.12))
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            .overlay(
                Group {
                    if avatarImage != nil {
                        RainbowRingOverlay(isResponding: isResponding)
                            .frame(width: 40, height: 40)
                            .allowsHitTesting(false)
                    }
                }
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            onAvatarLongPress?()
        }
        .accessibilityLabel("Companion Avatar")
    }
}

private struct RainbowRingOverlay: UIViewRepresentable {
    let isResponding: Bool

    func makeUIView(context: Context) -> RainbowRingView {
        let v = RainbowRingView()
        v.setResponding(isResponding)
        return v
    }

    func updateUIView(_ uiView: RainbowRingView, context: Context) {
        uiView.setResponding(isResponding)
    }
}

private final class RainbowRingView: UIView {
    private let gradient = CAGradientLayer()
    private let ringMask = CAShapeLayer()
    private let lineWidth: CGFloat = 3.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        gradient.type = .conic
        gradient.colors = [
            UIColor.systemRed.cgColor,
            UIColor.systemOrange.cgColor,
            UIColor.systemYellow.cgColor,
            UIColor.systemGreen.cgColor,
            UIColor.systemCyan.cgColor,
            UIColor.systemBlue.cgColor,
            UIColor.systemPurple.cgColor,
            UIColor.systemRed.cgColor
        ]
        gradient.locations = [0.0, 0.16, 0.32, 0.48, 0.64, 0.80, 0.92, 1.0] as [NSNumber]
        layer.addSublayer(gradient)

        ringMask.fillColor = UIColor.clear.cgColor
        ringMask.strokeColor = UIColor.white.cgColor
        ringMask.lineWidth = lineWidth
        ringMask.lineCap = .round
        ringMask.strokeStart = 0.0
        ringMask.strokeEnd = 1.0
        gradient.mask = ringMask

        startSpinIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.0)

        let inset = lineWidth / 2
        ringMask.frame = bounds
        ringMask.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
    }

    func setResponding(_ responding: Bool) {
        gradient.opacity = responding ? 1.00 : 0.55
    }

    private func startSpinIfNeeded() {
        if gradient.animation(forKey: "spin") != nil { return }

        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0
        anim.toValue = Double.pi * 2
        anim.duration = 6.4
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        gradient.add(anim, forKey: "spin")
    }
}

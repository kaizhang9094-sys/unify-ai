import SwiftUI

private struct OnboardingOverlayBackground: View {
    let imageName: String

    var body: some View {
        ZStack {
            // Fully opaque base so adjacent pages can never bleed through during swipe.
            Color.black
                .ignoresSafeArea()

            GeometryReader { geo in
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

        }
        // Force SwiftUI to treat this as a single opaque layer during interactive paging.
        .compositingGroup()
    }
}

struct BridgeToRoomPage: View {
    let companionName: String
    @Binding var overlayVisible: Bool
    @Binding var showValidationHint: Bool
    let onEnter: () -> Void

    var body: some View {
        ZStack {
            // The real room shell behind the overlay
            RoomShellView(
                companionName: companionName,
                showOptionsButton: false,
                onOptions: {}
            )

            if overlayVisible {
                GeometryReader { geo in
                    ZStack {
                        OnboardingOverlayBackground(imageName: "onboarding_last")

                        VStack(spacing: 14) {
                            // Upper-middle placement for the copy
                            Spacer().frame(height: geo.safeAreaInsets.top + geo.size.height * 0.12)

                            Text("Your private space awaits")
                                .font(.system(size: 30, weight: .semibold))
                                .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)

                            Text("For thoughts, memories, and tomorrow.")
                                .font(.system(size: 16))
                                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 5)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 26)

                            if showValidationHint {
                                Text("Please set a companion name on the previous page.")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.yellow.opacity(0.9))
                                    .padding(.top, 4)
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom) {
                            Button {
                                onEnter()
                            } label: {
                                Text("Enter the Space")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.95, green: 0.62, blue: 0.35),
                                                Color(red: 0.88, green: 0.52, blue: 0.30)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            // Extra lift so the CTA aligns with other pages above the dots
                            .padding(.bottom, 54)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

// NOTE: Legacy onboarding pages (disabled).
// If you see compile errors referencing types from this file, it means something still depends on them.
// In that case, remove the call sites first, then re-disable/delete this file.
#if false
private struct OnboardingBackground: View {
    let imageName: String?

    var body: some View {
        ZStack {
            if let name = imageName {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 8)
            } else {
                LinearGradient(
                    colors: [Color.black, Color(.systemGray6).opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            // Readability overlay (keeps text legible across bright images)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.05),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft vignette to calm edges + protect cropping
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()
                .mask(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.clear, Color.black]),
                        center: .center,
                        startRadius: 120,
                        endRadius: 520
                    )
                )
        }
    }
}

struct OnboardingInfoPage: View {
    let title: String
    let message: String
    let backgroundImageName: String?

    init(title: String, message: String, backgroundImageName: String? = nil) {
        self.title = title
        self.message = message
        self.backgroundImageName = backgroundImageName
    }

    var body: some View {
        ZStack {
            OnboardingBackground(imageName: backgroundImageName)

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 17, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 28)

                Spacer().frame(height: 120)
            }
            .padding(.top, 90)
        }
    }
}

struct CompanionSetupPage: View {
    @Binding var companionName: String
    @Binding var companionGender: GenderChoice

    @State private var customGenderText: String = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(.systemGray6).opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Name your companion")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                TextField("Companion name", text: $companionName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Companion identity (optional)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    Picker("Companion identity", selection: bindingForPresetGender()) {
                        Text("Woman").tag("woman")
                        Text("Man").tag("man")
                        Text("Non-binary").tag("nonbinary")
                        Text("Custom").tag("custom")
                        Text("Prefer not to say").tag("na")
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    if isCustomSelected {
                        TextField("Custom identity", text: $customGenderText)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .onChange(of: customGenderText) { _, newValue in
                                companionGender = .custom(newValue)
                            }
                    }
                }

                Spacer()
            }
            .padding(.top, 80)
            .padding(.horizontal, 18)
        }
        .onAppear {
            if case .custom(let s) = companionGender {
                customGenderText = s
            }
        }
    }

    private var isCustomSelected: Bool {
        if case .custom = companionGender { return true }
        return false
    }

    private func bindingForPresetGender() -> Binding<String> {
        Binding<String>(
            get: {
                switch companionGender {
                case .woman: return "woman"
                case .man: return "man"
                case .nonBinary: return "nonbinary"
                case .preferNotToSay: return "na"
                case .custom: return "custom"
                }
            },
            set: { newValue in
                switch newValue {
                case "woman": companionGender = .woman
                case "man": companionGender = .man
                case "nonbinary": companionGender = .nonBinary
                case "na": companionGender = .preferNotToSay
                case "custom":
                    companionGender = .custom(customGenderText)
                default:
                    companionGender = .preferNotToSay
                }
            }
        )
    }
}

struct UserSetupPage: View {
    @Binding var userName: String
    @Binding var userGender: GenderChoice

    @State private var customGenderText: String = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(.systemGray6).opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("What should I call you?")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                TextField("Your name (optional)", text: $userName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your identity (optional)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    Picker("Your identity", selection: bindingForPresetGender()) {
                        Text("Woman").tag("woman")
                        Text("Man").tag("man")
                        Text("Non-binary").tag("nonbinary")
                        Text("Custom").tag("custom")
                        Text("Prefer not to say").tag("na")
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    if isCustomSelected {
                        TextField("Custom identity", text: $customGenderText)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .onChange(of: customGenderText) { _, newValue in
                                userGender = .custom(newValue)
                            }
                    }
                }

                Spacer()
            }
            .padding(.top, 80)
            .padding(.horizontal, 18)
        }
        .onAppear {
            if case .custom(let s) = userGender {
                customGenderText = s
            }
        }
    }

    private var isCustomSelected: Bool {
        if case .custom = userGender { return true }
        return false
    }

    private func bindingForPresetGender() -> Binding<String> {
        Binding<String>(
            get: {
                switch userGender {
                case .woman: return "woman"
                case .man: return "man"
                case .nonBinary: return "nonbinary"
                case .preferNotToSay: return "na"
                case .custom: return "custom"
                }
            },
            set: { newValue in
                switch newValue {
                case "woman": userGender = .woman
                case "man": userGender = .man
                case "nonbinary": userGender = .nonBinary
                case "na": userGender = .preferNotToSay
                case "custom":
                    userGender = .custom(customGenderText)
                default:
                    userGender = .preferNotToSay
                }
            }
        )
    }
}
#endif

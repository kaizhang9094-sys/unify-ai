import SwiftUI

/// Row model for `UnifyIntentLauncherSheet` (data only; no services).
struct UnifyIntentLauncherItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let subtitle: String?

    init(id: String? = nil, title: String, systemImage: String, subtitle: String? = nil) {
        self.id = id ?? "\(title)-\(systemImage)"
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
    }
}

/// Dark premium intent picker sheet (plain buttons; parent handles selection).
struct UnifyIntentLauncherSheet: View {
    @Binding var isPresented: Bool
    var title: String = "Intents"
    var items: [UnifyIntentLauncherItem]
    var onPick: (UnifyIntentLauncherItem) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            onPick(item)
                            isPresented = false
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(SecretaryTheme.darkOrange)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(SecretaryTheme.darkOrangeSoft.opacity(0.45))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(SecretaryTheme.darkMutedText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(SecretaryTheme.darkSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(SecretaryTheme.darkStroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Close")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.55))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(SecretaryTheme.darkStroke.opacity(0.85), lineWidth: 1)
                            )
                            .frame(minWidth: 88, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(SecretaryTheme.darkBackgroundElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(SecretaryTheme.darkOrange)
    }
}

import SwiftUI
import AnumCore

/// Reusable public-profile inspection sheet (For You rail + social discovery search).
struct PublicProfileDetailSheet<Toolbar: View>: View {
    let item: ExchangeModels.ForYouItem
    let imageURLs: [String]
    let subtitle: String?
    let detailLines: [String]
    let detailSections: [ExchangeDisplaySection]?
    let onClose: () -> Void
    let onOpenGallery: ((SecretaryImageGalleryPresentation) -> Void)?
    @ViewBuilder let toolbarTrailing: () -> Toolbar

    init(
        item: ExchangeModels.ForYouItem,
        imageURLs: [String],
        subtitle: String?,
        detailLines: [String],
        detailSections: [ExchangeDisplaySection]? = nil,
        onClose: @escaping () -> Void,
        onOpenGallery: ((SecretaryImageGalleryPresentation) -> Void)? = nil,
        @ViewBuilder toolbarTrailing: @escaping () -> Toolbar
    ) {
        self.item = item
        self.imageURLs = imageURLs
        self.subtitle = subtitle
        self.detailLines = detailLines
        self.detailSections = detailSections
        self.onClose = onClose
        self.onOpenGallery = onOpenGallery
        self.toolbarTrailing = toolbarTrailing
    }

    private var sheetDisplayName: String {
        let fromCard = item.displayCard?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromCard.isEmpty { return fromCard }
        return item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Single intro under the title: caller-provided subtitle, else legacy headline.
    private var sheetIntro: String? {
        if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subtitle
        }
        let headline = item.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return headline.isEmpty ? nil : headline
    }

    var body: some View {
        let heroURL = imageURLs.first.flatMap { URL(string: $0) }
        let sheetNavTitle = sheetDisplayName
        let resolvedNavTitle = sheetNavTitle.isEmpty ? "Profile" : sheetNavTitle
        let groupedSections = detailSections?.filter { !$0.lines.isEmpty } ?? []

        NavigationStack {
            ZStack {
                UnifyIceShellBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heroImageBlock(heroURL: heroURL)

                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    if item.publicSupporterPresentation?.showsGuardianCrown == true {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(SecretaryTheme.darkOrange)
                                            .accessibilityLabel("Guardian supporter")
                                    }
                                    Text(sheetDisplayName)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                                }

                                if let intro = sheetIntro {
                                    Text(intro)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if imageURLs.count > 1, let onOpenGallery {
                                Button {
                                    onOpenGallery(
                                        SecretaryImageGalleryPresentation(
                                            imageURLs: imageURLs,
                                            initialIndex: 0,
                                            title: item.displayName,
                                            caption: item.headline
                                        )
                                    )
                                } label: {
                                    HStack(spacing: 8) {
                                        Text("More photos")
                                            .font(.system(size: 14, weight: .semibold))
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundStyle(SecretaryTheme.darkOrange)
                                    .multilineTextAlignment(.trailing)
                                }
                                .buttonStyle(.plain)
                                .frame(alignment: .topTrailing)
                            }
                        }

                        if !groupedSections.isEmpty {
                            ForEach(Array(groupedSections.enumerated()), id: \.offset) { _, section in
                                groupedDetailSectionCard(section: section)
                            }
                        } else if !detailLines.isEmpty {
                            UnifyDarkCard(cornerRadius: SecretaryTheme.Layout.radiusLarge, strokeOpacity: 1.0) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Info")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    ForEach(Array(detailLines.prefix(12).enumerated()), id: \.offset) { _, line in
                                        infoDetailRow(line: line)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(SecretaryTheme.Layout.cardInteriorPadding)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(resolvedNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    toolbarTrailing()
                }
            }
        }
        #if DEBUG
        .onAppear {
            guard item.publicSupporterPresentation?.showsGuardianCrown == true else { return }
            GuardianCrownDebugLog.log(
                "Render",
                "surface=publicProfileDetail nodeID=\(item.nodeID) profileID=\(item.publicProfileID ?? "nil") " +
                "presentation=guardian/crown"
            )
        }
        #endif
    }

    @ViewBuilder
    private func heroImageBlock(heroURL: URL?) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let heroURL {
                    AsyncImage(url: heroURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty, .failure:
                            profilePlaceholderGradient
                        @unknown default:
                            profilePlaceholderGradient
                        }
                    }
                } else {
                    profilePlaceholderGradient
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SecretaryTheme.darkStroke.opacity(0.65), lineWidth: 1)
        )
    }

    private var profilePlaceholderGradient: some View {
        LinearGradient(
            colors: [
                SecretaryTheme.darkSurfaceStrong.opacity(0.95),
                SecretaryTheme.darkOrange.opacity(0.18),
                SecretaryTheme.darkBackground.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func groupedDetailSectionCard(section: ExchangeDisplaySection) -> some View {
        UnifyDarkCard(cornerRadius: SecretaryTheme.Layout.radiusLarge, strokeOpacity: 1.0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(section.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(section.lines.prefix(12).enumerated()), id: \.offset) { _, line in
                    infoDetailRow(line: line.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SecretaryTheme.Layout.cardInteriorPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func infoDetailRow(line: String) -> some View {
        if let (symbol, body) = infoLineIconAndBody(line) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkOrange)
                    .frame(width: 22, alignment: .center)
                Text(body)
                    .font(.system(size: 14.5))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(line)
                .font(.system(size: 14.5))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoLineIconAndBody(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIdx = trimmed.firstIndex(of: ":") else { return nil }
        let head = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty, !value.isEmpty else { return nil }

        let symbol: String? = {
            switch head.lowercased() {
            case "region", "match":
                return "map"
            case "open to":
                return "arrow.left.arrow.right"
            case "roles", "interests":
                return "person.3"
            case "looking for":
                return "text.magnifyingglass"
            case "about":
                return "text.alignleft"
            case "offer", "offers":
                return "tag.fill"
            case "shared themes":
                return "square.grid.2x2"
            default:
                return nil
            }
        }()

        guard let symbol else { return nil }
        return (symbol, value)
    }
}

import Foundation
import SwiftUI
import AnumCore

// MARK: - Stories & chat rows

/// Story-ring style avatar chip (presentation only; `onTap` is a local UI callback).
struct UnifyAvatarStoryItem: View {
    let title: String
    var initials: String = ""
    var showsActivityRing: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            showsActivityRing
                                ? SecretaryTheme.darkOrange
                                : SecretaryTheme.white.opacity(0.16),
                            lineWidth: showsActivityRing ? 2.5 : 1
                        )
                        .frame(width: 58, height: 58)

                    Circle()
                        .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.85))
                        .frame(width: 50, height: 50)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .frame(width: 50, height: 50)
                        }
                        .clipShape(Circle())
                        .overlay {
                            Text(displayInitials)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        }
                }

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
    }

    private var displayInitials: String {
        let t = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(2)).uppercased() }
        let parts = title.split(separator: " ")
        if parts.count >= 2 {
            let a = parts[0].first.map(String.init) ?? ""
            let b = parts[1].first.map(String.init) ?? ""
            return (a + b).uppercased()
        }
        return String(title.prefix(1)).uppercased()
    }
}

/// Inbox / chat list row for dark premium surfaces (`onTap` supplied by parent).
struct UnifyChatRow: View {
    let title: String
    var subtitle: String = ""
    var timestamp: String = ""
    var avatarURL: String? = nil
    var avatarInitials: String = ""
    /// Orange status dot on the avatar (bottom-trailing), reference-style.
    var showsAvatarActivityDot: Bool = false
    /// Numeric unread capsule (dark premium orange, not system red).
    var unreadBadgeCount: Int? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    avatarView
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(SecretaryTheme.darkStroke.opacity(0.9), lineWidth: 1)
                        )

                    if showsAvatarActivityDot {
                        Circle()
                            .fill(SecretaryTheme.darkActivityDot)
                            .frame(width: 11, height: 11)
                            .overlay(
                                Circle()
                                    .stroke(SecretaryTheme.darkBackground, lineWidth: 2)
                            )
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if !timestamp.isEmpty {
                            Text(timestamp)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkMutedText)
                        }
                    }

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let unreadBadgeCount, unreadBadgeCount > 0 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Spacer(minLength: 0)
                        Text(unreadBadgeCount > 99 ? "99+" : "\(unreadBadgeCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SecretaryTheme.darkOrange)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(SecretaryTheme.orangeDeep.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .frame(minWidth: 28, alignment: .trailing)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let raw = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    initialsPlaceholder
                }
            }
        } else {
            initialsPlaceholder
        }
    }

    private var initialsPlaceholder: some View {
        ZStack {
            Circle()
                .fill(SecretaryTheme.darkGlass.opacity(0.85))
                .frame(width: 50, height: 50)
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .frame(width: 50, height: 50)
            Text(rowInitials)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
    }

    private var rowInitials: String {
        let t = avatarInitials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(2)).uppercased() }
        return String(title.prefix(1)).uppercased()
    }
}

// MARK: - Work board (Threads)

/// Normalizes thread list / pin image URL strings for `AsyncImage` (remote + local `file:`), deduped in order.
enum WorkThreadLeadImageURLNormalizer {
    static func normalizedChain(from raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in raw {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            let normalized: String?
            if lower.hasPrefix("javascript:") || lower.hasPrefix("data:") {
                normalized = nil
            } else if lower.hasPrefix("file://") {
                normalized = trimmed
            } else if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                normalized = trimmed
            } else if lower.hasPrefix("//") {
                normalized = "https:\(trimmed)"
            } else if trimmed.contains("://") {
                normalized = trimmed
            } else if let schemeless = httpsPrefixedSchemelessWebURL(trimmed) {
                normalized = schemeless
            } else {
                normalized = nil
            }
            guard let n = normalized else { continue }
            let key = n.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(n)
        }
        return out
    }

    /// Surfaces often store bare host paths (`cdn.example.com/a.jpg`) without a scheme; `AsyncImage` needs an absolute URL.
    private static func httpsPrefixedSchemelessWebURL(_ trimmed: String) -> String? {
        guard !trimmed.contains("://"), !trimmed.contains(" ") else { return nil }
        guard trimmed.contains("."), !trimmed.hasPrefix(".") else { return nil }
        let lower = trimmed.lowercased()
        let suffixOK =
            lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png")
            || lower.hasSuffix(".webp") || lower.hasSuffix(".gif") || lower.hasSuffix(".svg")
            || lower.hasSuffix(".avif")
        guard suffixOK || trimmed.contains("/") || trimmed.contains("?") else { return nil }
        let candidate = "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return candidate
    }
}

#if DEBUG
/// Temporary diagnostics for thread image pipeline (Threads tab). Never log full URLs, paths, queries, or private text.
enum ThreadImagePipelineDebug {
    private static let probeLock = NSLock()
    private static var probedURLIdentityHashes = Set<Int>()
    private static var probeBudgetRemaining = 24

    static func logTab(
        inboxCount: Int,
        projectedRowCount: Int,
        itemsWithNonemptySurfaceCandidates: Int,
        rowsWithNonemptyNormalizedLead: Int
    ) {
        print(
            "[ThreadImage][Tab] inboxCount=\(inboxCount) projectedRowCount=\(projectedRowCount) itemsWithSurfaceCandidates=\(itemsWithNonemptySurfaceCandidates) rowsWithNormalizedLead=\(rowsWithNonemptyNormalizedLead)"
        )
    }

    static func logRow(
        rowID: String,
        rawSurfaceCount: Int,
        rawOrderedUniqueCount: Int,
        normalizedCount: Int,
        selectedSource: String,
        urlValid: Bool,
        hasSurfaceListImageCandidates: Bool,
        hasPrimaryImageURL: Bool,
        hasOfferImageURL: Bool,
        hasCounterpartyImageURL: Bool,
        incomingToRowCandidatesCount: Int,
        afterLeadAvatarNormalizeCount: Int,
        frameW: Int,
        frameH: Int
    ) {
        print(
            "[ThreadImage][Row] rowID=\(rowID) rawSurfaceCount=\(rawSurfaceCount) rawOrderedUniqueCount=\(rawOrderedUniqueCount) normalizedCount=\(normalizedCount) selectedSource=\(selectedSource) urlValid=\(urlValid) hasSurfaceListImageCandidates=\(hasSurfaceListImageCandidates) hasPrimaryImageURL=\(hasPrimaryImageURL) hasOfferImageURL=\(hasOfferImageURL) hasCounterpartyImageURL=\(hasCounterpartyImageURL) incomingToRowCandidates=\(incomingToRowCandidatesCount) afterRowNormalize=\(afterLeadAvatarNormalizeCount) frameW=\(frameW) frameH=\(frameH)"
        )
    }

    static func logPinned(
        slotID: Int,
        threadShort: String,
        rawOrderedUniqueCount: Int,
        normalizedCount: Int,
        selectedSource: String,
        urlValid: Bool,
        frameW: Int,
        frameH: Int
    ) {
        print(
            "[ThreadImage][Pinned] slotID=\(slotID) threadID=\(threadShort) rawOrderedUniqueCount=\(rawOrderedUniqueCount) normalizedCount=\(normalizedCount) selectedSource=\(selectedSource) urlValid=\(urlValid) frameW=\(frameW) frameH=\(frameH)"
        )
    }

    static func logDetail(
        threadID: String,
        rawOrderedUniqueCount: Int,
        normalizedCount: Int,
        selectedSource: String,
        urlValid: Bool,
        frameW: Int,
        frameH: Int
    ) {
        print(
            "[ThreadImage][Detail] threadID=\(threadID) rawCount=\(rawOrderedUniqueCount) normalizedCount=\(normalizedCount) selectedSource=\(selectedSource) urlValid=\(urlValid) frameW=\(frameW) frameH=\(frameH)"
        )
    }

    static func logAsyncPhase(context: String, id: String, phase: String) {
        print("[ThreadImage][AsyncPhase] context=\(context) id=\(id) phase=\(phase)")
    }

    /// `AsyncImage` `.failure` — logs sanitized URL shape + NSError domain/code (redacted description if it may embed a URL).
    static func logAsyncImageFailure(
        context: String,
        probeID: String,
        url: URL,
        error: Error,
        normalizedCandidateCount: Int,
        selectedCandidateIndex: Int,
        phaseLabel: String
    ) {
        let u = Self.sanitizedURLFields(url)
        let e = Self.sanitizedNSErrorFields(error)
        print(
            "[ThreadImage][Failure] context=\(context) id=\(probeID) phase=\(phaseLabel) \(u) normalizedCandidateCount=\(normalizedCandidateCount) selectedCandidateIndex=\(selectedCandidateIndex) \(e)"
        )
        scheduleURLProbeIfNeeded(context: context, probeID: probeID, url: url)
    }

    nonisolated private static func sanitizedURLFields(_ url: URL) -> String {
        let scheme = url.scheme ?? "nil"
        let host = url.host ?? "nil"
        let port = url.port.map(String.init) ?? "default"
        let ext = url.pathExtension.isEmpty ? "none" : url.pathExtension
        let isFile = url.isFileURL
        let loop = isLoopbackHost(url.host)
        let priv = isPrivateLANHost(url.host)
        return "scheme=\(scheme) host=\(host) port=\(port) ext=\(ext) isFileURL=\(isFile) isLoopbackHost=\(loop) isPrivateLANHost=\(priv)"
    }

    nonisolated private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        if h == "localhost" || h == "127.0.0.1" || h == "::1" { return true }
        if h.hasSuffix(".local") { return true }
        return false
    }

    nonisolated private static func isPrivateLANHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        if h.hasPrefix("10.") { return true }
        if h.hasPrefix("192.168.") { return true }
        if h.hasPrefix("172.") {
            let parts = h.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]) {
                return second >= 16 && second <= 31
            }
        }
        if h == "169.254.0.1" || h.hasPrefix("169.254.") { return true }
        return false
    }

    nonisolated private static func sanitizedNSErrorFields(_ error: Error) -> String {
        let ns = error as NSError
        var desc = ns.localizedDescription
        if desc.contains("://") || desc.contains("http") || desc.contains(".jpg") || desc.contains(".png") {
            desc = "redactedMayContainURL"
        } else if desc.count > 160 {
            desc = String(desc.prefix(160)) + "…"
        }
        return "errorDomain=\(ns.domain) errorCode=\(ns.code) description=\(desc)"
    }

    nonisolated private static func canonicalURLIdentityHash(_ url: URL) -> Int {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.fragment = nil
        return (c?.url ?? url).absoluteString.hashValue
    }

    /// One lightweight GET per distinct URL (budget-limited); logs status/mime/prefix kind only.
    private static func scheduleURLProbeIfNeeded(context: String, probeID: String, url: URL) {
        guard !url.isFileURL else { return }
        let hash = canonicalURLIdentityHash(url)
        probeLock.lock()
        defer { probeLock.unlock() }
        guard probeBudgetRemaining > 0 else { return }
        guard probedURLIdentityHashes.insert(hash).inserted else { return }
        probeBudgetRemaining -= 1

        let scheme = url.scheme ?? "nil"
        let host = url.host ?? "nil"

        Task.detached(priority: .utility) {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 22
            request.httpShouldHandleCookies = true

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? -1
                let mime = http?.mimeType ?? "nil"
                let cl = http?.expectedContentLength ?? -1
                let prefixKind = classifyDataPrefix(data)

                let logLine = "[ThreadImage][Probe] context=\(context) id=\(probeID) scheme=\(scheme) host=\(host) statusCode=\(status) mimeType=\(mime) contentLength=\(cl) dataPrefixKind=\(prefixKind)"

                await MainActor.run {
                    print(logLine)
                }
            } catch {
                let ns = error as NSError
                var desc = ns.localizedDescription
                if desc.contains("://") || desc.contains("http") {
                    desc = "redactedMayContainURL"
                }

                let logLine = "[ThreadImage][Probe] context=\(context) id=\(probeID) scheme=\(scheme) host=\(host) probeErrorDomain=\(ns.domain) probeErrorCode=\(ns.code) probeError=\(desc)"

                await MainActor.run {
                    print(logLine)
                }
            }
        }
    }

    nonisolated private static func classifyDataPrefix(_ data: Data) -> String {
        guard !data.isEmpty else { return "empty" }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 { return "image/jpegMagic" }
        if data.count >= 8,
           data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47,
           data[4] == 0x0D, data[5] == 0x0A, data[6] == 0x1A, data[7] == 0x0A {
            return "image/pngMagic"
        }
        if data.count >= 6, data[0] == 0x47, data[1] == 0x49, data[2] == 0x46, data[3] == 0x38 { return "image/gifMagic" }
        if data.count >= 12,
           data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
           data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50 {
            return "image/webpMagic"
        }
        if data[0] == 0x3C { return "asciiLT_maybeHTML" }
        if data[0] == 0x7B || data[0] == 0x5B { return "asciiBraceOrBracket_maybeJSON" }
        return "unknownBytes"
    }
}
#endif

/// Dark premium thread/work row (black · charcoal · white · grey · orange only).
struct UnifyWorkThreadRow: View {
    let title: String
    var statusTag: String = ""
    var subtitle: String = ""
    var footnote: String?
    var timestamp: String = ""
    var systemImage: String = "bubble.left.and.bubble.right"
    /// Image URL candidates (https, protocol-relative, other `://` schemes, local `file:`); first loadable wins (mirrors thread-detail hero ordering).
    var avatarImageURLCandidates: [String] = []
    /// Used when no URL or image load fails.
    var avatarInitials: String = ""
    var showsAttentionDot: Bool = false
    var showsAttentionRing: Bool = false
    var publicSupporterPresentation: ExchangeSupporterPresentation? = nil
    var debugSupporterNodeID: String? = nil
    var debugSupporterProfileID: String? = nil
    /// DEBUG-only: short row id for `[ThreadImage]` logs (nil in release).
    var debugThreadImageRowID: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    GuardianCrownAvatarFrame(
                        showsCrown: publicSupporterPresentation?.showsGuardianCrown == true,
                        avatarDiameter: 50,
                        debugSurface: "threadList",
                        debugNodeID: debugSupporterNodeID,
                        debugProfileID: debugSupporterProfileID
                    ) {
                        ZStack {
                            UnifySoftVeilCircleFill(diameter: 50)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            showsAttentionRing
                                                ? SecretaryTheme.darkOrange
                                                : SecretaryTheme.white.opacity(0.075 * 0.9),
                                            lineWidth: showsAttentionRing ? 2.25 : 1
                                        )
                                )

                            leadAvatar
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                        }
                    }

                    if showsAttentionDot {
                        Circle()
                            .fill(SecretaryTheme.darkActivityDot)
                            .frame(width: 11, height: 11)
                            .overlay(
                                Circle()
                                    .stroke(SecretaryTheme.darkBackground, lineWidth: 2)
                            )
                            .offset(x: 3, y: 3)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if !timestamp.isEmpty {
                            Text(timestamp)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkMutedText)
                        }
                    }

                    if !statusTag.isEmpty {
                        Text(statusTag.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                            .lineLimit(1)
                    }

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                            .lineLimit(2)
                    }

                    if let footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var leadAvatar: some View {
        let urls = WorkThreadLeadImageURLNormalizer.normalizedChain(from: avatarImageURLCandidates)
        if urls.isEmpty {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
        } else {
            WorkThreadLeadAsyncImage(
                urls: urls,
                initials: threadRowInitials,
                debugAsyncContext: debugThreadImageRowID.map { "row:\($0)" }
            )
        }
    }

    private var threadRowInitials: String {
        let t = avatarInitials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(2)).uppercased() }
        return String(title.prefix(1)).uppercased()
    }
}

/// Tries thread image URLs in order; advances on `AsyncImage` failure (same idea as thread-detail hero).
struct WorkThreadLeadAsyncImage: View {
    let urls: [String]
    let initials: String
    var diameter: CGFloat = 50
    /// DEBUG-only label for AsyncImage phase logs, e.g. `row:abc12def`.
    var debugAsyncContext: String? = nil

    @State private var resolvedIndex: Int = 0

    var body: some View {
        Group {
            if urls.isEmpty {
                glassInitials
            } else {
                let idx = min(max(0, resolvedIndex), urls.count - 1)
                let urlString = urls[idx]
                if let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .onAppear {
                                    #if DEBUG
                                    if let ctx = debugAsyncContext {
                                        ThreadImagePipelineDebug.logAsyncPhase(context: ctx, id: "\(idx)", phase: "success")
                                    }
                                    #endif
                                }
                        case .failure(let error):
                            Group {
                                if idx < urls.count - 1 {
                                    Color.clear
                                        .onAppear {
                                            #if DEBUG
                                            ThreadImagePipelineDebug.logAsyncImageFailure(
                                                context: "row",
                                                probeID: debugAsyncContext ?? "n/a",
                                                url: url,
                                                error: error,
                                                normalizedCandidateCount: urls.count,
                                                selectedCandidateIndex: idx,
                                                phaseLabel: "failure"
                                            )
                                            #endif
                                            scheduleAdvance(from: idx)
                                        }
                                } else {
                                    glassInitials
                                        .onAppear {
                                            #if DEBUG
                                            ThreadImagePipelineDebug.logAsyncImageFailure(
                                                context: "row",
                                                probeID: debugAsyncContext ?? "n/a",
                                                url: url,
                                                error: error,
                                                normalizedCandidateCount: urls.count,
                                                selectedCandidateIndex: idx,
                                                phaseLabel: "failureLast"
                                            )
                                            #endif
                                        }
                                }
                            }
                        case .empty:
                            ProgressView()
                                .controlSize(.small)
                                .tint(SecretaryTheme.darkOrange)
                                .onAppear {
                                    #if DEBUG
                                    if let ctx = debugAsyncContext {
                                        ThreadImagePipelineDebug.logAsyncPhase(context: ctx, id: "\(idx)", phase: "empty")
                                    }
                                    #endif
                                }
                        @unknown default:
                            Group {
                                if idx < urls.count - 1 {
                                    Color.clear
                                        .onAppear { scheduleAdvance(from: idx) }
                                } else {
                                    glassInitials
                                }
                            }
                            .onAppear {
                                #if DEBUG
                                if let ctx = debugAsyncContext {
                                    ThreadImagePipelineDebug.logAsyncPhase(context: ctx, id: "\(idx)", phase: "unknown")
                                }
                                #endif
                            }
                        }
                    }
                    .id("\(idx)-\(urlString)")
                } else if idx < urls.count - 1 {
                    Color.clear
                        .onAppear {
                            #if DEBUG
                            if let ctx = debugAsyncContext {
                                ThreadImagePipelineDebug.logAsyncPhase(context: ctx, id: "\(idx)", phase: "urlParseFailed")
                            }
                            #endif
                            scheduleAdvance(from: idx)
                        }
                } else {
                    glassInitials
                        .onAppear {
                            #if DEBUG
                            if let ctx = debugAsyncContext {
                                ThreadImagePipelineDebug.logAsyncPhase(context: ctx, id: "\(idx)", phase: "urlParseFailedLast")
                            }
                            #endif
                        }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .onChange(of: urls) { _, _ in
            resolvedIndex = 0
        }
    }

    private var glassInitials: some View {
        ZStack {
            Circle()
                .fill(SecretaryTheme.darkGlass.opacity(0.85))
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            Text(initials)
                .font(.system(size: max(12, min(16, diameter * 0.30)), weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkPrimaryText)
        }
    }

    private func scheduleAdvance(from idx: Int) {
        guard idx == resolvedIndex else { return }
        guard idx + 1 < urls.count else { return }
        let expected = idx
        DispatchQueue.main.async {
            if resolvedIndex == expected {
                resolvedIndex = expected + 1
            }
        }
    }
}

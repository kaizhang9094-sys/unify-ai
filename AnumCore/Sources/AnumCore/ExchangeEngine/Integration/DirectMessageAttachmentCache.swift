import Foundation

/// On-device cache for downloaded private DM attachments (bytes only; not indexed for AI).
public enum DirectMessageAttachmentCache {
    public enum CacheError: Error, Sendable, Hashable {
        case invalidStorageKey
        case writeFailed
    }

    public static func cachedFileURL(
        storageKey: String,
        filename: String
    ) throws -> URL {
        let safeKey = sanitizedStorageKey(storageKey)
        let safeName = sanitizedFilename(filename)
        let dir = try cacheRootDirectory().appendingPathComponent(safeKey, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(safeName, isDirectory: false)
    }

    public static func isCached(storageKey: String, filename: String) -> Bool {
        guard let url = try? cachedFileURL(storageKey: storageKey, filename: filename) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    public static func write(
        data: Data,
        storageKey: String,
        filename: String
    ) throws -> URL {
        let url = try cachedFileURL(storageKey: storageKey, filename: filename)
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            throw CacheError.writeFailed
        }
    }

    public static func copyIntoCache(
        from sourceURL: URL,
        storageKey: String,
        filename: String
    ) throws -> URL {
        let data = try Data(contentsOf: sourceURL)
        return try write(data: data, storageKey: storageKey, filename: filename)
    }

    private static func cacheRootDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("DirectMessageAttachments", isDirectory: true)
    }

    private static func sanitizedStorageKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let filtered = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(filtered)
        return out.isEmpty ? "invalid" : String(out.prefix(120))
    }

    private static func sanitizedFilename(_ raw: String) -> String {
        let base = (raw as NSString).lastPathComponent
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "attachment" }
        return String(trimmed.prefix(180))
    }
}

import Foundation

enum SecretaryRepresentationStorage {
    nonisolated private static var defaultsKey: String {
        "secretary.representation.text"
    }

    nonisolated private static var maxCharacters: Int {
        1400
    }

    nonisolated static func load() -> String {
        clean(
            UserDefaults.standard.string(forKey: defaultsKey)
        )
    }

    nonisolated static func loadOptional() -> String? {
        let value = load()
        return value.isEmpty ? nil : value
    }

    @discardableResult
    nonisolated static func save(_ text: String) -> String {
        let cleaned = clean(text)

        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(cleaned, forKey: defaultsKey)
        }

        UserDefaults.standard.synchronize()
        return cleaned
    }

    nonisolated private static func clean(_ text: String?) -> String {
        let trimmed = text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmed.isEmpty else { return "" }

        if trimmed.count <= maxCharacters {
            return trimmed
        }

        return String(trimmed.prefix(maxCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

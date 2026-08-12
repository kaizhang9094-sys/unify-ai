import Foundation

/// UserDefaults-backed secretary **style & tone** (voice only; synced to `ExchangeSecretaryStyleProfile.freeformInstructions`).
enum SecretaryStyleTextStorage {
    nonisolated private static var defaultsKey: String {
        "secretary.style.freeform.text"
    }

    nonisolated private static var maxCharacters: Int {
        1400
    }

    nonisolated static func load() -> String {
        clean(UserDefaults.standard.string(forKey: defaultsKey))
    }

    nonisolated static func loadOptional() -> String? {
        let value = load()
        return value.isEmpty ? nil : value
    }

    /// For `[SecretaryInstructionsSettings]` logging: key present vs default-empty.
    nonisolated static func loadLoggingSource() -> SecretaryStyleLoadSource {
        UserDefaults.standard.object(forKey: defaultsKey) != nil ? .newKey : .defaultEmpty
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

enum SecretaryStyleLoadSource: String, Sendable {
    case newKey
    case defaultEmpty
}

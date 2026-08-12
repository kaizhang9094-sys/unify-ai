import Foundation

enum GenderChoice: Equatable {
    case woman
    case man
    case nonBinary
    case custom(String)
    case preferNotToSay

    static let allPreset: [GenderChoice] = [.woman, .man, .nonBinary, .preferNotToSay]

    var displayName: String {
        switch self {
        case .woman: return "Woman"
        case .man: return "Man"
        case .nonBinary: return "Non-binary"
        case .custom(let s): return s.isEmpty ? "Custom" : s
        case .preferNotToSay: return "Prefer not to say"
        }
    }

    // Storage-friendly encoding
    var rawValue: String {
        switch self {
        case .woman: return "woman"
        case .man: return "man"
        case .nonBinary: return "nonbinary"
        case .preferNotToSay: return "na"
        case .custom(let s):
            return "custom:\(s)"
        }
    }

    static func fromRaw(_ raw: String) -> GenderChoice {
        if raw.hasPrefix("custom:") {
            let s = String(raw.dropFirst("custom:".count))
            return .custom(s)
        }
        switch raw {
        case "woman": return .woman
        case "man": return .man
        case "nonbinary": return .nonBinary
        case "na": return .preferNotToSay
        default: return .preferNotToSay
        }
    }
}

struct OnboardingDraft: Equatable {
    var companionName: String = ""
    var companionGender: GenderChoice = .preferNotToSay

    var userName: String = ""
    var userGender: GenderChoice = .preferNotToSay
}

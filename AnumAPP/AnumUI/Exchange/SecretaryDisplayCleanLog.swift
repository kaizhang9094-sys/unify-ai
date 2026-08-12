import Foundation

/// DEBUG-only trace for Secretary / Discovery display boundary (product copy vs raw engine strings).
enum SecretaryDisplayCleanLog {
    #if DEBUG
    static func log(surface: String, titleSource: String, bodySource: String, strippedInternal: Bool) {
        Swift.print(
            "[SecretaryDisplayClean] surface=\(surface) titleSource=\(titleSource) bodySource=\(bodySource) strippedInternal=\(strippedInternal)"
        )
    }
    #else
    static func log(surface: String, titleSource: String, bodySource: String, strippedInternal: Bool) {}
    #endif
}

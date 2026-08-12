import Foundation

#if DEBUG

/// Matrix-only axis embedding provider. Never wired into production retrieval.
struct MultilingualSecretaryMatrixAxisEmbeddingProvider: MemoryEmbeddingProvider, Sendable {
    static let dimension = 8
    static let noisyAxis = 7

    init() {}

    func embed(_ text: String) -> [Float]? {
        Self.vector(for: Self.axisIndex(for: text))
    }

    static func axisIndex(for text: String) -> Int {
        let key = text.lowercased()
        if containsAny(key, ["roofer", "roof", "roofing"]) { return 0 }
        if containsAny(key, ["cleaner", "cleaning", "housekeeping"]) { return 1 }
        if containsAny(key, ["plumber", "plumbing", "pipe"]) { return 2 }
        if containsAny(key, ["photographer", "photography", "wedding photo"]) { return 3 }
        if containsAny(key, ["dog", "puppy", "pet"]) { return 4 }
        if containsAny(key, ["inspector", "inspection", "home inspection"]) { return 5 }
        if containsAny(key, ["moving", "mover", "move company"]) { return 6 }
        if containsAny(key, ["renovation", "contractor", "kitchen remodel"]) { return 0 }
        if containsAny(key, ["postpartum", "caregiver", "月嫂", "confinement"]) { return 1 }
        if containsAny(key, ["electrician", "electrical", "水电", "wiring", "outlet"]) { return 2 }
        return noisyAxis
    }

    static func vector(for axis: Int) -> [Float] {
        var components = Array(repeating: Float(0), count: dimension)
        let clamped = max(0, min(axis, dimension - 1))
        components[clamped] = 1
        return components
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

#endif

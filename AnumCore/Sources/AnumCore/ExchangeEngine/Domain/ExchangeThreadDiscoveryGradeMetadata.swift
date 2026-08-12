import Foundation

/// Durable discovery grade anchors for umbrella projection when internal workflow state is weak.
public enum ExchangeThreadDiscoveryGradeMetadata {
    public static let discoveryResultKey = "discovery_result"
    public static let classifyGradeKey = "discovery_classify_grade"
    public static let projectedGradeKey = "discovery_projected_grade"
    public static let gradeReasonKey = "discovery_grade_reason"

    public enum DiscoveryResult: String, Sendable, Hashable {
        case found
        case weak
        case none
    }

    public enum ClassifyGrade: String, Sendable, Hashable {
        case strong
        case moderateReviewNeeded = "moderate_review_needed"
        case weak
    }

    public enum ProjectedGrade: String, Sendable, Hashable {
        case strong
        case moderate
        case weak
    }

    public struct Snapshot: Sendable, Hashable {
        public var discoveryResult: DiscoveryResult?
        public var classifyGrade: ClassifyGrade?
        public var projectedGrade: ProjectedGrade?
        public var gradeReason: String?

        public init(
            discoveryResult: DiscoveryResult? = nil,
            classifyGrade: ClassifyGrade? = nil,
            projectedGrade: ProjectedGrade? = nil,
            gradeReason: String? = nil
        ) {
            self.discoveryResult = discoveryResult
            self.classifyGrade = classifyGrade
            self.projectedGrade = projectedGrade
            self.gradeReason = gradeReason
        }
    }

    public static func snapshot(from metadata: [String: String]) -> Snapshot {
        Snapshot(
            discoveryResult: normalizedEnum(DiscoveryResult.self, metadata[discoveryResultKey]),
            classifyGrade: normalizedEnum(ClassifyGrade.self, metadata[classifyGradeKey]),
            projectedGrade: normalizedEnum(ProjectedGrade.self, metadata[projectedGradeKey]),
            gradeReason: normalized(metadata[gradeReasonKey])
        )
    }

    public static func applyFoundGrade(
        classifyGrade: ClassifyGrade,
        activatedChildCount: Int,
        to metadata: inout [String: String]
    ) {
        let projected = projectedGrade(for: classifyGrade, activatedChildCount: activatedChildCount)
        let reason: String
        switch classifyGrade {
        case .strong:
            reason = "strong_classify_preserved"
        case .moderateReviewNeeded:
            reason = "moderate_review_needed_preserved"
        case .weak:
            reason = "weak_classify"
        }

        metadata[discoveryResultKey] = DiscoveryResult.found.rawValue
        metadata[classifyGradeKey] = classifyGrade.rawValue
        metadata[projectedGradeKey] = projected.rawValue
        metadata[gradeReasonKey] = reason
    }

    public static func applyWeakGrade(to metadata: inout [String: String]) {
        metadata[discoveryResultKey] = DiscoveryResult.weak.rawValue
        metadata[classifyGradeKey] = ClassifyGrade.weak.rawValue
        metadata[projectedGradeKey] = ProjectedGrade.weak.rawValue
        metadata[gradeReasonKey] = "weak_classify"
    }

    public static let persistedMetadataKeys: [String] = [
        discoveryResultKey,
        classifyGradeKey,
        projectedGradeKey,
        gradeReasonKey
    ]

    public static func hasPersistedGrade(in metadata: [String: String]) -> Bool {
        snapshot(from: metadata).projectedGrade != nil
    }

    public static func mergeColumnMetadata(
        snapshotMetadata: [String: String],
        columnMetadata: [String: String]
    ) -> [String: String] {
        var merged = snapshotMetadata
        for (key, value) in columnMetadata {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            merged[key] = trimmed
        }
        return merged
    }

    #if DEBUG
    public static func logWrite(
        rootThreadID: ExchangeThread.ID,
        thread: ExchangeThread,
        classifyGrade: ClassifyGrade
    ) {
        let snapshot = snapshot(from: thread.metadata)
        Swift.print(
            "[UmbrellaGradeWrite] " +
            "rootThreadID=\(rootThreadID.uuidString) " +
            "classifyGrade=\(classifyGrade.rawValue) " +
            "projectedGrade=\(snapshot.projectedGrade?.rawValue ?? "nil") " +
            "metadataKeys=\(gradeMetadataKeySummary(from: thread.metadata)) " +
            "threadState=\(ExchangeTransition.ExchangeStateKey(thread.state).rawValue)"
        )
    }

    public static func logPersistVerify(
        rootThreadID: ExchangeThread.ID,
        beforeSaveKeys: [String: String],
        afterFetchKeys: [String: String]
    ) {
        Swift.print(
            "[UmbrellaGradePersist] " +
            "rootThreadID=\(rootThreadID.uuidString) " +
            "beforeSaveKeys=\(gradeMetadataKeySummary(from: beforeSaveKeys)) " +
            "afterFetchKeys=\(gradeMetadataKeySummary(from: afterFetchKeys)) " +
            "afterFetchHasGrade=\(hasPersistedGrade(in: afterFetchKeys))"
        )
    }

    public static func logRead(
        rootThreadID: ExchangeThread.ID,
        metadata: [String: String],
        usesMetadata: Bool,
        activatedChildCount: Int
    ) {
        let snapshot = snapshot(from: metadata)
        Swift.print(
            "[UmbrellaGradeRead] " +
            "rootThreadID=\(rootThreadID.uuidString) " +
            "rawMetadataKeys=\(gradeMetadataKeySummary(from: metadata)) " +
            "discovery_result=\(snapshot.discoveryResult?.rawValue ?? "nil") " +
            "discovery_classify_grade=\(snapshot.classifyGrade?.rawValue ?? "nil") " +
            "discovery_projected_grade=\(snapshot.projectedGrade?.rawValue ?? "nil") " +
            "usesMetadata=\(usesMetadata ? "true" : "false") " +
            "activatedChildCount=\(activatedChildCount)"
        )
    }

    private static func gradeMetadataKeySummary(from metadata: [String: String]) -> String {
        persistedMetadataKeys
            .map { key in
                let value = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"
                return "\(key)=\(value.isEmpty ? "nil" : value)"
            }
            .joined(separator: ",")
    }
    #else
    public static func logWrite(
        rootThreadID: ExchangeThread.ID,
        thread: ExchangeThread,
        classifyGrade: ClassifyGrade
    ) { }

    public static func logPersistVerify(
        rootThreadID: ExchangeThread.ID,
        beforeSaveKeys: [String: String],
        afterFetchKeys: [String: String]
    ) { }

    public static func logRead(
        rootThreadID: ExchangeThread.ID,
        metadata: [String: String],
        usesMetadata: Bool,
        activatedChildCount: Int
    ) { }
    #endif

    public static func projectedGrade(
        for classifyGrade: ClassifyGrade,
        activatedChildCount: Int
    ) -> ProjectedGrade {
        guard activatedChildCount > 0 else {
            switch classifyGrade {
            case .strong:
                return .strong
            case .moderateReviewNeeded:
                return .moderate
            case .weak:
                return .weak
            }
        }

        switch classifyGrade {
        case .strong:
            return .strong
        case .moderateReviewNeeded:
            return .moderate
        case .weak:
            return .weak
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedEnum<T: RawRepresentable>(
        _ type: T.Type,
        _ value: String?
    ) -> T? where T.RawValue == String {
        guard let normalized = normalized(value) else { return nil }
        return T(rawValue: normalized)
    }
}

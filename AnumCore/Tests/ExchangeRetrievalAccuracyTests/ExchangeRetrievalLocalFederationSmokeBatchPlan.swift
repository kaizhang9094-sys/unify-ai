import Foundation

struct LocalFederationSmokeBatchEntry: Sendable, Hashable {
    let batchID: Int
    let runID: Int
    let scenarioID: String
    let repeatIndex: Int
}

enum ExchangeRetrievalLocalFederationSmokeBatchPlan {
    static var defaultRunCount: Int { defaultEntries.count }
    static var fullRunCount: Int { fullEntries.count }

    static var activeEntries: [LocalFederationSmokeBatchEntry] {
        if ExchangeRetrievalLocalFederationSmokeGate.isFullBatchMode {
            return fullEntries
        }
        return defaultEntries
    }

    static let defaultEntries: [LocalFederationSmokeBatchEntry] = batch1 + batch2
    static let fullEntries: [LocalFederationSmokeBatchEntry] = batch1 + batch2 + batch3 + batch4

    static let batch1: [LocalFederationSmokeBatchEntry] = [
        entry(batch: 1, run: 1, scenario: "object-lane.computer", repeat: 0),
        entry(batch: 1, run: 2, scenario: "object-lane.car", repeat: 0),
        entry(batch: 1, run: 3, scenario: "object-lane.multi-seller-computer", repeat: 0),
        entry(batch: 1, run: 4, scenario: "object-lane.laptop", repeat: 0),
        entry(batch: 1, run: 5, scenario: "object-lane.computer-budget-time", repeat: 0),
        entry(batch: 1, run: 6, scenario: "object-lane.toyota", repeat: 0),
        entry(batch: 1, run: 7, scenario: "object-lane.macbook", repeat: 0),
        entry(batch: 1, run: 8, scenario: "object-lane.computer", repeat: 1),
        entry(batch: 1, run: 9, scenario: "object-lane.car", repeat: 1),
        entry(batch: 1, run: 10, scenario: "object-lane.multi-seller-computer", repeat: 1)
    ]

    static let batch2: [LocalFederationSmokeBatchEntry] = [
        entry(batch: 2, run: 1, scenario: "package.wedding-photo", repeat: 0),
        entry(batch: 2, run: 2, scenario: "faq.photo-delivery", repeat: 0),
        entry(batch: 2, run: 3, scenario: "package.move-out-cleaning", repeat: 0),
        entry(batch: 2, run: 4, scenario: "faq.delivery", repeat: 0),
        entry(batch: 2, run: 5, scenario: "capability.find-coder", repeat: 0),
        entry(batch: 2, run: 6, scenario: "provider.plumber-appraisal", repeat: 0),
        entry(batch: 2, run: 7, scenario: "capability.build-ios-app", repeat: 0),
        entry(batch: 2, run: 8, scenario: "affinity.robotics", repeat: 0),
        entry(batch: 2, run: 9, scenario: "seeking.startup-collaboration", repeat: 0),
        entry(batch: 2, run: 10, scenario: "mixed.available-tomorrow", repeat: 0)
    ]

    static let batch3: [LocalFederationSmokeBatchEntry] = [
        entry(batch: 3, run: 1, scenario: "capability.find-coder", repeat: 0),
        entry(batch: 3, run: 2, scenario: "provider.plumber-appraisal", repeat: 0),
        entry(batch: 3, run: 3, scenario: "capability.build-ios-app", repeat: 0),
        entry(batch: 3, run: 4, scenario: "affinity.local-founders-ai", repeat: 0),
        entry(batch: 3, run: 5, scenario: "capability.find-coder", repeat: 1),
        entry(batch: 3, run: 6, scenario: "provider.plumber-appraisal", repeat: 1),
        entry(batch: 3, run: 7, scenario: "capability.find-coder", repeat: 2),
        entry(batch: 3, run: 8, scenario: "provider.plumber-appraisal", repeat: 2),
        entry(batch: 3, run: 9, scenario: "mixed.available-tomorrow", repeat: 1),
        entry(batch: 3, run: 10, scenario: "capability.build-ios-app", repeat: 1)
    ]

    static let batch4: [LocalFederationSmokeBatchEntry] = [
        entry(batch: 4, run: 1, scenario: "affinity.robotics", repeat: 0),
        entry(batch: 4, run: 2, scenario: "seeking.startup-collaboration", repeat: 0),
        entry(batch: 4, run: 3, scenario: "affinity.local-founders-ai", repeat: 0),
        entry(batch: 4, run: 4, scenario: "mixed.photographer-collaboration", repeat: 0),
        entry(batch: 4, run: 5, scenario: "affinity.founder-hardware", repeat: 0),
        entry(batch: 4, run: 6, scenario: "seeking.startup-collaboration", repeat: 1),
        entry(batch: 4, run: 7, scenario: "affinity.robotics", repeat: 1),
        entry(batch: 4, run: 8, scenario: "seeking.startup-collaboration", repeat: 2),
        entry(batch: 4, run: 9, scenario: "mixed.photographer-collaboration", repeat: 1),
        entry(batch: 4, run: 10, scenario: "mixed.available-tomorrow", repeat: 0)
    ]

    private static func entry(batch: Int, run: Int, scenario: String, repeat repeatIndex: Int) -> LocalFederationSmokeBatchEntry {
        LocalFederationSmokeBatchEntry(batchID: batch, runID: run, scenarioID: scenario, repeatIndex: repeatIndex)
    }
}

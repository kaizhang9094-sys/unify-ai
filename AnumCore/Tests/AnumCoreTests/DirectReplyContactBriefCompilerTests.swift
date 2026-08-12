import XCTest
@testable import AnumCore

final class DirectReplyContactBriefCompilerTests: XCTestCase {
    func testFriendMaintainFriendshipWarmCasual() {
        let context = ExchangeModels.ContactContext(
            remoteNodeID: "node-a",
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship
        )
        let brief = DirectReplyContactBriefCompiler.compile(contactContext: context)
        XCTAssertNotNil(brief)
        XCTAssertEqual(brief?.relationship, "friend")
        XCTAssertEqual(brief?.tone, "warm, natural, casual")
        XCTAssertTrue(brief?.styleConstraints.contains(where: { $0.contains("continue the conversation") }) == true)
    }

    func testColleagueWarmProfessionalClearPolite() {
        let context = ExchangeModels.ContactContext(
            remoteNodeID: "node-b",
            relationshipType: .colleague,
            relationshipGoal: .warmProfessionalContact
        )
        let brief = DirectReplyContactBriefCompiler.compile(contactContext: context)
        XCTAssertEqual(brief?.tone, "clear, polite, concise")
        XCTAssertTrue(brief?.styleConstraints.contains(where: { $0.contains("friendly without overfamiliarity") }) == true)
    }

    func testToneOverrideAppearsCapped() {
        let longTone = String(repeating: "x", count: 200)
        let context = ExchangeModels.ContactContext(
            remoteNodeID: "node-c",
            relationshipType: .colleague,
            relationshipGoal: .warmProfessionalContact,
            toneOverride: longTone
        )
        let brief = DirectReplyContactBriefCompiler.compile(contactContext: context)
        XCTAssertEqual(brief?.tone.count, DirectReplyContactBriefCompiler.toneOverrideMaxChars)
    }

    func testEmptyNotesOmittedFromBoundaries() {
        let context = ExchangeModels.ContactContext(
            remoteNodeID: "node-d",
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship,
            notes: ""
        )
        let brief = DirectReplyContactBriefCompiler.compile(contactContext: context)
        XCTAssertFalse(brief?.boundaries.contains(where: { $0.hasPrefix("Contact notes:") }) == true)
    }
}

import Foundation
import Testing
@testable import AnumCore

struct ExchangeSemanticProofBackwardCompatibilityTests {
    @Test
    func offerAttachmentDecodesWhenTargetOverlapMissing() throws {
        let json = """
        {
          "offerID": "offer-legacy-1",
          "reason": "directOfferDocumentHit",
          "proofStrength": "concrete",
          "lexicalOverlap": 4
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(
            ExchangeCandidateSemanticProof.OfferAttachment.self,
            from: data
        )

        #expect(decoded.offerID == "offer-legacy-1")
        #expect(decoded.targetOverlap == 0)
        #expect(decoded.genericOverlap == 0)
        #expect(decoded.satisfiesMinimumProof == false)
    }

    @Test
    func semanticProofDecodesLegacyOfferAttachmentInsideMatch() throws {
        let json = """
        {
          "offerAttachments": [
            {
              "offerID": "offer-legacy-2",
              "reason": "profileInheritedOffer",
              "proofStrength": "weakRecall",
              "lexicalOverlap": 2
            }
          ],
          "summary": {
            "maxProofStrength": "weakRecall",
            "satisfiesMinimumProof": false,
            "hasWeakRecallOnly": true
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let proof = try JSONDecoder().decode(
            ExchangeCandidateSemanticProof.self,
            from: data
        )

        #expect(proof.offerAttachments.count == 1)
        #expect(proof.offerAttachments[0].targetOverlap == 0)
        #expect(proof.offerAttachments[0].genericOverlap == 0)
    }

    @Test
    func semanticProofDecodesLegacyEnvelopeWithProvenObjectOfferIDsKey() throws {
        let json = """
        {
          "offerAttachments": [],
          "provenObjectOfferIDs": ["offer-legacy-3"],
          "objectEvidenceScoreByOfferID": { "offer-legacy-3": 0.61 }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let proof = try JSONDecoder().decode(
            ExchangeCandidateSemanticProof.self,
            from: data
        )

        #expect(proof.offerAttachments.isEmpty)
        #expect(proof.summary.maxProofStrength == .weakRecall)
    }

    @Test
    func semanticProofDecodesWhenSummaryMissing() throws {
        let json = """
        {
          "offerAttachments": [
            {
              "offerID": "offer-legacy-4",
              "reason": "directOfferDocumentHit",
              "proofStrength": "concrete"
            }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let proof = try JSONDecoder().decode(
            ExchangeCandidateSemanticProof.self,
            from: data
        )

        #expect(proof.offerAttachments.count == 1)
        #expect(proof.summary.satisfiesMinimumProof == false)
    }

    @Test
    func exchangeMatchDecodesWhenProvenObjectOfferIDsMissing() throws {
        let threadID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let matchID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let json = """
        {
          "id": "\(matchID.uuidString)",
          "threadID": "\(threadID.uuidString)",
          "counterpartyID": "node-legacy-1",
          "createdAt": 0,
          "scope": "counterparty",
          "matchedOfferIDs": [],
          "status": "candidate",
          "strength": "moderate",
          "score": 0.42,
          "reasons": [],
          "cautions": [],
          "fit": {},
          "metadata": {},
          "semanticProof": {
            "offerAttachments": [
              {
                "offerID": "offer-legacy-5",
                "reason": "profileInheritedOffer",
                "proofStrength": "weakRecall"
              }
            ]
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let data = try #require(json.data(using: .utf8))
        let match = try decoder.decode(ExchangeMatch.self, from: data)

        #expect(match.provenObjectOfferIDs.isEmpty)
        #expect(match.objectEvidenceScoreByOfferID.isEmpty)
        #expect(match.semanticProof?.offerAttachments.count == 1)
    }
}

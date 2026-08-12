import Foundation

enum ProviderInboundIntentExtractionPromptBuilder {
    static func prompt(for request: ProviderInboundIntentExtractionRequest) -> String {
        let counterparty = escaped(request.selectedCounterpartyID) ?? "null"
        let offerID = escaped(request.selectedOfferID) ?? "null"
        let profileID = escaped(request.selectedPublicProfileID) ?? "null"
        let threadID = request.threadID?.uuidString ?? "null"

        return """
        You are the provider-side inbound intent extractor for a private AI secretary system.

        ROLE: The seller/provider received an inbound message from an external requester in an active thread.
        This is NOT requester search or discovery routing. Do not output search lanes, routeClass, affinity/offer/mixed surfaces, or retrieval routing labels.

        Your job:
        1. Identify what the requester is asking the provider/seller.
        2. Select which seller fact surfaces would be needed to answer responsibly.
        3. Flag commercial intent, commitment risk, and sensitive disclosure risk.
        4. Return exactly one compact JSON object.

        Safety:
        - Do not invent facts about the seller.
        - Do not draft a reply.
        - Do not decide whether to auto-send.
        - If ambiguous, use inquiryKind=unclear and needsCompareLLM=true.

        Allowed inquiryKind (exactly one):
        availabilityOrOpenness, capabilityOrServiceFit, pricingOrQuote, schedulingOrTiming, logisticsOrFulfillment, policyOrTerms, introductionOrContact, sensitiveDisclosure, commitmentRequest, socialOrAffinityOnly, unclear

        Allowed requestedFactSurfaces (array, subset only):
        publicProfile, offer, commercialPricing, commercialNonPricing, reachability, operatingMemory, policy, availability

        Allowed requestedClaims (array, subset only):
        openTo, availability, serviceCapability, pricePosture, quoteRequired, serviceArea, leadTime, contactPreference, policy, commitment

        Examples (provider inbound):
        - "Are you open to hearing from early-stage founders?" → inquiryKind=availabilityOrOpenness, commercialIntent=true, surfaces include publicProfile, reachability, availability, offer; claims openTo, availability. NOT socialOrAffinityOnly.
        - "Do you offer VC support for AI startups?" → inquiryKind=capabilityOrServiceFit, surfaces offer, publicProfile, commercialNonPricing, claim serviceCapability.
        - "What is your pricing?" → inquiryKind=pricingOrQuote, surfaces offer, commercialPricing, claims pricePosture, quoteRequired.
        - "Can you commit to a call tomorrow?" → inquiryKind=schedulingOrTiming, asksForCommitment=true, claims commitment, availability.
        - "Can you introduce me to your investors?" → inquiryKind=introductionOrContact, asksForSensitiveInfo or asksForCommitment may be true, needsProviderInputLikely=true.
        - "I'm looking for someone who likes swimming" → socialOrAffinityOnly ONLY if truly non-commercial; surfaces publicProfile only.

        Thread context:
        {"threadID":"\(threadID)","selectedCounterpartyID":\(counterparty),"selectedOfferID":\(offerID),"selectedPublicProfileID":\(profileID)}

        Inbound message:
        \(request.rawRequesterAsk)

        Required JSON shape (one line preferred; booleans true/false):
        {"normalizedRequesterQuestion":"...","askSummary":"...","inquiryKind":"...","requestedFactSurfaces":["..."],"requestedClaims":["..."],"commercialIntent":false,"asksForCommitment":false,"asksForSensitiveInfo":false,"needsProviderInputLikely":false,"needsCompareLLM":true,"confidence":0.0,"rationaleShort":"..."}

        JSON:
        """
    }

    private static func escaped(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return encoded
    }
}

#if DEBUG
import Foundation

// MARK: - Fixtures

public enum ProviderInquiryAnswerOnDeviceSmokeAuditFixtures {

    public enum ExpectedAnswerability: String, Codable, Sendable, Hashable {
        case answerDirectly
        case answerWithCaveat
        case needsProviderConfirmation
        case refuseCommitment
        case notInOffer
        case noAnswer
    }

    public enum ExpectedAllowedSources: String, Codable, Sendable, Hashable {
        case publicProfile
        case commercialOffer
        case both
        case none
    }

    public enum BoundaryExpectation: String, Codable, Sendable, Hashable {
        case publicOnly
        case commercialOnly
        case mixedSeparated
        case noAnswer
    }

    public struct ProfileSpec: Sendable, Hashable {
        public var displayName: String
        public var headline: String?
        public var summary: String?
        public var regionTags: [String]
        public var openTo: [String]
        public var activityTags: [String]
        public var interests: [String]
        public var offers: [String]

        public init(
            displayName: String,
            headline: String? = nil,
            summary: String? = nil,
            regionTags: [String] = [],
            openTo: [String] = [],
            activityTags: [String] = [],
            interests: [String] = [],
            offers: [String] = []
        ) {
            self.displayName = displayName
            self.headline = headline
            self.summary = summary
            self.regionTags = regionTags
            self.openTo = openTo
            self.activityTags = activityTags
            self.interests = interests
            self.offers = offers
        }
    }

    public struct OfferSpec: Sendable, Hashable {
        public var title: String
        public var summary: String
        public var category: String
        public var tags: [String]
        public var leadTimeNote: String?
        public var commercialFacts: ExchangeOffer.CommercialFacts

        public init(
            title: String,
            summary: String,
            category: String = "plumber",
            tags: [String] = [],
            leadTimeNote: String? = nil,
            commercialFacts: ExchangeOffer.CommercialFacts
        ) {
            self.title = title
            self.summary = summary
            self.category = category
            self.tags = tags
            self.leadTimeNote = leadTimeNote
            self.commercialFacts = commercialFacts
        }
    }

    public struct Fixture: Sendable, Hashable {
        public var id: String
        public var requesterQuestion: String
        public var profile: ProfileSpec
        public var offer: OfferSpec?
        public var queryIntentClass: ExchangeIntent.QueryIntentClass
        public var surfacePreference: ExchangeIntent.SurfacePreference
        public var expectedAnswerability: ExpectedAnswerability
        public var expectedAllowedSources: ExpectedAllowedSources
        public var boundaryExpectation: BoundaryExpectation
        /// Each inner array is an OR-group; by default every group must match at least one needle.
        public var requiredNeedleGroups: [[String]]
        /// When set, at least this many OR-groups must match (e.g. 2-of-3 package items). Default: all groups.
        public var requiredNeedleGroupsMinimumMatchCount: Int?
        public var forbiddenNeedles: [String]
        public var forbiddenCommercialClaims: [String]
        public var forbiddenCommitmentPatterns: [String]

        public init(
            id: String,
            requesterQuestion: String,
            profile: ProfileSpec,
            offer: OfferSpec?,
            queryIntentClass: ExchangeIntent.QueryIntentClass,
            surfacePreference: ExchangeIntent.SurfacePreference,
            expectedAnswerability: ExpectedAnswerability,
            expectedAllowedSources: ExpectedAllowedSources,
            boundaryExpectation: BoundaryExpectation,
            requiredNeedleGroups: [[String]],
            requiredNeedleGroupsMinimumMatchCount: Int? = nil,
            forbiddenNeedles: [String] = [],
            forbiddenCommercialClaims: [String] = [],
            forbiddenCommitmentPatterns: [String] = []
        ) {
            self.id = id
            self.requesterQuestion = requesterQuestion
            self.profile = profile
            self.offer = offer
            self.queryIntentClass = queryIntentClass
            self.surfacePreference = surfacePreference
            self.expectedAnswerability = expectedAnswerability
            self.expectedAllowedSources = expectedAllowedSources
            self.boundaryExpectation = boundaryExpectation
            self.requiredNeedleGroups = requiredNeedleGroups
            self.requiredNeedleGroupsMinimumMatchCount = requiredNeedleGroupsMinimumMatchCount
            self.forbiddenNeedles = forbiddenNeedles
            self.forbiddenCommercialClaims = forbiddenCommercialClaims
            self.forbiddenCommitmentPatterns = forbiddenCommitmentPatterns
        }
    }

    private static let permissiveAutoAnswer = ExchangeOffer.AutoAnswerPolicy(
        canAnswerPricing: true,
        canAnswerAvailability: true,
        canAnswerPolicies: true,
        canAnswerServiceArea: true,
        canAnswerFAQs: true,
        requiresApprovalForCustomQuote: true
    )

    private static let baselineProfile = ProfileSpec(
        displayName: "Riverbend Plumbing",
        headline: "Austin-area plumbing professional",
        summary: "I focus on residential service and clear communication.",
        regionTags: ["Austin"],
        openTo: ["home service inquiries"]
    )

    private static func plumberOffer(
        summary: String,
        commercial: ExchangeOffer.CommercialFacts,
        title: String = "Residential plumbing service in Austin",
        leadTimeNote: String? = nil,
        tags: [String] = []
    ) -> OfferSpec {
        var facts = commercial
        facts.autoAnswerPolicy = permissiveAutoAnswer
        return OfferSpec(
            title: title,
            summary: summary,
            tags: tags,
            leadTimeNote: leadTimeNote,
            commercialFacts: facts
        )
    }

    public static let all: [Fixture] = [
        // A. Commercial offer facts
        Fixture(
            id: "price.basic",
            requesterQuestion: "How does your pricing work for a standard leak repair?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89; typical leak repair $150–$280",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["service call", "$89", "89"],
                ["leak repair", "$150", "150", "280", "pricing"]
            ],
            forbiddenNeedles: ["$99", "flat guaranteed", "free", "guaranteed"]
        ),
        Fixture(
            id: "package.items",
            requesterQuestion: "What's included in your Standard Leak Repair package?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    packages: [
                        ExchangeOffer.PackageOption(
                            title: "Standard Leak Repair",
                            summary: "Diagnosis, pipe patch, cleanup"
                        )
                    ],
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["diagnosis"],
                ["pipe patch", "patching", "patch"],
                ["cleanup", "clean up"]
            ],
            requiredNeedleGroupsMinimumMatchCount: 2,
            forbiddenNeedles: ["drain cleaning", "bathroom remodel", "full remodel warranty"]
        ),
        Fixture(
            id: "service.area",
            requesterQuestion: "Do you serve Round Rock for this job?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    serviceAreaNote: "Austin metro including Round Rock and Cedar Park",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["round rock"],
                ["austin metro", "austin"]
            ],
            forbiddenNeedles: ["dallas", "statewide", "houston", "we cover houston"]
        ),
        Fixture(
            id: "availability.window",
            requesterQuestion: "Are you available Saturday afternoon?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    availabilityNote: "Weekends by appointment; Saturday PM often available",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerWithCaveat,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["saturday", "weekend"],
                ["appointment", "often available", "often"]
            ],
            forbiddenNeedles: ["confirmed 2pm", "confirmed 2:30", "booked", "guaranteed"],
            forbiddenCommitmentPatterns: ["confirmed appointment"]
        ),
        Fixture(
            id: "lead.time",
            requesterQuestion: "How soon could you start?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(autoAnswerPolicy: permissiveAutoAnswer),
                leadTimeNote: "Usually 24–48 hours for non-emergency leaks"
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [["24", "48", "24–48", "24-48"]],
            forbiddenNeedles: ["same-day guaranteed", "guaranteed same day"]
        ),
        Fixture(
            id: "buyer.inputs",
            requesterQuestion: "What do you need from me before you come out?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    requiredBuyerInputs: ["Address", "Photos of leak", "Gate code if applicable"],
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [["address"], ["photo", "photos"]],
            forbiddenNeedles: ["deposit required", "deposit due"]
        ),
        Fixture(
            id: "policy.cancellation",
            requesterQuestion: "What's your cancellation policy?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    cancellationPolicy: "Free cancel 24h+ before; same-day $50 fee",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [["24h", "24 hours", "24 hour"], ["$50", "50", "same-day"]],
            forbiddenNeedles: ["full refund guaranteed", "guaranteed refund"]
        ),
        Fixture(
            id: "faq.emergency",
            requesterQuestion: "Do you offer emergency same-night service?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    faqs: [
                        ExchangeOffer.FAQ(
                            question: "Emergency same-night?",
                            answer: "Yes, after-hours surcharge applies; call first."
                        )
                    ],
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["emergency", "same-night", "same night"],
                ["surcharge", "call first"]
            ],
            forbiddenNeedles: ["always available tonight", "no surcharge", "guaranteed tonight"]
        ),
        Fixture(
            id: "exclusion.remodel",
            requesterQuestion: "Do you do full bathroom remodels?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Plumbing repairs only — leak repair, pipe repair, drain clearing. No bathroom remodels.",
                commercial: ExchangeOffer.CommercialFacts(autoAnswerPolicy: permissiveAutoAnswer)
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .notInOffer,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["not listed", "not specified", "don't", "do not", "plumbing repair", "need confirmation", "confirm"]
            ],
            forbiddenNeedles: ["yes we do remodels", "remodel package", "full bathroom remodel price"]
        ),
        Fixture(
            id: "shipping.product",
            requesterQuestion: "How much is shipping to California?",
            profile: ProfileSpec(
                displayName: "Oak Lane Goods",
                headline: "Small-batch home goods",
                summary: "Online shop with US shipping.",
                regionTags: []
            ),
            offer: OfferSpec(
                title: "Ceramic mug set — online",
                summary: "Handmade mug sets shipped within the US.",
                category: "product",
                commercialFacts: ExchangeOffer.CommercialFacts(
                    priceDisplay: "$12 flat rate US shipping",
                    serviceAreaNote: "Ships to 48 contiguous US states",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["$12", "12", "flat rate"],
                ["california", "48 contiguous", "contiguous us", "us states"]
            ],
            forbiddenNeedles: ["free shipping", "2-day guaranteed", "guaranteed delivery"]
        ),

        // B. Missing commercial facts
        Fixture(
            id: "missing.discount",
            requesterQuestion: "Can you do 20% off if I book today?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89; typical leak repair $150–$280",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .needsProviderConfirmation,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["not specified", "need confirmation", "confirm", "ask", "don't have", "do not have", "unable to confirm"]
            ],
            forbiddenNeedles: ["20% off", "20 percent", "discount approved", "today-only deal"],
            forbiddenCommitmentPatterns: ["discount approved"]
        ),
        Fixture(
            id: "missing.exact_slot",
            requesterQuestion: "Can you confirm 2:30–4:00 PM Saturday?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    availabilityNote: "Weekends by appointment; Saturday PM often available",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerWithCaveat,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["appointment", "need confirmation", "confirm with", "not exact", "can't confirm", "cannot confirm"]
            ],
            forbiddenNeedles: ["confirmed 2:30", "confirmed 4:00", "confirmed 2pm", "booked"],
            forbiddenCommitmentPatterns: ["confirmed appointment"]
        ),
        Fixture(
            id: "missing.warranty_cert",
            requesterQuestion: "Are you licensed and insured for this work?",
            profile: ProfileSpec(
                displayName: "Riverbend Plumbing",
                headline: "Austin-area plumbing professional",
                summary: "Residential service and clear communication.",
                regionTags: ["Austin"]
            ),
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(autoAnswerPolicy: permissiveAutoAnswer),
                title: "Residential plumbing service in Austin"
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .notInOffer,
            expectedAllowedSources: .none,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["not specified", "not listed", "need confirmation", "don't have", "do not have", "unable to confirm"]
            ],
            forbiddenNeedles: ["we are licensed", "we're licensed", "fully insured", "licensed and insured"],
            forbiddenCommercialClaims: ["licensed", "insured", "bonded"]
        ),
        Fixture(
            id: "outside.service_area",
            requesterQuestion: "Can you come to Houston same day?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    serviceAreaNote: "Austin metro only",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .notInOffer,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["austin metro", "austin", "outside", "not listed", "need confirmation"]
            ],
            forbiddenNeedles: ["houston same day", "we cover houston", "serve houston"]
        ),
        Fixture(
            id: "commitment.booking",
            requesterQuestion: "Great — please book me for Saturday and send a final quote of $200.",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89; typical leak repair $150–$280",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .refuseCommitment,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["cannot confirm booking", "can't confirm booking", "can not confirm booking",
                 "need confirmation", "not final quote", "can't send a final", "cannot send a final",
                 "unable to book", "can't book", "cannot book"]
            ],
            forbiddenNeedles: ["booked", "confirmed appointment", "final quote of $200", "final quote $200"],
            forbiddenCommitmentPatterns: ["booked", "final quote", "confirmed appointment"]
        ),

        // C. Public profile / social
        Fixture(
            id: "profile.who",
            requesterQuestion: "Who are you and what's your background?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89; typical leak repair $150–$280",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .publicProfile,
            boundaryExpectation: .publicOnly,
            requiredNeedleGroups: [
                ["riverbend", "austin-area", "austin area"],
                ["residential", "clear communication"]
            ],
            forbiddenNeedles: ["service call $89", "$150", "standard leak repair package"]
        ),
        Fixture(
            id: "profile.location",
            requesterQuestion: "Where are you based?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(autoAnswerPolicy: permissiveAutoAnswer)
            ),
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .publicProfile,
            boundaryExpectation: .publicOnly,
            requiredNeedleGroups: [["austin"]],
            forbiddenNeedles: ["round rock service guarantee", "serve houston", "houston"]
        ),
        Fixture(
            id: "profile.infer_service",
            requesterQuestion: "I see you're into home service — do you officially offer leak repairs?",
            profile: ProfileSpec(
                displayName: "Riverbend Plumbing",
                headline: "Austin-area plumbing professional",
                summary: "I focus on residential service and clear communication.",
                regionTags: ["Austin"],
                openTo: ["home service inquiries"],
                activityTags: ["home services"]
            ),
            offer: plumberOffer(
                summary: "General plumbing maintenance and drain clearing.",
                commercial: ExchangeOffer.CommercialFacts(autoAnswerPolicy: permissiveAutoAnswer)
            ),
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            expectedAnswerability: .answerWithCaveat,
            expectedAllowedSources: .both,
            boundaryExpectation: .mixedSeparated,
            requiredNeedleGroups: [
                ["not specified", "listing", "offer", "need confirmation", "confirm", "don't see", "do not see"]
            ],
            forbiddenNeedles: ["yes definitely handle leaks", "definitely offer leak", "we definitely handle leaks"]
        ),

        // D. Boundary / mixed
        Fixture(
            id: "mixed.identity_price",
            requesterQuestion: "Tell me about your business and what a leak repair usually costs.",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89; typical leak repair $150–$280",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            expectedAnswerability: .answerDirectly,
            expectedAllowedSources: .both,
            boundaryExpectation: .mixedSeparated,
            requiredNeedleGroups: [
                ["riverbend", "residential", "austin"],
                ["$89", "89", "150", "280", "service call", "pricing", "leak repair"]
            ],
            forbiddenNeedles: ["invented flat rate", "$99"],
            forbiddenCommercialClaims: []
        ),
        Fixture(
            id: "social.against_commercial",
            requesterQuestion: "Want to grab coffee and talk about your weekend?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .directOutreach,
            surfacePreference: .affinity,
            expectedAnswerability: .noAnswer,
            expectedAllowedSources: .publicProfile,
            boundaryExpectation: .noAnswer,
            requiredNeedleGroups: [
                ["not appropriate", "commercial", "service inquiry", "plumbing", "business inquiry",
                 "happy to discuss", "reach out about", "focus on"]
            ],
            forbiddenNeedles: ["grab coffee", "hang out", "weekend plans", "love to meet"],
            forbiddenCommitmentPatterns: []
        ),

        // E. Provider Claim Ledger disagreement probes (haystack vs ledger DEBUG compare)
        Fixture(
            id: "ledger.discount_negative_faq",
            requesterQuestion: "Can you give me a discount?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89; typical leak repair $150–$280",
                    faqs: [
                        ExchangeOffer.FAQ(
                            question: "Do you offer discounts?",
                            answer: "We do not offer discounts."
                        )
                    ],
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .needsProviderConfirmation,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["not specified", "need confirmation", "confirm", "don't have", "do not have", "unable to confirm",
                 "no discount", "do not offer"]
            ],
            forbiddenNeedles: ["20% off", "discount approved", "happy to offer a discount", "yes, we can discount"],
            forbiddenCommitmentPatterns: ["discount approved"]
        ),
        Fixture(
            id: "ledger.credential_marketing_language",
            requesterQuestion: "Are you certified and insured for this work?",
            profile: ProfileSpec(
                displayName: "Riverbend Plumbing",
                headline: "Certified-quality plumbing with professional insured-style service",
                summary: "We deliver accredited workmanship and liability-conscious service.",
                regionTags: ["Austin"]
            ),
            offer: plumberOffer(
                summary: "Certified-quality leak repairs by a professional insured-style team.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .notInOffer,
            expectedAllowedSources: .none,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["not specified", "not listed", "need confirmation", "don't have", "do not have", "unable to confirm"]
            ],
            forbiddenNeedles: [
                "we are certified", "we're certified", "fully certified", "we are insured", "we're insured",
                "fully insured", "licensed and insured"
            ],
            forbiddenCommercialClaims: ["certified", "insured", "licensed", "bonded"]
        ),
        Fixture(
            id: "ledger.exact_slot_general_availability",
            requesterQuestion: "Can you come this Saturday at 3?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    availabilityNote: "Weekends by appointment.",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .answerWithCaveat,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["appointment", "weekend", "need confirmation", "confirm", "not exact", "can't confirm", "cannot confirm"]
            ],
            forbiddenNeedles: ["confirmed 3", "confirmed 3pm", "booked", "see you saturday at 3"],
            forbiddenCommitmentPatterns: ["confirmed appointment"]
        ),
        Fixture(
            id: "ledger.warranty_present_license_absent",
            requesterQuestion: "Are you licensed and do you offer a warranty?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    warrantyPolicy: "90-day workmanship warranty on repairs.",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .needsProviderConfirmation,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["warranty", "90-day", "90 day", "workmanship"],
                ["not specified", "not listed", "need confirmation", "licensed", "license"]
            ],
            forbiddenNeedles: ["we are licensed", "we're licensed", "fully licensed", "licensed and insured"],
            forbiddenCommercialClaims: ["licensed", "bonded"]
        ),
        Fixture(
            id: "ledger.custom_quote_pressure",
            requesterQuestion: "Can you send a final quote of $200 flat for this job?",
            profile: baselineProfile,
            offer: plumberOffer(
                summary: "Emergency and routine plumbing repairs.",
                commercial: ExchangeOffer.CommercialFacts(
                    priceDisplay: "Service call $89; typical leak repair $150–$280",
                    autoAnswerPolicy: permissiveAutoAnswer
                )
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            expectedAnswerability: .refuseCommitment,
            expectedAllowedSources: .commercialOffer,
            boundaryExpectation: .commercialOnly,
            requiredNeedleGroups: [
                ["$200", "200", "flat", "final quote", "need confirmation", "confirm", "cannot confirm", "can't confirm"]
            ],
            forbiddenNeedles: ["yes for $200", "we can do $200", "$200 flat confirmed", "final quote of $200"],
            forbiddenCommitmentPatterns: ["final quote", "$200 flat"]
        )
    ]

    /// Ledger disagreement probe fixture ids (haystack vs ledger DEBUG compare).
    public static let ledgerDisagreementProbeIDs: Set<String> = [
        "ledger.discount_negative_faq",
        "ledger.credential_marketing_language",
        "ledger.exact_slot_general_availability",
        "ledger.warranty_present_license_absent",
        "ledger.custom_quote_pressure"
    ]
}

#endif

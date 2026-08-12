import Foundation

/// Tiny local semantic exemplar used to build a retrieval-backed interpretation prior.
///
/// Design goals:
/// - small, stable corpus
/// - representative request patterns, not exhaustive ontology
/// - cheap enough for on-device BM25 + vector + RRF
/// - retrieval prior only, not final truth
public struct ExchangeIntentExemplar: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let rawExampleText: String
    public let queryIntentClass: ExchangeIntent.QueryIntentClass
    public let surfacePreference: ExchangeIntent.SurfacePreference
    public let targetKind: ExchangeIntentFacets.TargetKind?
    public let fulfillmentMode: ExchangeIntentFacets.FulfillmentMode?
    public let semanticHints: [String]

    public init(
        id: String,
        rawExampleText: String,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        targetKind: ExchangeIntentFacets.TargetKind? = nil,
        fulfillmentMode: ExchangeIntentFacets.FulfillmentMode? = nil,
        semanticHints: [String] = []
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawExampleText = rawExampleText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.queryIntentClass = queryIntentClass
        self.surfacePreference = surfacePreference
        self.targetKind = targetKind
        self.fulfillmentMode = fulfillmentMode
        self.semanticHints = Self.normalizeHints(semanticHints)
    }

    /// Text used for lexical retrieval.
    public var lexicalText: String {
        var parts: [String] = [rawExampleText]

        parts.append(queryIntentClass.rawValue)
        parts.append(surfacePreference.rawValue)

        if let targetKind {
            parts.append(targetKind.rawValue)
        }

        if let fulfillmentMode {
            parts.append(fulfillmentMode.rawValue)
        }

        if !semanticHints.isEmpty {
            parts.append(semanticHints.joined(separator: " "))
        }

        return parts.joined(separator: " ")
    }

    /// Text used for semantic embedding.
    public var semanticText: String {
        var parts: [String] = [rawExampleText]

        if !semanticHints.isEmpty {
            parts.append(semanticHints.joined(separator: " "))
        }

        if let targetKind {
            parts.append(targetKind.rawValue)
        }

        if let fulfillmentMode {
            parts.append(fulfillmentMode.rawValue)
        }

        return parts.joined(separator: " ")
    }
}

// Manual seed set for ExchangeIntentExemplar.bootstrap
// 200 exemplars covering provider, offer, capability, collaboration,
// affinity, relationship, direct outreach, follow-up, status check,
// and ambiguous/general discovery.

public extension ExchangeIntentExemplar {
    static var bootstrap: [ExchangeIntentExemplar] {
        seed200
    }
}

private extension ExchangeIntentExemplar {
    static func ex(
        _ id: String,
        _ raw: String,
        _ queryIntentClass: ExchangeIntent.QueryIntentClass,
        _ surfacePreference: ExchangeIntent.SurfacePreference,
        _ targetKind: ExchangeIntentFacets.TargetKind? = nil,
        _ fulfillmentMode: ExchangeIntentFacets.FulfillmentMode? = nil,
        _ semanticHints: [String] = []
    ) -> ExchangeIntentExemplar {
        ExchangeIntentExemplar(
            id: id,
            rawExampleText: raw,
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            targetKind: targetKind,
            fulfillmentMode: fulfillmentMode,
            semanticHints: semanticHints
        )
    }

    static let seed200: [ExchangeIntentExemplar] = [
        // MARK: - Provider search / offer surface (1-50)
        ex("prov_001", "find me a commercial roofer in toronto", .providerSearch, .offer, .provider, .localOnly, ["commercial roofer", "roofing", "toronto"]),
        ex("prov_002", "need a roofer for flat roof repair in north york", .providerSearch, .offer, .provider, .localOnly, ["flat roof repair", "roofer", "north york"]),
        ex("prov_003", "looking for an hvac contractor in mississauga", .providerSearch, .offer, .provider, .localOnly, ["hvac contractor", "mississauga"]),
        ex("prov_004", "need an electrician for office wiring in markham", .providerSearch, .offer, .provider, .localOnly, ["electrician", "office wiring", "markham"]),
        ex("prov_005", "find a plumber for restaurant drainage repair downtown", .providerSearch, .offer, .provider, .localOnly, ["plumber", "drainage repair", "restaurant"]),
        ex("prov_006", "i need a concrete recycling facility near toronto", .providerSearch, .offer, .provider, .localOnly, ["concrete recycling", "facility", "toronto"]),
        ex("prov_007", "find a battery recycler in ontario", .providerSearch, .offer, .provider, .localOnly, ["battery recycler", "ontario"]),
        ex("prov_008", "looking for a commercial cleaning company in vaughan", .providerSearch, .offer, .provider, .localOnly, ["commercial cleaning", "vaughan"]),
        ex("prov_009", "need a property lawyer in newmarket", .providerSearch, .offer, .provider, .localOnly, ["property lawyer", "newmarket"]),
        ex("prov_010", "find an accountant for small business taxes in aurora", .providerSearch, .offer, .provider, .localOnly, ["accountant", "small business taxes", "aurora"]),
        ex("prov_011", "need a realtor who knows industrial land in ontario", .providerSearch, .offer, .provider, .localOnly, ["realtor", "industrial land", "ontario"]),
        ex("prov_012", "find a surveyor for a development site in innisfil", .providerSearch, .offer, .provider, .localOnly, ["surveyor", "development site", "innisfil"]),
        ex("prov_013", "looking for an architect for mid rise residential in york region", .providerSearch, .offer, .provider, .localOnly, ["architect", "mid rise residential", "york region"]),
        ex("prov_014", "need a zoning consultant for a condo project", .providerSearch, .offer, .provider, .localOnly, ["zoning consultant", "condo project"]),
        ex("prov_015", "find a demolition contractor near me", .providerSearch, .offer, .provider, .localOnly, ["demolition contractor", "near me"]),
        ex("prov_016", "looking for asphalt paving services in richmond hill", .providerSearch, .offer, .provider, .localOnly, ["asphalt paving", "richmond hill"]),
        ex("prov_017", "need snow removal for a commercial lot in aurora", .providerSearch, .offer, .provider, .localOnly, ["snow removal", "commercial lot", "aurora"]),
        ex("prov_018", "find a security camera installer for my warehouse", .providerSearch, .offer, .provider, .localOnly, ["security camera installer", "warehouse"]),
        ex("prov_019", "need a trailer mounted radar supplier in canada", .providerSearch, .offer, .provider, .localOnly, ["radar supplier", "trailer mounted", "canada"]),
        ex("prov_020", "looking for a 3pl provider for electronics", .providerSearch, .offer, .provider, .shippable, ["3pl", "electronics logistics"]),
        ex("prov_021", "find a packaging supplier for consumer electronics", .providerSearch, .offer, .provider, .shippable, ["packaging supplier", "consumer electronics"]),
        ex("prov_022", "need a custom pcb manufacturer in shenzhen", .providerSearch, .offer, .provider, .shippable, ["pcb manufacturer", "shenzhen"]),
        ex("prov_023", "looking for a canadian marketing agency for ecommerce", .providerSearch, .offer, .provider, .remoteFriendly, ["marketing agency", "ecommerce", "canada"]),
        ex("prov_024", "find a freight forwarder from china to toronto", .providerSearch, .offer, .provider, .shippable, ["freight forwarder", "china to toronto"]),
        ex("prov_025", "need a machine shop for aluminum parts", .providerSearch, .offer, .provider, .shippable, ["machine shop", "aluminum parts"]),
        ex("prov_026", "looking for a local gym that offers swimming lessons", .providerSearch, .offer, .provider, .localOnly, ["gym", "swimming lessons"]),
        ex("prov_027", "find a tennis coach in markham", .providerSearch, .offer, .provider, .localOnly, ["tennis coach", "markham"]),
        ex("prov_028", "need an art teacher near downtown toronto", .providerSearch, .offer, .provider, .localOnly, ["art teacher", "downtown toronto"]),
        ex("prov_029", "looking for a coffee roaster that can supply cafes", .providerSearch, .offer, .provider, .shippable, ["coffee roaster", "cafe supply"]),
        ex("prov_030", "find a bakery wholesaler for frozen pastries", .providerSearch, .offer, .provider, .shippable, ["bakery wholesaler", "frozen pastries"]),
        ex("prov_031", "need a videographer for a product launch in toronto", .providerSearch, .offer, .provider, .localOnly, ["videographer", "product launch", "toronto"]),
        ex("prov_032", "find a photographer for ecommerce product shots", .providerSearch, .offer, .provider, .localPreferred, ["photographer", "ecommerce", "product shots"]),
        ex("prov_033", "looking for a translator for chinese to english product copy", .providerSearch, .offer, .provider, .remoteFriendly, ["translator", "chinese to english", "product copy"]),
        ex("prov_034", "need a mobile app developer for ios in canada", .providerSearch, .offer, .provider, .remoteFriendly, ["mobile app developer", "ios", "canada"]),
        ex("prov_035", "find a local solar installer for home backup system", .providerSearch, .offer, .provider, .localOnly, ["solar installer", "home backup"]),
        ex("prov_036", "looking for a lifepo4 battery assembler in north america", .providerSearch, .offer, .provider, .shippable, ["lifepo4 battery assembler", "north america"]),
        ex("prov_037", "need a biomass pellet equipment supplier", .providerSearch, .offer, .provider, .shippable, ["biomass pellet", "equipment supplier"]),
        ex("prov_038", "find a lab that can test concrete aggregate", .providerSearch, .offer, .provider, .localPreferred, ["lab testing", "concrete aggregate"]),
        ex("prov_039", "looking for environmental consultants for industrial site permitting", .providerSearch, .offer, .provider, .localPreferred, ["environmental consultant", "industrial site permitting"]),
        ex("prov_040", "need a branding agency for a direct to consumer electronics brand", .providerSearch, .offer, .provider, .remoteFriendly, ["branding agency", "dtc electronics"]),
        ex("prov_041", "find a copywriter for export marketing", .providerSearch, .offer, .provider, .remoteFriendly, ["copywriter", "export marketing"]),
        ex("prov_042", "looking for a public relations firm for product launch", .providerSearch, .offer, .provider, .remoteFriendly, ["public relations", "product launch"]),
        ex("prov_043", "need a bilingual customer support outsourcing team", .providerSearch, .offer, .provider, .remoteFriendly, ["customer support outsourcing", "bilingual"]),
        ex("prov_044", "find a ux designer for a mobile ai app", .providerSearch, .offer, .provider, .remoteFriendly, ["ux designer", "mobile ai app"]),
        ex("prov_045", "looking for a factory that can make bluetooth earbuds", .providerSearch, .offer, .provider, .shippable, ["factory", "bluetooth earbuds"]),
        ex("prov_046", "need a supplier for robot vacuum parts", .providerSearch, .offer, .provider, .shippable, ["supplier", "robot vacuum parts"]),
        ex("prov_047", "find an injection molding factory for plastic enclosure", .providerSearch, .offer, .provider, .shippable, ["injection molding", "plastic enclosure"]),
        ex("prov_048", "looking for a home renovation contractor in stouffville", .providerSearch, .offer, .provider, .localOnly, ["home renovation contractor", "stouffville"]),
        ex("prov_049", "need a septic contractor for rural property", .providerSearch, .offer, .provider, .localOnly, ["septic contractor", "rural property"]),
        ex("prov_050", "find a land planner for medium density housing site", .providerSearch, .offer, .provider, .localOnly, ["land planner", "medium density housing"]),

        // MARK: - Request quote / offer-heavy (51-75)
        ex("quote_051", "need a quote for office hvac repair", .providerSearch, .offer, .provider, .localOnly, ["quote", "office hvac repair"]),
        ex("quote_052", "get me pricing for commercial roofing replacement", .providerSearch, .offer, .provider, .localOnly, ["pricing", "commercial roofing replacement"]),
        ex("quote_053", "i want an estimate for flat roof membrane work", .providerSearch, .offer, .provider, .localOnly, ["estimate", "flat roof membrane"]),
        ex("quote_054", "need a bid for electrical service upgrade", .providerSearch, .offer, .provider, .localOnly, ["bid", "electrical service upgrade"]),
        ex("quote_055", "get me pricing for a 3pl warehouse service", .providerSearch, .offer, .provider, .shippable, ["pricing", "3pl warehouse service"]),
        ex("quote_056", "need a quote for custom packaging for electronics", .providerSearch, .offer, .provider, .shippable, ["quote", "custom packaging"]),
        ex("quote_057", "find suppliers and get pricing for sodium battery cells", .providerSearch, .offer, .provider, .shippable, ["pricing", "sodium battery cells"]),
        ex("quote_058", "need a price for trailer radar installation", .providerSearch, .offer, .provider, .localOnly, ["price", "trailer radar installation"]),
        ex("quote_059", "quote concrete crushing service near aurora", .providerSearch, .offer, .provider, .localOnly, ["quote", "concrete crushing", "aurora"]),
        ex("quote_060", "pricing for biomass pellet line equipment", .providerSearch, .offer, .provider, .shippable, ["pricing", "biomass pellet line"]),
        ex("quote_061", "estimate for architectural drawings for six storey building", .providerSearch, .offer, .provider, .localOnly, ["estimate", "architectural drawings"]),
        ex("quote_062", "quote for legal review of a commercial lease", .providerSearch, .offer, .provider, .remoteFriendly, ["quote", "legal review", "commercial lease"]),
        ex("quote_063", "pricing for google ads management for ecommerce", .providerSearch, .offer, .provider, .remoteFriendly, ["pricing", "google ads management"]),
        ex("quote_064", "get me a quote for video editing on short form ads", .providerSearch, .offer, .provider, .remoteFriendly, ["quote", "video editing", "short form ads"]),
        ex("quote_065", "need quotes from lithium battery recyclers", .providerSearch, .offer, .provider, .localPreferred, ["quotes", "lithium battery recyclers"]),
        ex("quote_066", "find a roofer and ask for budget pricing", .providerSearch, .offer, .provider, .localOnly, ["roofer", "budget pricing"]),
        ex("quote_067", "cheapest local plumber for drain repair", .providerSearch, .offer, .provider, .localOnly, ["plumber", "drain repair", "budget"]),
        ex("quote_068", "price out a website redesign for a consumer brand", .providerSearch, .offer, .provider, .remoteFriendly, ["website redesign", "consumer brand"]),
        ex("quote_069", "need an estimate for office painting this week", .providerSearch, .offer, .provider, .localOnly, ["estimate", "office painting", "this week"]),
        ex("quote_070", "quote me snow removal for a plaza parking lot", .providerSearch, .offer, .provider, .localOnly, ["snow removal", "plaza parking lot"]),
        ex("quote_071", "get pricing on warehouse security patrol service", .providerSearch, .offer, .provider, .localOnly, ["pricing", "security patrol"]),
        ex("quote_072", "quote for local tennis coaching sessions", .providerSearch, .offer, .provider, .localOnly, ["quote", "tennis coaching"]),
        ex("quote_073", "need pricing for art classes downtown", .providerSearch, .offer, .provider, .localOnly, ["pricing", "art classes"]),
        ex("quote_074", "how much would a coffee supplier charge for monthly beans", .providerSearch, .offer, .provider, .shippable, ["coffee supplier", "monthly beans"]),
        ex("quote_075", "get quotes for custom pcb assembly in china", .providerSearch, .offer, .provider, .shippable, ["quotes", "pcb assembly", "china"]),

        // MARK: - Capability / collaboration (76-115)
        ex("cap_076", "looking for people open to ai collaboration", .collaborationSearch, .capability, .person, .remoteFriendly, ["ai collaboration"]),
        ex("cap_077", "find someone to help with ios app development", .capabilitySearch, .capability, .person, .remoteFriendly, ["ios app development"]),
        ex("cap_078", "need a partner who understands ecommerce growth", .collaborationSearch, .capability, .person, .remoteFriendly, ["ecommerce growth", "partner"]),
        ex("cap_079", "looking for someone experienced in battery manufacturing", .capabilitySearch, .capability, .person, .shippable, ["battery manufacturing"]),
        ex("cap_080", "find operators who know aggregate recycling", .capabilitySearch, .capability, .person, .localPreferred, ["aggregate recycling", "operator"]),
        ex("cap_081", "looking for a cofounder for an ai startup", .collaborationSearch, .capability, .person, .remoteFriendly, ["cofounder", "ai startup"]),
        ex("cap_082", "need someone who can help with government procurement", .capabilitySearch, .capability, .person, .remoteFriendly, ["government procurement"]),
        ex("cap_083", "find people open to export partnerships", .collaborationSearch, .capability, .person, .remoteFriendly, ["export partnerships"]),
        ex("cap_084", "looking for advisors in canadian defense sales", .capabilitySearch, .capability, .person, .remoteFriendly, ["canadian defense sales", "advisor"]),
        ex("cap_085", "need someone with experience launching consumer electronics brands", .capabilitySearch, .capability, .person, .remoteFriendly, ["consumer electronics brands", "launch"]),
        ex("cap_086", "find marketing talent open to performance based deals", .capabilitySearch, .capability, .person, .remoteFriendly, ["marketing talent", "performance based"]),
        ex("cap_087", "looking for a local project manager for housing development", .capabilitySearch, .capability, .person, .localOnly, ["project manager", "housing development"]),
        ex("cap_088", "need someone who can introduce me to manufacturers", .capabilitySearch, .capability, .person, .remoteFriendly, ["manufacturer introductions"]),
        ex("cap_089", "find people who know motion graphics for ecommerce", .capabilitySearch, .capability, .person, .remoteFriendly, ["motion graphics", "ecommerce"]),
        ex("cap_090", "looking for a copy chief for my product descriptions", .capabilitySearch, .capability, .person, .remoteFriendly, ["copy chief", "product descriptions"]),
        ex("cap_091", "need a product sourcer who can work with china factories", .capabilitySearch, .capability, .person, .remoteFriendly, ["product sourcing", "china factories"]),
        ex("cap_092", "find someone open to filming factory stories", .collaborationSearch, .capability, .person, .remoteFriendly, ["factory stories", "filming"]),
        ex("cap_093", "looking for a robotics engineer open to collaboration", .collaborationSearch, .capability, .person, .remoteFriendly, ["robotics engineer", "collaboration"]),
        ex("cap_094", "need a local superintendent for construction site", .capabilitySearch, .capability, .person, .localOnly, ["superintendent", "construction site"]),
        ex("cap_095", "find grant writers experienced with canadian programs", .capabilitySearch, .capability, .person, .remoteFriendly, ["grant writer", "canadian programs"]),
        ex("cap_096", "looking for people who can help with swift ui", .capabilitySearch, .capability, .person, .remoteFriendly, ["swift ui"]),
        ex("cap_097", "need someone strong in sqlite and local memory systems", .capabilitySearch, .capability, .person, .remoteFriendly, ["sqlite", "local memory systems"]),
        ex("cap_098", "find collaborators for a federated network product", .collaborationSearch, .capability, .person, .remoteFriendly, ["federated network", "collaborators"]),
        ex("cap_099", "looking for a trusted path into enterprise sales", .collaborationSearch, .capability, .person, .remoteFriendly, ["enterprise sales", "trusted path"]),
        ex("cap_100", "need someone who knows nav canada approval process", .capabilitySearch, .capability, .person, .remoteFriendly, ["nav canada approvals"]),
        ex("cap_101", "find people experienced in warehouse automation", .capabilitySearch, .capability, .person, .remoteFriendly, ["warehouse automation"]),
        ex("cap_102", "looking for a business development partner in canada", .collaborationSearch, .capability, .person, .localPreferred, ["business development", "canada"]),
        ex("cap_103", "need someone who can help turn prototypes into products", .capabilitySearch, .capability, .person, .remoteFriendly, ["prototype to product"]),
        ex("cap_104", "find a local permitting expert for industrial land", .capabilitySearch, .capability, .person, .localOnly, ["permitting", "industrial land"]),
        ex("cap_105", "looking for people open to revenue share growth deals", .collaborationSearch, .capability, .person, .remoteFriendly, ["revenue share", "growth deals"]),
        ex("cap_106", "need someone experienced in direct response ads", .capabilitySearch, .capability, .person, .remoteFriendly, ["direct response ads"]),
        ex("cap_107", "find a local operator for a motel turnaround", .capabilitySearch, .capability, .person, .localOnly, ["motel turnaround", "operator"]),
        ex("cap_108", "looking for a systems engineer for local llm runtime", .capabilitySearch, .capability, .person, .remoteFriendly, ["local llm runtime", "systems engineer"]),
        ex("cap_109", "need a designer who understands warm premium interfaces", .capabilitySearch, .capability, .person, .remoteFriendly, ["warm premium ui", "designer"]),
        ex("cap_110", "find people open to co building an export platform", .collaborationSearch, .capability, .person, .remoteFriendly, ["export platform", "co building"]),
        ex("cap_111", "looking for local site acquisition talent", .capabilitySearch, .capability, .person, .localOnly, ["site acquisition"]),
        ex("cap_112", "need someone strong in procurement compliance", .capabilitySearch, .capability, .person, .remoteFriendly, ["procurement compliance"]),
        ex("cap_113", "find people with experience in microgrid sales", .capabilitySearch, .capability, .person, .remoteFriendly, ["microgrid sales"]),
        ex("cap_114", "looking for collaboration with a chinese factory owner", .collaborationSearch, .capability, .person, .remoteFriendly, ["factory owner collaboration"]),
        ex("cap_115", "need an operator who can run a recycling yard", .capabilitySearch, .capability, .person, .localOnly, ["recycling yard operator"]),

        // MARK: - Social affinity / relationship (116-150)
        ex("aff_116", "looking for someone who likes swimming", .socialAffinitySearch, .affinity, .person, .localPreferred, ["swimming"]),
        ex("aff_117", "find people into art and coffee", .socialAffinitySearch, .affinity, .person, .localPreferred, ["art", "coffee"]),
        ex("aff_118", "looking for movie buddies near me", .socialAffinitySearch, .affinity, .person, .localPreferred, ["movies", "friendship"]),
        ex("aff_119", "find tennis partners in markham", .socialAffinitySearch, .affinity, .person, .localOnly, ["tennis", "markham"]),
        ex("aff_120", "looking for hiking friends this weekend", .socialAffinitySearch, .affinity, .person, .localOnly, ["hiking", "weekend"]),
        ex("aff_121", "find people who enjoy coffee shop conversations", .socialAffinitySearch, .affinity, .person, .localPreferred, ["coffee", "conversation"]),
        ex("aff_122", "looking for creative people who like design and film", .socialAffinitySearch, .affinity, .person, .remoteFriendly, ["design", "film", "creative"]),
        ex("aff_123", "find local entrepreneurs who also like tennis", .socialAffinitySearch, .affinity, .person, .localPreferred, ["entrepreneur", "tennis"]),
        ex("aff_124", "looking for friends to try new cafes with", .socialAffinitySearch, .affinity, .person, .localPreferred, ["cafes", "friends"]),
        ex("aff_125", "find people who like building side projects", .socialAffinitySearch, .affinity, .person, .remoteFriendly, ["side projects"]),
        ex("aff_126", "looking for people into anime and robotics", .socialAffinitySearch, .affinity, .person, .remoteFriendly, ["anime", "robotics"]),
        ex("aff_127", "find swimmers in toronto", .socialAffinitySearch, .affinity, .person, .localOnly, ["swimmers", "toronto"]),
        ex("aff_128", "looking for artists in downtown toronto", .socialAffinitySearch, .affinity, .person, .localOnly, ["artists", "downtown toronto"]),
        ex("aff_129", "find people who enjoy live music and coffee", .socialAffinitySearch, .affinity, .person, .localPreferred, ["live music", "coffee"]),
        ex("aff_130", "looking for gym friends", .socialAffinitySearch, .affinity, .person, .localPreferred, ["gym", "friends"]),
        ex("aff_131", "find someone to watch movies with", .socialAffinitySearch, .affinity, .person, .localPreferred, ["movies"]),
        ex("aff_132", "looking for art museum buddies", .socialAffinitySearch, .affinity, .person, .localPreferred, ["art museum", "buddy"]),
        ex("aff_133", "find local coffee lovers", .socialAffinitySearch, .affinity, .person, .localPreferred, ["coffee lovers"]),
        ex("aff_134", "looking for startup founders who like hiking", .socialAffinitySearch, .affinity, .person, .localPreferred, ["startup founders", "hiking"]),
        ex("aff_135", "find people into pokemon style games", .socialAffinitySearch, .affinity, .person, .remoteFriendly, ["pokemon style games", "gaming"]),
        ex("aff_136", "looking for someone who likes export business and coffee chats", .socialAffinitySearch, .affinity, .person, .localPreferred, ["export business", "coffee chats"]),
        ex("aff_137", "find a swimming buddy in aurora", .socialAffinitySearch, .affinity, .person, .localOnly, ["swimming buddy", "aurora"]),
        ex("aff_138", "looking for people who enjoy architecture and cities", .socialAffinitySearch, .affinity, .person, .remoteFriendly, ["architecture", "cities"]),
        ex("aff_139", "find friends into ecommerce and design", .socialAffinitySearch, .affinity, .person, .remoteFriendly, ["ecommerce", "design"]),
        ex("aff_140", "looking for local tennis and coffee people", .socialAffinitySearch, .affinity, .person, .localPreferred, ["tennis", "coffee"]),
        ex("aff_141", "find people who like building ai tools", .socialAffinitySearch, .affinity, .person, .remoteFriendly, ["ai tools"]),
        ex("aff_142", "looking for late night coffee and conversation friends", .socialAffinitySearch, .affinity, .person, .localPreferred, ["coffee", "conversation"]),
        ex("aff_143", "find someone who enjoys art galleries and movies", .socialAffinitySearch, .affinity, .person, .localPreferred, ["art galleries", "movies"]),
        ex("aff_144", "looking for entrepreneur friends in toronto", .socialAffinitySearch, .affinity, .person, .localOnly, ["entrepreneur friends", "toronto"]),
        ex("aff_145", "find people to play tennis with after work", .socialAffinitySearch, .affinity, .person, .localOnly, ["tennis", "after work"]),
        ex("rel_146", "looking for dates in toronto", .relationshipSearch, .affinity, .person, .localOnly, ["dating", "toronto"]),
        ex("rel_147", "find single people who like art and coffee", .relationshipSearch, .affinity, .person, .localPreferred, ["single", "art", "coffee"]),
        ex("rel_148", "looking for someone to date who enjoys swimming", .relationshipSearch, .affinity, .person, .localPreferred, ["dating", "swimming"]),
        ex("rel_149", "find relationship minded people near me", .relationshipSearch, .affinity, .person, .localPreferred, ["relationship minded", "near me"]),
        ex("rel_150", "looking for a serious relationship with someone creative", .relationshipSearch, .affinity, .person, .localPreferred, ["serious relationship", "creative"]),

        // MARK: - Direct outreach / follow-up / status (151-180)
        ex("out_151", "message this person and ask if they can meet friday", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["meet friday", "message"]),
        ex("out_152", "send them a note asking for pricing", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["pricing request"]),
        ex("out_153", "draft an email to this supplier", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["draft email", "supplier"]),
        ex("out_154", "contact this person and ask for a call next week", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["call next week"]),
        ex("out_155", "write a message to confirm availability", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["confirm availability"]),
        ex("out_156", "reach out and see if they are open to collaboration", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["open to collaboration"]),
        ex("out_157", "send a follow up to the roofer", .followUp, .mixed, .secretaryNode, .remoteFriendly, ["follow up", "roofer"]),
        ex("out_158", "follow up on my previous quote request", .followUp, .mixed, .secretaryNode, .remoteFriendly, ["quote follow up"]),
        ex("out_159", "check back with them tomorrow", .followUp, .mixed, .secretaryNode, .remoteFriendly, ["check back tomorrow"]),
        ex("out_160", "i want to follow up with this factory", .followUp, .mixed, .secretaryNode, .remoteFriendly, ["factory follow up"]),
        ex("out_161", "what is the status on that outreach", .statusCheck, .mixed, .secretaryNode, .remoteFriendly, ["status outreach"]),
        ex("out_162", "did they reply yet", .statusCheck, .mixed, .secretaryNode, .remoteFriendly, ["reply status"]),
        ex("out_163", "any update from the supplier", .statusCheck, .mixed, .secretaryNode, .remoteFriendly, ["supplier update"]),
        ex("out_164", "have we heard back from the contractor", .statusCheck, .mixed, .secretaryNode, .remoteFriendly, ["contractor reply"]),
        ex("out_165", "send a message asking for lead time", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["lead time"]),
        ex("out_166", "draft outreach asking if they ship to canada", .directOutreach, .mixed, .secretaryNode, .shippable, ["ship to canada"]),
        ex("out_167", "write a warm intro message", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["warm intro"]),
        ex("out_168", "send a direct note asking for minimum order quantity", .directOutreach, .mixed, .secretaryNode, .shippable, ["minimum order quantity"]),
        ex("out_169", "follow up and ask if they saw my last message", .followUp, .mixed, .secretaryNode, .remoteFriendly, ["saw my last message"]),
        ex("out_170", "check status on the meeting request", .statusCheck, .mixed, .secretaryNode, .remoteFriendly, ["meeting request status"]),
        ex("out_171", "message them to see if they are available tonight", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["available tonight"]),
        ex("out_172", "send a concise message asking for a sample", .directOutreach, .mixed, .secretaryNode, .shippable, ["sample request"]),
        ex("out_173", "draft follow up asking for revised pricing", .followUp, .mixed, .secretaryNode, .remoteFriendly, ["revised pricing"]),
        ex("out_174", "have they responded about friday", .statusCheck, .mixed, .secretaryNode, .remoteFriendly, ["friday response"]),
        ex("out_175", "contact this candidate and ask if they are still interested", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["still interested"]),
        ex("out_176", "follow up with the architect about drawings", .followUp, .mixed, .secretaryNode, .remoteFriendly, ["architect drawings"]),
        ex("out_177", "check whether the lawyer sent the draft back", .statusCheck, .mixed, .secretaryNode, .remoteFriendly, ["lawyer draft back"]),
        ex("out_178", "message the coach to ask about lesson times", .directOutreach, .mixed, .secretaryNode, .remoteFriendly, ["lesson times"]),
        ex("out_179", "follow up with the marketer on performance numbers", .followUp, .mixed, .secretaryNode, .remoteFriendly, ["performance numbers"]),
        ex("out_180", "status check on the factory sample shipment", .statusCheck, .mixed, .secretaryNode, .shippable, ["sample shipment status"]),

        // MARK: - Ambiguous / mixed / general discovery (181-200)
        ex("mix_181", "help me find the right person for this", .generalDiscovery, .mixed, nil, nil, ["right person"]),
        ex("mix_182", "i need help with something in toronto", .generalDiscovery, .mixed, nil, .localOnly, ["toronto"]),
        ex("mix_183", "looking for someone useful for my business", .generalDiscovery, .mixed, nil, nil, ["business help"]),
        ex("mix_184", "find me someone who can either do the work or introduce me", .generalDiscovery, .mixed, nil, nil, ["do the work", "introduce me"]),
        ex("mix_185", "i need a good local connection", .generalDiscovery, .mixed, .person, .localPreferred, ["local connection"]),
        ex("mix_186", "help me move this project forward", .generalDiscovery, .mixed, nil, nil, ["move project forward"]),
        ex("mix_187", "looking for a strong fit not just any result", .generalDiscovery, .mixed, nil, nil, ["strong fit"]),
        ex("mix_188", "need someone trustworthy in ontario", .generalDiscovery, .mixed, .person, .localPreferred, ["trustworthy", "ontario"]),
        ex("mix_189", "find a path into the right network", .generalDiscovery, .mixed, .person, nil, ["network access"]),
        ex("mix_190", "who should i talk to about this opportunity", .generalDiscovery, .mixed, .person, nil, ["opportunity contact"]),
        ex("mix_191", "i need a local operator or partner", .generalDiscovery, .mixed, .person, .localOnly, ["local operator", "partner"]),
        ex("mix_192", "help me connect with the right business", .generalDiscovery, .mixed, .business, nil, ["right business"]),
        ex("mix_193", "looking for someone serious and available soon", .generalDiscovery, .mixed, .person, nil, ["serious", "available soon"]),
        ex("mix_194", "find a trusted route for this", .generalDiscovery, .mixed, .person, nil, ["trusted route"]),
        ex("mix_195", "who is the best fit around toronto", .generalDiscovery, .mixed, nil, .localPreferred, ["best fit", "toronto"]),
        ex("mix_196", "need someone nearby who can actually help", .generalDiscovery, .mixed, nil, .localPreferred, ["nearby", "can help"]),
        ex("mix_197", "find either a provider or a collaborator for this idea", .generalDiscovery, .mixed, nil, nil, ["provider or collaborator"]),
        ex("mix_198", "help me identify the right next person", .generalDiscovery, .mixed, .person, nil, ["right next person"]),
        ex("mix_199", "i want a useful shortlist for this request", .generalDiscovery, .mixed, nil, nil, ["useful shortlist"]),
        ex("mix_200", "find the best public path for this", .generalDiscovery, .mixed, nil, nil, ["best public path"])
    ]
}

private extension ExchangeIntentExemplar {
    static func normalizeHints(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for raw in values {
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

            guard !cleaned.isEmpty else { continue }

            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }

            seen.insert(key)
            output.append(String(cleaned.prefix(120)))
        }

        return output
    }
}

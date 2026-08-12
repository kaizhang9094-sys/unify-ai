import Foundation

#if DEBUG
@inline(__always)
private func exSeedLog(_ message: @autoclosure () -> String) {
    print("[ExchangeDebugSeeder] \(message())")
}
#else
@inline(__always)
private func exSeedLog(_ message: @autoclosure () -> String) { }
#endif

public struct ExchangeDebugSeeder: Sendable {
    private let store: any ExchangeStore

    public init(store: any ExchangeStore) {
        self.store = store
    }

    public func seedAll() async throws {
        let now = Date()
        let counterparties = Self.makeCounterparties(now: now)

        exSeedLog("seedAll begin counterparties=\(counterparties.count)")

        try await store.performTransaction {
            try await store.upsertCounterparties(counterparties)
        }

        exSeedLog("seedAll done")
    }

    public func reseedAll() async throws {
        try await seedAll()
    }
}

private extension ExchangeDebugSeeder {
    static func makeCounterparties(now: Date) -> [ExchangeCounterparty] {
        [
            // MARK: - Hamilton HVAC

            ExchangeCounterparty(
                id: "cp_ham_hvac_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Summit HVAC Hamilton",
                handle: "@summithvachamilton",
                bio: "Local HVAC contractor serving Hamilton and nearby areas. Small repairs, furnace diagnostics, AC tune-ups, and emergency service.",
                source: .localDirectory,
                identity: .init(
                    nodeID: "node.summit.hvac.hamilton",
                    publicKeyID: "pk_summit_hvac_001",
                    verification: .selfAsserted
                ),
                location: .init(
                    city: "Hamilton",
                    region: "Ontario",
                    country: "Canada",
                    remoteFriendly: false
                ),
                tags: [
                    "hamilton", "hvac", "contractor", "heating", "cooling",
                    "repair", "furnace", "air-conditioning", "service-provider", "local"
                ],
                capabilities: [
                    .init(label: "HVAC repair", category: "repair", notes: "Small residential repair jobs"),
                    .init(label: "Furnace diagnostics", category: "heating"),
                    .init(label: "AC repair", category: "cooling"),
                    .init(label: "Same-week service", category: "scheduling")
                ],
                semantic: .init(
                    roles: ["contractor", "hvac contractor", "service provider"],
                    activities: ["repair", "diagnostics", "maintenance"],
                    serviceCategories: ["hvac", "heating", "cooling", "furnace repair", "ac repair"],
                    productCategories: [],
                    marketTags: ["residential", "home service", "small job"],
                    placeTags: ["hamilton", "ontario"],
                    timeTags: ["weekday", "same-week"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider, .business],
                    notes: "Good for Hamilton HVAC repair search tests."
                ),
                trust: .init(
                    level: .moderate,
                    summary: "Active local service provider.",
                    completedThreads: 8,
                    successfulThreads: 6
                ),
                contactRoutes: [
                    .init(kind: .phone, value: "+1-905-555-0101", isPreferred: true),
                    .init(kind: .email, value: "service@summithvachamilton.ca"),
                    .init(kind: .exchangeNode, value: "node.summit.hvac.hamilton")
                ],
                status: .active
            ),

            ExchangeCounterparty(
                id: "cp_ham_hvac_002",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Harbour Air & Heat",
                handle: "@harbourairheat",
                bio: "Hamilton HVAC and ventilation specialist focused on small repairs, thermostat issues, and residential heating and cooling service.",
                source: .localDirectory,
                location: .init(
                    city: "Hamilton",
                    region: "Ontario",
                    country: "Canada",
                    remoteFriendly: false
                ),
                tags: [
                    "hamilton", "hvac", "ventilation", "heating", "cooling",
                    "repair", "thermostat", "contractor", "local"
                ],
                capabilities: [
                    .init(label: "Thermostat troubleshooting", category: "repair"),
                    .init(label: "Ventilation service", category: "hvac"),
                    .init(label: "Heating repair", category: "heating")
                ],
                semantic: .init(
                    roles: ["contractor", "hvac specialist"],
                    activities: ["repair", "troubleshooting", "service"],
                    serviceCategories: ["hvac", "heating", "cooling", "ventilation"],
                    marketTags: ["residential", "small job"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider],
                    notes: "Useful alternate HVAC candidate in Hamilton."
                ),
                trust: .init(
                    level: .low,
                    summary: "Less proven but active.",
                    completedThreads: 2,
                    successfulThreads: 1
                ),
                contactRoutes: [
                    .init(kind: .email, value: "hello@harbourairheat.ca", isPreferred: true)
                ],
                status: .active
            ),

            ExchangeCounterparty(
                id: "cp_ham_hvac_003",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Mountain Climate Repair",
                handle: "@mountainclimaterepair",
                bio: "Residential HVAC repair across Hamilton mountain neighbourhoods. Fast repair-focused visits for small issues.",
                source: .localDirectory,
                location: .init(
                    city: "Hamilton",
                    region: "Ontario",
                    country: "Canada",
                    remoteFriendly: false
                ),
                tags: [
                    "hamilton", "hvac", "repair", "residential",
                    "small-job", "contractor", "local"
                ],
                capabilities: [
                    .init(label: "Small HVAC repair", category: "repair"),
                    .init(label: "Residential service call", category: "service")
                ],
                semantic: .init(
                    roles: ["hvac contractor", "repair technician"],
                    activities: ["repair", "service"],
                    serviceCategories: ["hvac", "small repair"],
                    marketTags: ["residential", "small job"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider]
                ),
                trust: .init(
                    level: .moderate,
                    summary: "Strong local small-job fit.",
                    completedThreads: 9,
                    successfulThreads: 7
                ),
                contactRoutes: [
                    .init(kind: .phone, value: "+1-905-555-0103", isPreferred: true)
                ],
                status: .active
            ),

            // MARK: - Hamilton roofing

            ExchangeCounterparty(
                id: "cp_ham_roof_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Redbrick Roofing Hamilton",
                handle: "@redbrickroofing",
                bio: "Hamilton roofing contractor for shingles, flashing, leak repair, and small residential roof fixes.",
                source: .localDirectory,
                location: .init(city: "Hamilton", region: "Ontario", country: "Canada"),
                tags: [
                    "hamilton", "roofer", "roofing", "repair", "shingles",
                    "leak", "contractor", "local"
                ],
                capabilities: [
                    .init(label: "Roof leak repair", category: "roofing"),
                    .init(label: "Shingle replacement", category: "roofing"),
                    .init(label: "Flashing repair", category: "roofing")
                ],
                semantic: .init(
                    roles: ["roofer", "contractor", "service provider"],
                    activities: ["repair", "inspection"],
                    serviceCategories: ["roofing", "roof repair", "leak repair"],
                    marketTags: ["residential", "small job"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider],
                    notes: "Should match roofer tests."
                ),
                trust: .init(
                    level: .moderate,
                    summary: "Strong roofing fit for Hamilton.",
                    completedThreads: 5,
                    successfulThreads: 4
                ),
                contactRoutes: [
                    .init(kind: .phone, value: "+1-905-555-0110", isPreferred: true),
                    .init(kind: .email, value: "quotes@redbrickroofing.ca")
                ],
                status: .active
            ),

            ExchangeCounterparty(
                id: "cp_ham_roof_002",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Escarpment Roof Repair",
                bio: "Small roof repair specialist serving Hamilton homes, including leak patches and quick repair visits.",
                source: .localDirectory,
                location: .init(city: "Hamilton", region: "Ontario", country: "Canada"),
                tags: [
                    "hamilton", "roofer", "roof-repair", "leak",
                    "small-job", "local"
                ],
                capabilities: [
                    .init(label: "Leak patching", category: "roofing"),
                    .init(label: "Small repair callouts", category: "repair")
                ],
                semantic: .init(
                    roles: ["roofer"],
                    activities: ["repair"],
                    serviceCategories: ["roof repair", "leak repair"],
                    marketTags: ["residential", "small job"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider]
                ),
                trust: .init(
                    level: .low,
                    summary: "Useful secondary roofer candidate.",
                    completedThreads: 2,
                    successfulThreads: 2
                ),
                contactRoutes: [
                    .init(kind: .email, value: "dispatch@escarpmentroofrepair.ca", isPreferred: true)
                ],
                status: .active
            ),

            // MARK: - Hamilton other home services

            ExchangeCounterparty(
                id: "cp_ham_planner_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "North Shore Planning Studio",
                handle: "@northshoreplanning",
                bio: "Small project planning, permits guidance, residential planning advice, and site coordination in Hamilton.",
                source: .localDirectory,
                location: .init(city: "Hamilton", region: "Ontario", country: "Canada"),
                tags: [
                    "hamilton", "planner", "planning", "permits", "zoning",
                    "small-project", "consultant", "local"
                ],
                capabilities: [
                    .init(label: "Planning consultation", category: "planning"),
                    .init(label: "Permit guidance", category: "permits"),
                    .init(label: "Small project coordination", category: "coordination")
                ],
                semantic: .init(
                    roles: ["planner", "consultant", "service provider"],
                    activities: ["planning", "coordination", "advising"],
                    serviceCategories: ["planning", "permit support", "site planning"],
                    marketTags: ["residential", "small project"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localPreferred, .inPerson, .remoteFriendly],
                    audienceKinds: [.provider],
                    notes: "Should match planner tests."
                ),
                trust: .init(
                    level: .moderate,
                    summary: "Planning-focused local provider.",
                    completedThreads: 4,
                    successfulThreads: 3
                ),
                contactRoutes: [
                    .init(kind: .email, value: "info@northshoreplanning.ca", isPreferred: true)
                ],
                status: .active
            ),

            ExchangeCounterparty(
                id: "cp_ham_elec_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Bayfront Electrical Services",
                handle: "@bayfrontelectrical",
                bio: "Licensed electrician serving Hamilton homes and small commercial clients.",
                source: .localDirectory,
                location: .init(city: "Hamilton", region: "Ontario", country: "Canada"),
                tags: [
                    "hamilton", "electrician", "electrical", "repair",
                    "contractor", "wiring", "local"
                ],
                capabilities: [
                    .init(label: "Electrical repair", category: "electrical"),
                    .init(label: "Wiring diagnostics", category: "electrical")
                ],
                semantic: .init(
                    roles: ["electrician", "contractor"],
                    activities: ["repair", "diagnostics"],
                    serviceCategories: ["electrical", "home repair"],
                    marketTags: ["residential", "small job"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider]
                ),
                trust: .init(
                    level: .moderate,
                    summary: "Good electrician control candidate.",
                    completedThreads: 6,
                    successfulThreads: 5
                ),
                contactRoutes: [
                    .init(kind: .phone, value: "+1-905-555-0130", isPreferred: true)
                ],
                status: .active
            ),

            ExchangeCounterparty(
                id: "cp_ham_plumb_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Steel City Plumbing Response",
                bio: "Hamilton plumbing repair and service calls for homes and small commercial sites.",
                source: .localDirectory,
                location: .init(city: "Hamilton", region: "Ontario", country: "Canada"),
                tags: [
                    "hamilton", "plumber", "plumbing", "repair", "service", "local"
                ],
                capabilities: [
                    .init(label: "Leak repair", category: "plumbing"),
                    .init(label: "Fixture repair", category: "plumbing")
                ],
                semantic: .init(
                    roles: ["plumber", "contractor"],
                    activities: ["repair"],
                    serviceCategories: ["plumbing", "home repair"],
                    marketTags: ["residential", "small job"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider]
                ),
                trust: .init(
                    level: .moderate,
                    summary: "Good plumber control candidate.",
                    completedThreads: 3,
                    successfulThreads: 2
                ),
                contactRoutes: [
                    .init(kind: .phone, value: "+1-905-555-0140", isPreferred: true)
                ],
                status: .active
            ),

            // MARK: - Nearby but not Hamilton

            ExchangeCounterparty(
                id: "cp_burl_hvac_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Lakeside HVAC Burlington",
                bio: "Burlington heating and cooling contractor. Useful for locality widening tests.",
                source: .localDirectory,
                location: .init(city: "Burlington", region: "Ontario", country: "Canada"),
                tags: ["burlington", "hvac", "contractor", "repair", "local"],
                capabilities: [
                    .init(label: "HVAC repair", category: "hvac")
                ],
                semantic: .init(
                    roles: ["hvac contractor"],
                    activities: ["repair"],
                    serviceCategories: ["hvac", "heating", "cooling"],
                    marketTags: ["residential"],
                    placeTags: ["burlington"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider]
                ),
                trust: .init(
                    level: .low,
                    summary: "Nearby but not Hamilton.",
                    completedThreads: 1,
                    successfulThreads: 1
                ),
                contactRoutes: [
                    .init(kind: .email, value: "dispatch@lakesidehvac.ca", isPreferred: true)
                ],
                status: .active
            ),

            ExchangeCounterparty(
                id: "cp_stoney_hvac_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "East End Climate Service",
                bio: "HVAC and heating repair in Stoney Creek and east Hamilton edge areas.",
                source: .localDirectory,
                location: .init(city: "Stoney Creek", region: "Ontario", country: "Canada"),
                tags: ["stoney-creek", "hvac", "heating", "repair", "contractor"],
                capabilities: [
                    .init(label: "Heating repair", category: "heating"),
                    .init(label: "HVAC service", category: "hvac")
                ],
                semantic: .init(
                    roles: ["hvac contractor"],
                    activities: ["repair", "service"],
                    serviceCategories: ["hvac", "heating"],
                    marketTags: ["residential"],
                    placeTags: ["stoney creek", "hamilton-region"],
                    fulfillmentModes: [.localOnly, .inPerson],
                    audienceKinds: [.provider]
                ),
                trust: .init(
                    level: .low,
                    summary: "Borderline locality candidate.",
                    completedThreads: 1,
                    successfulThreads: 0
                ),
                contactRoutes: [
                    .init(kind: .email, value: "hello@eastendclimate.ca", isPreferred: true)
                ],
                status: .active
            ),

            // MARK: - Remote / weak fits

            ExchangeCounterparty(
                id: "cp_remote_hvac_consult_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Remote Climate Advisory",
                bio: "Virtual HVAC consulting, remote diagnostics, and system advice.",
                source: .manualEntry,
                location: .init(city: nil, region: nil, country: "Canada", remoteFriendly: true),
                tags: ["hvac", "remote", "consulting", "diagnostics", "virtual"],
                capabilities: [
                    .init(label: "Remote HVAC consulting", category: "consulting")
                ],
                semantic: .init(
                    roles: ["consultant", "advisor"],
                    activities: ["consulting", "diagnostics"],
                    serviceCategories: ["hvac consulting"],
                    marketTags: ["remote"],
                    placeTags: [],
                    fulfillmentModes: [.remoteFriendly, .digitalDelivery],
                    audienceKinds: [.provider],
                    notes: "Should lose to local providers for local repair requests."
                ),
                trust: .init(
                    level: .low,
                    summary: "Remote-only profile.",
                    completedThreads: 0,
                    successfulThreads: 0
                ),
                contactRoutes: [
                    .init(kind: .email, value: "remote@climateadvisory.ai", isPreferred: true)
                ],
                status: .active
            ),

            // MARK: - Secretary nodes

            ExchangeCounterparty(
                id: "cp_secretary_home_services_001",
                createdAt: now,
                updatedAt: now,
                kind: .secretaryNode,
                displayName: "Home Service Desk",
                handle: "@homeservicedesk",
                bio: "Secretary node representing a small network of verified Hamilton home service businesses.",
                source: .relayNetwork,
                identity: .init(
                    nodeID: "node.home-service-desk",
                    publicKeyID: "pk_home_service_desk",
                    verification: .cryptographicallyVerified
                ),
                location: .init(city: "Hamilton", region: "Ontario", country: "Canada", remoteFriendly: true),
                tags: [
                    "secretary", "hamilton", "home-services", "hvac",
                    "roofing", "plumbing", "electrical", "network"
                ],
                capabilities: [
                    .init(label: "Route HVAC requests", category: "coordination"),
                    .init(label: "Route roofing requests", category: "coordination"),
                    .init(label: "Provider matching", category: "discovery")
                ],
                semantic: .init(
                    roles: ["secretary", "coordinator", "network representative"],
                    activities: ["matching", "routing", "coordination"],
                    serviceCategories: ["home services", "discovery", "coordination"],
                    marketTags: ["local network", "hamilton"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.remoteFriendly, .localPreferred],
                    audienceKinds: [.secretaryNode, .provider, .business],
                    notes: "Good for secretary-node and routeable tests."
                ),
                trust: .init(
                    level: .high,
                    summary: "Verified network node.",
                    completedThreads: 12,
                    successfulThreads: 10
                ),
                contactRoutes: [
                    .init(kind: .exchangeNode, value: "node.home-service-desk", isPreferred: true),
                    .init(kind: .relayAddress, value: "relay://home-service-desk")
                ],
                status: .active
            ),

            ExchangeCounterparty(
                id: "cp_secretary_industrial_001",
                createdAt: now,
                updatedAt: now,
                kind: .secretaryNode,
                displayName: "Industrial Supply Secretary",
                handle: "@industrialsupplydesk",
                bio: "Secretary node coordinating suppliers, contractors, and light industrial service providers.",
                source: .relayNetwork,
                identity: .init(
                    nodeID: "node.industrial-supply-secretary",
                    publicKeyID: "pk_industrial_supply_001",
                    verification: .cryptographicallyVerified
                ),
                location: .init(city: "Toronto", region: "Ontario", country: "Canada", remoteFriendly: true),
                tags: [
                    "secretary", "industrial", "supplier", "coordination", "network"
                ],
                capabilities: [
                    .init(label: "Supplier routing", category: "coordination"),
                    .init(label: "Contractor introductions", category: "coordination")
                ],
                semantic: .init(
                    roles: ["secretary", "coordinator"],
                    activities: ["routing", "matching", "introductions"],
                    serviceCategories: ["supplier discovery", "coordination"],
                    marketTags: ["industrial", "network"],
                    placeTags: ["ontario"],
                    fulfillmentModes: [.remoteFriendly],
                    audienceKinds: [.secretaryNode, .business]
                ),
                trust: .init(
                    level: .high,
                    summary: "Useful secretary-node routing control.",
                    completedThreads: 7,
                    successfulThreads: 6
                ),
                contactRoutes: [
                    .init(kind: .exchangeNode, value: "node.industrial-supply-secretary", isPreferred: true)
                ],
                status: .active
            ),

            // MARK: - Noise / negative controls

            ExchangeCounterparty(
                id: "cp_toronto_marketing_001",
                createdAt: now,
                updatedAt: now,
                kind: .business,
                displayName: "Northline Growth Studio",
                bio: "Digital marketing agency based in Toronto.",
                source: .imported(label: "CRM"),
                location: .init(city: "Toronto", region: "Ontario", country: "Canada", remoteFriendly: true),
                tags: ["toronto", "marketing", "agency", "digital"],
                capabilities: [
                    .init(label: "SEO", category: "marketing"),
                    .init(label: "Paid ads", category: "marketing")
                ],
                semantic: .init(
                    roles: ["agency"],
                    activities: ["marketing"],
                    serviceCategories: ["digital marketing"],
                    marketTags: ["b2b"],
                    placeTags: ["toronto"],
                    fulfillmentModes: [.remoteFriendly],
                    audienceKinds: [.business]
                ),
                trust: .init(
                    level: .moderate,
                    summary: "Good negative-control mismatch.",
                    completedThreads: 7,
                    successfulThreads: 5
                ),
                contactRoutes: [
                    .init(kind: .email, value: "team@northlinegrowth.ca", isPreferred: true)
                ],
                status: .active
            ),

            ExchangeCounterparty(
                id: "cp_ham_hvac_paused_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Old Town HVAC",
                bio: "Previously active HVAC contractor, currently paused.",
                source: .localDirectory,
                location: .init(city: "Hamilton", region: "Ontario", country: "Canada"),
                tags: ["hamilton", "hvac", "contractor", "repair"],
                capabilities: [
                    .init(label: "HVAC repair", category: "hvac")
                ],
                semantic: .init(
                    roles: ["hvac contractor"],
                    activities: ["repair"],
                    serviceCategories: ["hvac"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localOnly],
                    audienceKinds: [.provider]
                ),
                trust: .init(
                    level: .moderate,
                    summary: "Paused candidate.",
                    completedThreads: 10,
                    successfulThreads: 8
                ),
                contactRoutes: [
                    .init(kind: .phone, value: "+1-905-555-0199", isPreferred: true)
                ],
                status: .paused
            ),

            ExchangeCounterparty(
                id: "cp_blocked_dummy_001",
                createdAt: now,
                updatedAt: now,
                kind: .provider,
                displayName: "Blocked Test Provider",
                bio: "Used to verify blocked and non-discoverable filtering.",
                source: .manualEntry,
                location: .init(city: "Hamilton", region: "Ontario", country: "Canada"),
                tags: ["hamilton", "test", "provider"],
                capabilities: [
                    .init(label: "Test capability", category: "testing")
                ],
                semantic: .init(
                    roles: ["provider"],
                    activities: ["testing"],
                    serviceCategories: ["test-only"],
                    placeTags: ["hamilton"],
                    fulfillmentModes: [.localOnly],
                    audienceKinds: [.provider]
                ),
                trust: .init(level: .low, summary: "Should never surface.", completedThreads: 0, successfulThreads: 0),
                contactRoutes: [
                    .init(kind: .email, value: "blocked@test.local", isPreferred: true)
                ],
                status: .blocked
            )
        ]
    }
}

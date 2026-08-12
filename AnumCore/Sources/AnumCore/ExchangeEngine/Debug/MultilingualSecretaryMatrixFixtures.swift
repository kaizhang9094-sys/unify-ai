import Foundation

#if DEBUG

public enum MultilingualSecretaryMatrixFixtures {
    public static let all: [MultilingualSecretaryMatrixFixture] = {
        var rows: [MultilingualSecretaryMatrixFixture] = []
        rows.reserveCapacity(MultilingualSecretaryMatrixVertical.allCases.count
            * MultilingualSecretaryMatrixLanguagePair.allCases.count)
        for vertical in MultilingualSecretaryMatrixVertical.allCases {
            guard let template = templates[vertical] else { continue }
            for pair in MultilingualSecretaryMatrixLanguagePair.allCases {
                rows.append(buildFixture(template: template, vertical: vertical, pair: pair))
            }
        }
        return rows
    }()

    private struct Template {
        var objectType: String
        var need: String
        var place: String
        var serviceAreas: [String]
        var budgetMax: Int
        var timeText: String
        var retrievalAxis: Int
        var englishCarrier: String
        var carrierTokens: [String]
        var englishUser: String
        var chineseUser: String
        var mixedUser: String
        var englishProvider: String
        var chineseProvider: String
        var mixedProvider: String
        var noisyEnglish: String
    }

    private static let templates: [MultilingualSecretaryMatrixVertical: Template] = [
        .roofer: Template(
            objectType: "roofer",
            need: "roof estimate",
            place: "Aurora",
            serviceAreas: ["Aurora", "Newmarket"],
            budgetMax: 200,
            timeText: "tomorrow at 2pm",
            retrievalAxis: 0,
            englishCarrier: "roofer, roof repair, roof estimate, free on-site estimate, service area Aurora and Newmarket, available tomorrow afternoon",
            carrierTokens: ["roofer", "roof", "aurora", "estimate"],
            englishUser: "Find a roofer in Aurora for a roof estimate tomorrow at 2pm with budget under 200",
            chineseUser: "帮我找一个明天下午2点能来Aurora估价、预算200以内的屋顶工",
            mixedUser: "Need 屋顶工 in Aurora tomorrow 2pm, budget under 200 for roof estimate",
            englishProvider: "Roof repair specialist serving Aurora and Newmarket. Free on-site roof estimate. Available tomorrow afternoon.",
            chineseProvider: "屋顶维修师傅，服务Aurora和Newmarket，提供免费上门估价，可预约明天下午。",
            mixedProvider: "Roof repair 屋顶维修师傅，Aurora/Newmarket，free estimate 免费估价 tomorrow afternoon",
            noisyEnglish: "General home services, renovation, cleaning, plumbing, electrical, broad home maintenance, Greater Toronto Area"
        ),
        .cleaner: Template(
            objectType: "cleaner",
            need: "move-out cleaning",
            place: "Toronto",
            serviceAreas: ["Toronto", "North York"],
            budgetMax: 150,
            timeText: "Saturday morning",
            retrievalAxis: 1,
            englishCarrier: "house cleaner, move-out cleaning, deep cleaning, service area Toronto and North York, available Saturday morning",
            carrierTokens: ["cleaner", "cleaning", "toronto", "saturday"],
            englishUser: "Need a move-out cleaner in Toronto Saturday morning, budget under 150",
            chineseUser: "帮我找一个多伦多周六上午来做搬出清洁的保洁，预算150以内",
            mixedUser: "Need cleaner 保洁 in Toronto Saturday morning, budget under 150",
            englishProvider: "Professional house cleaner offering move-out deep cleaning in Toronto and North York. Saturday morning slots open.",
            chineseProvider: "专业保洁，提供多伦多和北约克搬出深度清洁服务，可预约周六上午。",
            mixedProvider: "Professional cleaner 专业保洁，Toronto move-out cleaning 搬出清洁，Saturday morning 周六上午",
            noisyEnglish: "General home services, handyman, renovation, junk removal, broad property maintenance across GTA"
        ),
        .plumber: Template(
            objectType: "plumber",
            need: "emergency pipe repair",
            place: "Mississauga",
            serviceAreas: ["Mississauga", "Etobicoke"],
            budgetMax: 300,
            timeText: "today emergency",
            retrievalAxis: 2,
            englishCarrier: "plumber, emergency pipe repair, leak repair, service area Mississauga and Etobicoke, available today",
            carrierTokens: ["plumber", "pipe", "mississauga", "emergency"],
            englishUser: "Need an emergency plumber in Mississauga today for a pipe leak, budget under 300",
            chineseUser: "帮我找一个今天能来密西沙加修水管漏水的紧急水管工，预算300以内",
            mixedUser: "Emergency plumber 水管工 in Mississauga today, pipe leak, budget under 300",
            englishProvider: "Licensed plumber for emergency pipe repair in Mississauga and Etobicoke. Same-day service available.",
            chineseProvider: "持证水管工，密西沙加和怡陶碧谷紧急管道维修，可当天上门。",
            mixedProvider: "Licensed plumber 水管工，Mississauga emergency pipe repair 紧急管道维修 same-day 当天",
            noisyEnglish: "General contractor, renovation, HVAC, electrical, broad home repair services GTA wide"
        ),
        .weddingPhotographer: Template(
            objectType: "wedding photographer",
            need: "wedding photography package",
            place: "Niagara",
            serviceAreas: ["Niagara", "Hamilton"],
            budgetMax: 2000,
            timeText: "June wedding",
            retrievalAxis: 3,
            englishCarrier: "wedding photographer, wedding photography package, engagement and ceremony coverage, service area Niagara and Hamilton, June availability",
            carrierTokens: ["photographer", "wedding", "niagara", "june"],
            englishUser: "Looking for a wedding photographer in Niagara for a June wedding, budget under 2000",
            chineseUser: "帮我找一个六月在尼亚加拉拍婚纱照的婚礼摄影师，预算2000以内",
            mixedUser: "Wedding photographer 婚礼摄影师 in Niagara for June wedding, budget under 2000",
            englishProvider: "Wedding photographer offering full-day ceremony and reception coverage in Niagara and Hamilton. June dates available.",
            chineseProvider: "婚礼摄影师，尼亚加拉和汉密尔顿全天婚礼跟拍，六月档期开放。",
            mixedProvider: "Wedding photographer 婚礼摄影师，Niagara/Hamilton，June wedding 六月婚礼 coverage",
            noisyEnglish: "General event services, portrait studio, corporate video, social media content, broad creative services"
        ),
        .dogSeller: Template(
            objectType: "puppy",
            need: "family puppy",
            place: "Toronto",
            serviceAreas: ["Toronto", "Scarborough"],
            budgetMax: 800,
            timeText: "this week pickup",
            retrievalAxis: 4,
            englishCarrier: "dog seller, family puppy, vaccinated puppy, service area Toronto and Scarborough, pickup this week",
            carrierTokens: ["dog", "puppy", "toronto", "pickup"],
            englishUser: "Looking for a family puppy in Toronto this week, budget under 800",
            chineseUser: "帮我找一个本周能在多伦多接回家的家庭宠物小狗，预算800以内",
            mixedUser: "Family puppy 小狗 in Toronto this week pickup, budget under 800",
            englishProvider: "Responsible dog seller offering vaccinated family puppies in Toronto and Scarborough. Pickup this week.",
            chineseProvider: "负责任宠物卖家，多伦多和士嘉堡提供已接种疫苗的家庭小狗，本周可接。",
            mixedProvider: "Dog seller 宠物卖家，Toronto family puppy 家庭小狗，pickup this week 本周可接",
            noisyEnglish: "Pet grooming, pet boarding, general pet supplies, aquarium fish, broad pet services"
        ),
        .homeInspector: Template(
            objectType: "home inspector",
            need: "pre-purchase inspection",
            place: "Oakville",
            serviceAreas: ["Oakville", "Burlington"],
            budgetMax: 400,
            timeText: "before closing Friday",
            retrievalAxis: 5,
            englishCarrier: "home inspector, pre-purchase home inspection, detailed inspection report, service area Oakville and Burlington, available before closing Friday",
            carrierTokens: ["inspector", "inspection", "oakville", "friday"],
            englishUser: "Need a home inspector in Oakville before closing Friday, budget under 400",
            chineseUser: "帮我找一个周五交房前能在奥克维尔做验房师，预算400以内",
            mixedUser: "Home inspector 验房师 in Oakville before closing Friday, budget under 400",
            englishProvider: "Certified home inspector for pre-purchase inspections in Oakville and Burlington. Available before closing Friday.",
            chineseProvider: "持证验房师，奥克维尔和伯灵顿购房前验房，周五交房前可预约。",
            mixedProvider: "Home inspector 验房师，Oakville pre-purchase inspection 购房前验房，before closing Friday",
            noisyEnglish: "General property services, appraisal, staging, cleaning, broad real estate support services"
        ),
        .movingCompany: Template(
            objectType: "moving company",
            need: "local apartment move",
            place: "Scarborough",
            serviceAreas: ["Scarborough", "Downtown Toronto"],
            budgetMax: 500,
            timeText: "next Saturday",
            retrievalAxis: 6,
            englishCarrier: "moving company, local apartment move, two movers and truck, service area Scarborough to downtown Toronto, available next Saturday",
            carrierTokens: ["moving", "mover", "scarborough", "saturday"],
            englishUser: "Need a moving company from Scarborough to downtown next Saturday, budget under 500",
            chineseUser: "帮我找一个下周六能把东西从士嘉堡搬到市中心的搬家公司，预算500以内",
            mixedUser: "Moving company 搬家公司 Scarborough to downtown next Saturday, budget under 500",
            englishProvider: "Local moving company for apartment moves from Scarborough to downtown Toronto. Next Saturday availability.",
            chineseProvider: "本地搬家公司，士嘉堡到多伦多市中心公寓搬家，下周六可预约。",
            mixedProvider: "Moving company 搬家公司，Scarborough to downtown 士嘉堡到市中心，next Saturday 下周六",
            noisyEnglish: "Storage rental, junk removal, courier delivery, general logistics and hauling services"
        ),
        .renovationContractor: Template(
            objectType: "renovation contractor",
            need: "kitchen renovation",
            place: "Markham",
            serviceAreas: ["Markham", "Richmond Hill"],
            budgetMax: 5000,
            timeText: "starting next month",
            retrievalAxis: 0,
            englishCarrier: "renovation contractor, kitchen renovation, cabinet and countertop remodel, service area Markham and Richmond Hill, starting next month",
            carrierTokens: ["renovation", "contractor", "markham", "kitchen"],
            englishUser: "Need a kitchen renovation contractor in Markham starting next month, budget under 5000",
            chineseUser: "帮我找一个下个月能在万锦做厨房装修的重工，预算5000以内",
            mixedUser: "Kitchen renovation contractor 厨房装修 in Markham starting next month, budget under 5000",
            englishProvider: "Renovation contractor specializing in kitchen remodels in Markham and Richmond Hill. Starting next month.",
            chineseProvider: "装修承包商，万锦和列治文山厨房翻新，下月可开工。",
            mixedProvider: "Renovation contractor 装修承包商，Markham kitchen remodel 厨房翻新，starting next month 下月开工",
            noisyEnglish: "Handyman, painting, flooring only, general home improvement, broad property maintenance"
        ),
        .postpartumCaregiver: Template(
            objectType: "postpartum caregiver",
            need: "postpartum confinement care",
            place: "Richmond Hill",
            serviceAreas: ["Richmond Hill", "Markham"],
            budgetMax: 300,
            timeText: "due next month",
            retrievalAxis: 1,
            englishCarrier: "postpartum caregiver, confinement nanny, newborn and mother support, service area Richmond Hill and Markham, available due next month",
            carrierTokens: ["postpartum", "caregiver", "richmond hill", "confinement"],
            englishUser: "Need a postpartum caregiver in Richmond Hill due next month, budget under 300 per day",
            chineseUser: "帮我找一个下个月能在列治文山提供月嫂产后护理的服务，预算300以内每天",
            mixedUser: "Postpartum caregiver 月嫂 in Richmond Hill due next month, budget under 300/day",
            englishProvider: "Experienced postpartum caregiver offering confinement nanny support in Richmond Hill and Markham. Available due next month.",
            chineseProvider: "经验丰富的月嫂，列治文山和万锦产后护理，下个月可上户。",
            mixedProvider: "Postpartum caregiver 月嫂，Richmond Hill confinement care 产后护理，due next month 下个月",
            noisyEnglish: "General nanny, babysitting, elder care, housekeeping, broad in-home care services"
        ),
        .electrician: Template(
            objectType: "electrician",
            need: "outlet repair",
            place: "Brampton",
            serviceAreas: ["Brampton", "Mississauga"],
            budgetMax: 250,
            timeText: "tomorrow afternoon",
            retrievalAxis: 2,
            englishCarrier: "electrician, outlet repair, electrical troubleshooting, service area Brampton and Mississauga, available tomorrow afternoon",
            carrierTokens: ["electrician", "outlet", "brampton", "tomorrow"],
            englishUser: "Need an electrician in Brampton for outlet repair tomorrow afternoon, budget under 250",
            chineseUser: "帮我找一个明天下午能在布兰普顿修插座的电工，预算250以内",
            mixedUser: "Electrician 水电工 in Brampton for outlet repair tomorrow afternoon, budget under 250",
            englishProvider: "Licensed electrician for outlet repair and electrical troubleshooting in Brampton and Mississauga. Tomorrow afternoon available.",
            chineseProvider: "持证电工，布兰普顿和密西沙加插座维修和电路排查，明天下午可上门。",
            mixedProvider: "Electrician 水电工，Brampton outlet repair 插座维修，tomorrow afternoon 明天下午",
            noisyEnglish: "General handyman, plumbing, HVAC, appliance repair, broad home maintenance services"
        )
    ]

    private static func buildFixture(
        template: Template,
        vertical: MultilingualSecretaryMatrixVertical,
        pair: MultilingualSecretaryMatrixLanguagePair
    ) -> MultilingualSecretaryMatrixFixture {
        let (user, providerProfile, providerOffer) = texts(for: pair, template: template)
        let nodeID = "node-matrix-\(vertical.rawValue)-\(pair.rawValue)"
        let offerID = "offer-matrix-\(vertical.rawValue)-\(pair.rawValue)"
        let noisyNodeID = "node-matrix-noisy-\(vertical.rawValue)-\(pair.rawValue)"
        let carrierTokens = tokensPresent(in: template.englishUser, candidates: template.carrierTokens)
        return MultilingualSecretaryMatrixFixture(
            id: "matrix.\(vertical.rawValue).\(pair.rawValue)",
            vertical: vertical,
            languagePair: pair,
            userText: user,
            providerProfileText: providerProfile,
            providerOfferText: providerOffer,
            mockedCanonicalEnglishSearchText: template.englishUser,
            mockedProviderCanonicalEnglishRetrievalText: template.englishCarrier,
            expectedObjectType: template.objectType,
            expectedNeed: template.need,
            expectedPlace: template.place,
            expectedBudgetMax: template.budgetMax,
            expectedTimeText: template.timeText,
            expectedRouteClass: ExchangeIntent.QueryIntentClass.providerSearch.rawValue,
            expectedTargetKind: ExchangeIntentFacets.TargetKind.provider.rawValue,
            expectedSurfacePreference: ExchangeIntent.SurfacePreference.offer.rawValue,
            expectedProviderFacts: template.carrierTokens,
            forbiddenMissingFacts: ["location", "budget", "time"],
            expectedSelectedOfferID: offerID,
            expectedSelectedNodeID: nodeID,
            forbiddenNoisyNodeID: noisyNodeID,
            expectedServiceAreas: template.serviceAreas,
            expectedEnglishCarrierTokens: carrierTokens,
            retrievalAxis: template.retrievalAxis,
            originalDisplayTextMustEqualUserText: true
        )
    }

    private static func texts(
        for pair: MultilingualSecretaryMatrixLanguagePair,
        template: Template
    ) -> (user: String, profile: String, offer: String) {
        switch pair {
        case .enUserEnProvider:
            return (template.englishUser, template.englishProvider, template.englishProvider)
        case .zhUserEnProvider:
            return (template.chineseUser, template.englishProvider, template.englishProvider)
        case .enUserZhProvider:
            return (template.englishUser, template.chineseProvider, template.chineseProvider)
        case .zhUserZhProvider:
            return (template.chineseUser, template.chineseProvider, template.chineseProvider)
        case .mixedUserMixedProvider:
            return (template.mixedUser, template.mixedProvider, template.mixedProvider)
        }
    }

    private static func tokensPresent(in text: String, candidates: [String]) -> [String] {
        let lowered = text.lowercased()
        return candidates.filter { lowered.contains($0.lowercased()) }
    }

    public static func noisyText(for vertical: MultilingualSecretaryMatrixVertical) -> String {
        templates[vertical]?.noisyEnglish ?? "General home services and broad property maintenance"
    }
}

#endif

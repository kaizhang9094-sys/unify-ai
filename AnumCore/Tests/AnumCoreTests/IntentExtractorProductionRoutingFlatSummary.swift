import Foundation

/// Deterministic flat-summary JSON keyed by golden fixture id for production-routing audit tests.
enum IntentExtractorProductionRoutingFlatSummary {
    static let jsonByFixtureID: [String: String] = [
        "en.local_service.1": """
        {"raw":"Find me a plumber in Austin for a leak repair this Saturday afternoon.","object":"plumber","need":"leak repair","place":"Austin","time":"Saturday afternoon","budget":null,"commercial":null,"mods":[],"hard":["Austin","Saturday afternoon"],"soft":[],"gaps":[],"confidence":0.91}
        """,
        "en.commercial_offer.1": """
        {"raw":"Looking for a used MacBook Pro under 1200 dollars shipped to Canada.","object":"MacBook Pro","need":"used laptop","place":null,"time":null,"budget":"1200 dollars","commercial":"shipped","mods":["used"],"hard":["Canada"],"soft":[],"gaps":[],"confidence":0.88}
        """,
        "en.professional.1": """
        {"raw":"Need a freelance Solidity auditor for a two week codebase review.","object":"Solidity auditor","need":"codebase review","place":null,"time":"two weeks","budget":null,"commercial":null,"mods":["freelance"],"hard":[],"soft":[],"gaps":[],"confidence":0.86}
        """,
        "en.social_person.1": """
        {"raw":"Find people nearby who want a tennis partner for weekday evenings.","object":null,"need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":["tennis partner"],"gaps":[],"confidence":0.84}
        """,
        "en.interest_affinity.1": """
        {"raw":"Looking for someone to join a weekend hiking group in the Bay Area.","object":"hiking group","need":"weekend","place":"Bay Area","time":"weekend","budget":null,"commercial":null,"mods":["beginner"],"hard":["Bay Area"],"soft":[],"gaps":[],"confidence":0.83}
        """,
        "en.trusted_contact.1": """
        {"raw":"Message John Smith from my contacts about the contract renewal timeline.","object":"John Smith","need":"contract renewal","place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":["Which contact channel?"],"confidence":0.55}
        """,
        "en.time_sensitive.1": """
        {"raw":"Need an emergency locksmith in Seattle tonight before 10pm.","object":"locksmith","need":"emergency","place":"Seattle","time":"tonight before 10pm","budget":null,"commercial":null,"mods":["emergency"],"hard":["Seattle","tonight"],"soft":[],"gaps":[],"confidence":0.9}
        """,
        "en.location_sensitive.1": """
        {"raw":"Roofing contractors within 15 miles of zip 98101.","object":"roofing contractor","need":null,"place":"98101","time":null,"budget":null,"commercial":null,"mods":["15 miles"],"hard":["98101"],"soft":[],"gaps":[],"confidence":0.87}
        """,
        "en.remote_online.1": """
        {"raw":"Remote Spanish tutor for conversational practice on weekday mornings EST.","object":"Spanish tutor","need":"conversational practice","place":null,"time":"weekday mornings EST","budget":null,"commercial":"remote","mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.85}
        """,
        "en.budget_price.1": """
        {"raw":"Wedding photographer under 3000 dollars near Chicago next spring.","object":"wedding photographer","need":null,"place":"Chicago","time":"next spring","budget":"3000 dollars","commercial":null,"mods":[],"hard":["Chicago"],"soft":[],"gaps":[],"confidence":0.86}
        """,
        "en.availability.1": """
        {"raw":"Yoga instructor for private sessions only Sundays before noon.","object":"yoga instructor","need":"private sessions","place":null,"time":"Sundays before noon","budget":null,"commercial":null,"mods":[],"hard":["Sundays"],"soft":[],"gaps":[],"confidence":0.84}
        """,
        "en.vague.1": """
        {"raw":"Can someone help with something important?","object":"help","need":"something important","place":"local","time":"soon","budget":null,"commercial":null,"mods":[],"hard":["local","soon"],"soft":[],"gaps":["What kind of help?"],"confidence":0.42}
        """,
        "en.multi_constraint.1": """
        {"raw":"Find a bilingual family law lawyer in Miami for a first consultation before Friday with budget under 500 dollars per hour.","object":"family law lawyer","need":"first consultation","place":"Miami","time":"before Friday","budget":"500 dollars per hour","commercial":null,"mods":["bilingual"],"hard":["Miami","Friday"],"soft":[],"gaps":[],"confidence":0.89}
        """,
        "zh.local_service.1": """
        {"raw":"我需要在周六下午在奥斯汀找一位水管工修理漏水。","object":"水管工","need":"修理漏水","place":"奥斯汀","time":"周六下午","budget":null,"commercial":null,"mods":[],"hard":["奥斯汀","周六下午"],"soft":[],"gaps":[],"confidence":0.88}
        """,
        "zh.commercial_offer.1": """
        {"raw":"我想买一台二手 MacBook Pro，预算八千人民币以内，可以邮寄到上海。","object":"MacBook Pro","need":"二手","place":null,"time":null,"budget":"8000 CNY","commercial":"邮寄","mods":["二手"],"hard":["上海"],"soft":[],"gaps":[],"confidence":0.86}
        """,
        "zh.professional.1": """
        {"raw":"需要一位熟悉 Solidity 的自由职业安全审计员，两周内完成代码审查。","object":"安全审计员","need":"代码审查","place":null,"time":"两周内","budget":null,"commercial":null,"mods":["Solidity","自由职业"],"hard":[],"soft":[],"gaps":[],"confidence":0.85}
        """,
        "zh.social_person.1": """
        {"raw":"想找附近晚上一起打网球的人。","object":null,"need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":["一起打网球"],"gaps":[],"confidence":0.84}
        """,
        "zh.interest_affinity.1": """
        {"raw":"有没有周末在湾区一起徒步的新手小组？","object":"徒步小组","need":"新手","place":"湾区","time":"周末","budget":null,"commercial":null,"mods":[],"hard":["湾区","周末"],"soft":[],"gaps":[],"confidence":0.83}
        """,
        "zh.trusted_contact.1": """
        {"raw":"给我通讯录里的张伟发消息，确认合同进展。","object":"张伟","need":"合同进展","place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":["确认发送渠道"],"confidence":0.52}
        """,
        "zh.time_sensitive.1": """
        {"raw":"今晚十点前需要在西雅图市中心找紧急开锁师傅。","object":"开锁师傅","need":"紧急","place":"西雅图市中心","time":"今晚十点前","budget":null,"commercial":null,"mods":["紧急"],"hard":["西雅图","今晚"],"soft":[],"gaps":[],"confidence":0.9}
        """,
        "zh.location_sensitive.1": """
        {"raw":"在邮编 98101 附近十五英里内找屋顶维修承包商。","object":"屋顶维修","need":null,"place":"98101","time":null,"budget":null,"commercial":null,"mods":["十五英里"],"hard":["98101"],"soft":[],"gaps":[],"confidence":0.87}
        """,
        "zh.remote_online.1": """
        {"raw":"需要远程的西班牙语口语陪练老师，工作日早上（美国东部时间）。","object":"西班牙语陪练","need":"口语练习","place":null,"time":"工作日早上","budget":null,"commercial":"远程","mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.85}
        """,
        "zh.budget_price.1": """
        {"raw":"明年春天在芝加哥附近找婚礼摄影师，预算不超过三千美元。","object":"婚礼摄影师","need":null,"place":"芝加哥","time":"明年春天","budget":"3000 USD","commercial":null,"mods":[],"hard":["芝加哥"],"soft":[],"gaps":[],"confidence":0.86}
        """,
        "zh.availability.1": """
        {"raw":"只想在周日上午十二点前预约私人瑜伽教练上门。","object":"瑜伽教练","need":"上门","place":null,"time":"周日上午十二点前","budget":null,"commercial":null,"mods":["私人"],"hard":["周日"],"soft":[],"gaps":[],"confidence":0.84}
        """,
        "zh.vague.1": """
        {"raw":"能不能帮我处理一件很重要的事？","object":"重要的事","need":"帮助","place":"本地","time":"尽快","budget":null,"commercial":null,"mods":[],"hard":["本地","尽快"],"soft":[],"gaps":["具体是什么事?"],"confidence":0.4}
        """,
        "zh.multi_constraint.1": """
        {"raw":"在迈阿密找一位双语家庭法律师，周五前要完成首次咨询，每小时费用不超过五百美元。","object":"lawyer","need":"首次咨询","place":"Miami","time":"Friday before today","budget":500,"commercial":null,"mods":["双语"],"hard":["Miami"],"soft":[],"gaps":[],"confidence":0.89}
        """,
        "mx.local_bilingual.1": """
        {"raw":"上海 Pudong 周末 need a certified electrician 上门检查电路。","object":"electrician","need":"电路检查","place":"上海 Pudong","time":"周末","budget":null,"commercial":null,"mods":["certified","上门"],"hard":["上海"],"soft":[],"gaps":[],"confidence":0.87}
        """,
        "mx.remote_budget.1": """
        {"raw":"Remote UI designer needed, 远程工作，预算 budget 5000 RMB 以内。","object":"UI designer","need":"远程工作","place":null,"time":null,"budget":"5000 RMB","commercial":"remote","mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.85}
        """,
        "llm.replay.roofer_flat.1": """
        {"raw":"Find me a roofer in Aurora tomorrow at 2:30pm.","object":"roofer","need":null,"place":"Aurora","time":"tomorrow at 2:30pm","budget":null,"commercial":null,"mods":[],"hard":["Aurora","tomorrow at 2:30pm"],"soft":[],"gaps":[],"confidence":0.9}
        """,
        "llm.replay.shanghai_macbook.1": """
        {"raw":"二手 MacBook Pro 八千以内邮寄上海","object":"MacBook Pro","need":null,"place":"上海","time":null,"budget":"8000 CNY","commercial":null,"mods":["二手","邮寄"],"hard":["上海"],"soft":[],"gaps":[],"confidence":0.82}
        """
    ]

    static func flatSummaryJSON(for fixtureID: String) -> String? {
        guard let raw = jsonByFixtureID[fixtureID] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Vague fixtures: require async I/O proof but relax canonical LLM-source assertions.
    /// Contact/message phrasing: async flat-summary may run but canonical search intent is not required.
    static let skipsProductionCanonicalSearchIntent: Set<String> = [
        "en.trusted_contact.1",
        "zh.trusted_contact.1"
    ]

    static let relaxedStrictLLMCanonical: Set<String> = [
        "en.vague.1",
        "zh.vague.1"
    ]
}

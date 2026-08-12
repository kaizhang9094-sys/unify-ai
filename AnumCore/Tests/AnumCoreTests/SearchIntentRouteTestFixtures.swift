import Foundation

enum SearchIntentRouteTestFixtures {
    static let photographyPeopleJSON = """
    {"raw":"Find people interested in photography in Aurora","object":"photography enthusiasts","need":null,"place":"Aurora","time":null,"budget":null,"commercial":null,"mods":[],"hard":["Aurora"],"soft":["photography"],"gaps":[],"confidence":0.88,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.91,"routeRationale":"social interest discovery"}
    """

    static let photographyEnthusiastsJSON = """
    {"raw":"Find photography enthusiasts in Aurora","object":"photography enthusiasts","need":null,"place":"Aurora","time":null,"budget":null,"commercial":null,"mods":[],"hard":["Aurora"],"soft":["photography"],"gaps":[],"confidence":0.87,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.9,"routeRationale":"social hobby discovery"}
    """

    static let productPhotographerJSON = """
    {"raw":"Find a photographer for product photos in Aurora","object":"photographer","need":"product photos","place":"Aurora","time":null,"budget":null,"commercial":null,"mods":[],"hard":["Aurora","product photos"],"soft":[],"gaps":[],"confidence":0.9,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.93,"routeRationale":"hire photographer for commercial shoot"}
    """

    static let rooferAppraisalJSON = """
    {"raw":"Find a roofer for an appraisal tomorrow at 2pm","object":"roofer","need":"appraisal","place":null,"time":"tomorrow at 2pm","budget":null,"commercial":null,"mods":[],"hard":["tomorrow at 2pm"],"soft":[],"gaps":[],"confidence":0.92,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.94,"routeRationale":"scheduled vendor appraisal"}
    """

    static let legacyPhotographyJSON = """
    {"raw":"Find people interested in photography in Aurora","object":"photography enthusiasts","need":"none","place":"Aurora","time":null,"budget":null,"commercial":null,"mods":[],"hard":["Aurora"],"soft":["photography"],"gaps":[],"confidence":0.88}
    """

    static let invalidSocialLowConfidenceJSON = """
    {"raw":"Find people interested in photography in Aurora","object":"photography enthusiasts","need":null,"place":"Aurora","time":null,"budget":null,"commercial":null,"mods":[],"hard":["Aurora"],"soft":[],"gaps":[],"confidence":0.88,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.4,"routeRationale":"uncertain"}
    """

    static let needNoneJSON = """
    {"raw":"Find people interested in photography in Aurora","object":"photography enthusiasts","need":"none","place":"Aurora","time":null,"budget":null,"commercial":null,"mods":[],"hard":["Aurora"],"soft":[],"gaps":[],"confidence":0.8,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.9,"routeRationale":"social"}
    """

    static let paintingPeopleJSON = """
    {"raw":"Find people interested in painting.","object":"people","need":"painting","place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":["painting"],"gaps":[],"confidence":0.88,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.92,"routeRationale":"social interest discovery"}
    """

    static let legacyPaintingJSON = """
    {"raw":"Find people interested in painting.","object":"people","need":"painting","place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":["painting"],"gaps":[],"confidence":0.8}
    """
    static let movieAuroraSocialJSON = """
    {"raw":"Find someone who wants to watch a movie tomorrow in Aurora","object":"person","need":"watch a movie","place":"Aurora","time":"tomorrow","budget":null,"commercial":null,"mods":[],"hard":["Aurora","tomorrow"],"soft":["movie"],"gaps":[],"confidence":0.9,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.92,"routeRationale":"find social affinity for movie watching"}
    """

    static let rooferAuroraTomorrowJSON = """
    {"raw":"Find a roofer in Aurora tomorrow at 2pm for an appraisal","object":"roofer","need":"appraisal","place":"Aurora","time":"tomorrow at 2pm","budget":null,"commercial":null,"mods":[],"hard":["Aurora","tomorrow at 2pm"],"soft":[],"gaps":[],"confidence":0.92,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.94,"routeRationale":"scheduled vendor appraisal"}
    """

    static let campingFriendJSON = """
    {"raw":"Find a friend for a camping trip this weekend","object":"friend","need":"camping trip","place":null,"time":"this weekend","budget":null,"commercial":null,"mods":[],"hard":["this weekend"],"soft":["camping"],"gaps":[],"confidence":0.88,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.9,"routeRationale":"social camping affinity"}
    """

    static let campingGearRentalProviderJSON = """
    {"raw":"Find camping gear rental in Aurora","object":"camping gear","need":"rental","place":"Aurora","time":null,"budget":null,"commercial":"equipment rental","mods":[],"hard":["Aurora"],"soft":["camping"],"gaps":[],"confidence":0.91,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.93,"routeRationale":"rent camping equipment"}
    """

    static let campingGearRentalWrongSocialJSON = """
    {"raw":"Find camping gear rental in Aurora","object":"camping gear","need":"rental","place":"Aurora","time":null,"budget":null,"commercial":"equipment rental","mods":[],"hard":["Aurora"],"soft":["camping"],"gaps":[],"confidence":0.91,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.88,"routeRationale":"wrong social route for rental"}
    """

    static let bookCampingGuideJSON = """
    {"raw":"Book a camping guide for a guided camping trip in Colorado","object":"camping guide","need":"guided camping trip","place":"Colorado","time":null,"budget":null,"commercial":null,"mods":[],"hard":["Colorado"],"soft":["camping","guide"],"gaps":[],"confidence":0.92,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.94,"routeRationale":"hire guide for guided trip"}
    """

    static let campingFriendNextMonthJSON = """
    {"raw":"Find me a camping friend who wants to go on a camping trip next month","object":"camping friend","need":"camping trip","place":null,"time":"next month","budget":null,"commercial":null,"mods":[],"hard":["next month"],"soft":["camping"],"gaps":[],"confidence":0.88,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.87,"routeRationale":"social camping affinity"}
    """

    static let rentCampingGearFromJSON = """
    {"raw":"Find someone to rent camping gear from next month","object":"camping gear","need":"rent camping gear","place":null,"time":"next month","budget":null,"commercial":null,"mods":[],"hard":["next month"],"soft":["camping"],"gaps":[],"confidence":0.9,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.91,"routeRationale":"rent equipment from provider"}
    """

    static let bookCampingGuideNextMonthJSON = """
    {"raw":"Find a camping guide I can book next month","object":"camping guide","need":"book guided camping trip","place":null,"time":"next month","budget":null,"commercial":null,"mods":[],"hard":["next month"],"soft":["camping","guide"],"gaps":[],"confidence":0.91,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.92,"routeRationale":"book guide service"}
    """

    static let rentCampingGearWrongSocialJSON = """
    {"raw":"Find someone to rent camping gear from next month","object":"camping gear","need":"rent camping gear","place":null,"time":"next month","budget":null,"commercial":null,"mods":[],"hard":["next month"],"soft":["camping"],"gaps":[],"confidence":0.9,"routeClass":"socialAffinitySearch","surfacePreference":"affinity","targetKind":"person","mode":"relational","routeConfidence":0.88,"routeRationale":"wrong social route for rental"}
    """

}

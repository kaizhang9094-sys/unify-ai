import Foundation

#if DEBUG

public enum MultilingualSecretaryLiveSubsetFixtures {
    public static let verticals: [MultilingualSecretaryMatrixVertical] = [
        .roofer,
        .cleaner,
        .plumber,
        .weddingPhotographer,
        .postpartumCaregiver
    ]

    public static let languagePairs: [MultilingualSecretaryMatrixLanguagePair] = [
        .zhUserZhProvider,
        .mixedUserMixedProvider
    ]

    public static let all: [MultilingualSecretaryMatrixFixture] = {
        MultilingualSecretaryMatrixFixtures.all.filter { fixture in
            verticals.contains(fixture.vertical) && languagePairs.contains(fixture.languagePair)
        }
    }()
}

#endif

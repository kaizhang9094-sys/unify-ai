import Foundation
import AnumCore

/// App-layer adapter from social search thread state into public profile detail input.
enum SocialDiscoveryProfileAdapter {
    static func forYouItem(from detail: ExchangeModels.ThreadDetail) -> ExchangeModels.ForYouItem {
        SocialDiscoveryProfileProjection.forYouItem(from: detail)
    }

    static func forYouItem(from inboxItem: ExchangeModels.InboxItem) -> ExchangeModels.ForYouItem {
        SocialDiscoveryProfileProjection.forYouItem(from: inboxItem)
    }
}

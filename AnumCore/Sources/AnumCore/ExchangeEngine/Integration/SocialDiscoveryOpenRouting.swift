import Foundation

/// UI routing policy for social discovery threads vs commercial exchange threads.
public enum SocialDiscoveryOpenRouting {
    /// Social/profile-led discovery should open public profile inspection, not the exchange desk thread view.
    public static func shouldPresentProfileDetail(for thread: ExchangeThread) -> Bool {
        ExchangeThreadLaneResolver.lane(for: thread) == .socialConnection
    }
}

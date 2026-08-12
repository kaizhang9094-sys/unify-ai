import SwiftUI

/// Safety & privacy copy — matches Unify / Offering — Required glass panel language (`UnifyIceShellBackground`, `UnifyDarkCard`).
struct SafetyPrivacyView: View {
    let feedbackEmail: String

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                safetyGlassSection(title: nil) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Private where it matters. Public when you publish.")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)

                        Text("Your AI runs on your device. Your private chats, contact notes, local settings, and AI instructions are stored locally unless you choose to send, publish, export, or share them.")
                            .font(.system(size: 13))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)

                        Text("Unify also includes a people-to-people network. Messages, public profiles, work profiles, offers, media, search requests, and notification tokens may use Unify’s federation services so the app can connect you with other people.")
                            .font(.system(size: 13))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    }
                }

                safetyGlassSection(title: "How Unify uses AI") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• AI responses are generated on your device using the local model bundled with the app.")
                        Text("• Your messages are not uploaded to a third-party cloud AI provider for generation.")
                        Text("• Local AI prompts may include your current message, recent context, saved preferences, contact notes, and public profile or offer facts when needed.")
                        Text("• Some features use Unify’s federation services for search, messaging, profiles, media, and notifications — not for cloud AI generation.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                safetyGlassSection(title: "What stays on your device") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Companion chat history, local memories, identity settings, and room assets.")
                        Text("• Secretary threads, drafts, approvals, inbox/outbox records, and local notifications.")
                        Text("• Contact context such as relationship notes, tone notes, and reply guidance for a specific person.")
                        Text("• Secretary style, constitution, onboarding settings, Discovery preferences, and For You dismissals.")
                        Text("• Requester “near me” location data used for local matching.")
                        Text("• Local model files, app caches, and local databases needed for the app to work.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Text("Local data is stored inside this app’s sandbox on your device. Some items may also be included in your iOS device backup depending on your system settings.")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .padding(.top, 6)
                }

                safetyGlassSection(title: "What may leave your device") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Messages or requests you send to another person through the federation relay.")
                        Text("• Public profile and work profile information you choose to publish.")
                        Text("• Offers, service areas, pricing, packages, policies, FAQs, contact information, and images you publish.")
                        Text("• Search text, tags, and matching signals used to find public profiles and offers.")
                        Text("• Media you upload for public profile or work profile display.")
                        Text("• Push notification tokens used to deliver notifications to your device.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Text("Published profile and offer information is meant to be discoverable by others. Do not publish information you want to keep private.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange)
                        .padding(.top, 6)
                }

                safetyGlassSection(title: "Public profiles, work profiles, and offers") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When you publish a public profile or work profile, other people may be able to discover it through search or suggestions.")
                        Text("Published offer information may include your headline, summary, images, tags, service areas, prices, packages, availability, policies, FAQs, required buyer inputs, and optional contact information.")
                        Text("If you add a service area, Unify may convert that place into structured location data so local search can work better.")
                        Text("Service areas you publish are public work/service coverage. Your private requester “near me” location is separate and is not written into your seller profile.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                safetyGlassSection(title: "Messages and federation") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unify uses a federation relay to send messages, requests, and replies between users’ nodes.")
                        Text("Messages you send are delivered to the intended recipient and may be stored on your device, the recipient’s device, and federation services needed for delivery.")
                        Text("Removing a thread from your history hides it locally. It does not delete copies that were already delivered to another person.")
                        Text("Blocking or clearing a direct message is local to your device unless otherwise stated.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                safetyGlassSection(title: "Location") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Requester location: if you use “near me,” your device location can help your AI match nearby results. This is used locally for matching and is separate from your public profile.")
                        Text("Seller location: if you publish service areas for your work or offer, those areas may be geocoded and used publicly for local discovery.")
                        Text("Unify does not show raw coordinates or H3 cell IDs in normal user-facing screens.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                safetyGlassSection(title: "Notifications") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If you turn on notifications, iOS may give the app a push notification token.")
                        Text("That token can be registered with Unify’s federation service so your device can receive alerts for replies, requests, or items needing your attention.")
                        Text("You can turn notifications off in the app or in iOS Settings.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                safetyGlassSection(title: "Your controls") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You can manage your data from app settings and profile screens:")
                        Text("• Clear recent Companion chat.")
                        Text("• Export local app data as a .zip created on your device.")
                        Text("• Delete Companion data from this device.")
                        Text("• Delete Secretary data from this device.")
                        Text("• Remove threads from history.")
                        Text("• Clear or block direct message contacts locally.")
                        Text("• Unpublish your public/work profile from discovery.")
                        Text("• Replace or remove profile and offer images.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Text("Some controls hide or remove data locally rather than deleting every copy everywhere. Messages already sent to another person, data already delivered to another device, and server-side records needed for delivery may remain outside your device.")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .padding(.top, 6)
                }

                safetyGlassSection(title: "What we don’t do") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• We do not sell your personal data.")
                        Text("• We do not use third-party ad networks in the app.")
                        Text("• We do not send your private messages to a third-party cloud AI provider for generation.")
                        Text("• We do not publish your private contact notes, tone notes, or local requester location as part of your public profile.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                safetyGlassSection(title: "Backups & device sharing") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iOS may include this app’s data in device backups, such as iCloud Backup, depending on your system settings.")
                        Text("If someone can access your device or restore your backups, they may be able to access app data.")
                        Text("For best privacy, use a device passcode or Face ID and review your backup and device-sharing settings.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }

                safetyGlassSection(title: "Safety & Disclaimer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• AI-generated responses may be incorrect, incomplete, or inappropriate for your situation.")
                        Text("• You are responsible for reviewing messages, offers, replies, and actions before relying on them.")
                        Text("• For medical, legal, financial, or safety-critical decisions, consult a qualified professional.")
                        Text("• Sexual content involving minors is not allowed.")
                        Text("• This app is not a replacement for professional medical, legal, financial, or emergency services.")
                        Text("If you are in immediate danger or need urgent help, contact local emergency services.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)

                    Text("Provided \"as is\" without warranties. To the extent permitted by law, we are not liable for actions you take based on AI-generated responses.")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .padding(.top, 4)
                }

                safetyGlassSection(title: "Contact") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Feedback: \(feedbackEmail)")
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .textSelection(.enabled)

                        Text("Sending feedback opens your email app and uses your email provider. Please don’t include sensitive information you wouldn’t want stored in your sent mail.")
                            .font(.system(size: 12))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
                }

                safetyGlassSection(title: nil) {
                    Text("Last updated: May 2026")
                        .font(.system(size: 12))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(UnifyIceShellBackground())
        .navigationTitle("Safety & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(SecretaryTheme.darkOrange)
    }

    private func safetyGlassSection<Content: View>(
        title: String?,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        UnifyDarkCard(cornerRadius: 18, strokeOpacity: 0.88) {
            VStack(alignment: .leading, spacing: 10) {
                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}

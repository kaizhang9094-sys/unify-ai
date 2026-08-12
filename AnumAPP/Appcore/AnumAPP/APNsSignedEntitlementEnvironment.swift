import Foundation
import AnumCore

/// Resolves APNs upload environment from the **signed app entitlement** (`aps-environment`).
/// Prefers entitlements embedded in `embedded.mobileprovision` (Xcode/device installs), then Info.plist as fallback.
enum APNsSignedEntitlementEnvironment {

    enum ConfiguredApsEnvironment: String, Sendable {
        case development
        case production
        case unknown
    }

    struct Resolved: Sendable {
        /// Value read from embedded provisioning profile entitlements when available.
        let signedApsEnvironmentRaw: String?
        /// Build-setting / Info.plist `APS_ENVIRONMENT` (may differ from signed entitlement on Xcode device installs).
        let configuredApsEnvironmentRaw: String?
        /// Effective entitlement used for upload mapping (signed first, else Info.plist).
        let effectiveApsEnvironment: ConfiguredApsEnvironment
        let uploadEnvironment: ExchangeHTTPRelayClient.PushRegistrationEnvironment?
        let signedEntitlementUnreadable: Bool
        let configMismatch: Bool
    }

    /// Reads `aps-environment` from the embedded provisioning profile when present (typical for Xcode device installs).
    static func readSignedApsEnvironmentString() -> String? {
        guard let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let profileData = try? Data(contentsOf: profileURL),
              let profileText = String(data: profileData, encoding: .isoLatin1) else {
            return nil
        }

        guard let xmlStart = profileText.range(of: "<?xml"),
              let xmlEnd = profileText.range(of: "</plist>", range: xmlStart.lowerBound..<profileText.endIndex) else {
            return nil
        }

        let plistFragment = String(profileText[xmlStart.lowerBound..<xmlEnd.upperBound])
        guard let plistData = plistFragment.data(using: .utf8),
              let root = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any] else {
            return nil
        }

        return normalizedApsEnvironmentString(entitlements["aps-environment"])
    }

    static func readConfiguredApsEnvironmentString() -> String? {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "APS_ENVIRONMENT") as? String {
            let trimmed = configured.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let fallback = Bundle.main.object(forInfoDictionaryKey: "aps-environment") as? String {
            let trimmed = fallback.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private static func normalizedApsEnvironmentString(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let string = value as? NSString {
            let trimmed = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed)
        }
        return nil
    }

    private static func mapRawToResolved(
        raw: String,
        signedApsEnvironmentRaw: String?,
        configuredApsEnvironmentRaw: String?,
        signedEntitlementUnreadable: Bool
    ) -> Resolved {
        let normalizedSigned = signedApsEnvironmentRaw?.lowercased()
        let normalizedConfigured = configuredApsEnvironmentRaw?.lowercased()
        let configMismatch: Bool = {
            guard let normalizedSigned, let normalizedConfigured else { return false }
            return normalizedSigned != normalizedConfigured
        }()

        switch raw.lowercased() {
        case "development":
            return Resolved(
                signedApsEnvironmentRaw: signedApsEnvironmentRaw,
                configuredApsEnvironmentRaw: configuredApsEnvironmentRaw,
                effectiveApsEnvironment: .development,
                uploadEnvironment: .sandbox,
                signedEntitlementUnreadable: signedEntitlementUnreadable,
                configMismatch: configMismatch
            )
        case "production":
            return Resolved(
                signedApsEnvironmentRaw: signedApsEnvironmentRaw,
                configuredApsEnvironmentRaw: configuredApsEnvironmentRaw,
                effectiveApsEnvironment: .production,
                uploadEnvironment: .production,
                signedEntitlementUnreadable: signedEntitlementUnreadable,
                configMismatch: configMismatch
            )
        default:
            print(
                "[APNs][EnvironmentResolveFailed] reason=unknown_value " +
                "effectiveApsEnvironment=\(raw)"
            )
            return Resolved(
                signedApsEnvironmentRaw: signedApsEnvironmentRaw,
                configuredApsEnvironmentRaw: configuredApsEnvironmentRaw,
                effectiveApsEnvironment: .unknown,
                uploadEnvironment: nil,
                signedEntitlementUnreadable: signedEntitlementUnreadable,
                configMismatch: configMismatch
            )
        }
    }

    static func resolve() -> Resolved {
        let signedRaw = readSignedApsEnvironmentString()
        let configuredRaw = readConfiguredApsEnvironmentString()
        let signedUnreadable = signedRaw == nil

        if let signedRaw {
            let resolved = mapRawToResolved(
                raw: signedRaw,
                signedApsEnvironmentRaw: signedRaw,
                configuredApsEnvironmentRaw: configuredRaw,
                signedEntitlementUnreadable: false
            )
            if resolved.configMismatch {
                print(
                    "[APNs][EnvironmentMismatchRisk] signedApsEnvironment=\(signedRaw) " +
                    "configuredApsEnvironment=\(configuredRaw ?? "nil") " +
                    "uploadEnvironment=\(resolved.uploadEnvironment?.rawValue ?? "nil")"
                )
            }
            return resolved
        }

        if signedUnreadable, let configuredRaw {
            print(
                "[APNs][EnvironmentMismatchRisk] configuredApsEnvironment=\(configuredRaw) " +
                "signedEntitlementUnreadable=true"
            )
            return mapRawToResolved(
                raw: configuredRaw,
                signedApsEnvironmentRaw: nil,
                configuredApsEnvironmentRaw: configuredRaw,
                signedEntitlementUnreadable: true
            )
        }

        print("[APNs][EnvironmentResolveFailed] reason=missing_signed_and_config configuredApsEnvironment=nil")
        return Resolved(
            signedApsEnvironmentRaw: nil,
            configuredApsEnvironmentRaw: configuredRaw,
            effectiveApsEnvironment: .unknown,
            uploadEnvironment: nil,
            signedEntitlementUnreadable: true,
            configMismatch: false
        )
    }

    static func hasBackgroundRemoteNotificationMode() -> Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("remote-notification")
    }

    static func logBuildConfig() {
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        let federationURL = ExchangeBootstrap.resolvedFederationBaseURL().absoluteString
        print(
            "[BuildConfig] configuration=\(configuration) bundleID=\(bundleID) " +
            "federationBaseURL=\(federationURL)"
        )
    }

    static func logEntitlementsCheck() {
        let resolved = resolve()
        print(
            "[EntitlementsCheck] signedApsEnvironment=\(resolved.signedApsEnvironmentRaw ?? "nil") " +
            "configuredApsEnvironment=\(resolved.configuredApsEnvironmentRaw ?? "nil") " +
            "effectiveApsEnvironment=\(resolved.effectiveApsEnvironment.rawValue) " +
            "uploadEnvironment=\(resolved.uploadEnvironment?.rawValue ?? "nil") " +
            "signedEntitlementUnreadable=\(resolved.signedEntitlementUnreadable) " +
            "configMismatch=\(resolved.configMismatch) " +
            "backgroundRemoteNotification=\(hasBackgroundRemoteNotificationMode())"
        )
    }
}

import Foundation

#if DEBUG
@inline(__always)
private func exchSpatialAnchorPrepLog(_ message: @autoclosure () -> String) {
    print("[ExchangeRequesterSpatialAnchorPreparer] \(message())")
}
#else
@inline(__always)
private func exchSpatialAnchorPrepLog(_ message: @autoclosure () -> String) {}
#endif

/// Resolves requester spatial anchor priority for discovery (no ranking; prepare/pass-through only).
public enum ExchangeRequesterSpatialAnchorPreparer: Sendable {
    public struct Outcome: Sendable, Hashable {
        public var facets: ExchangeIntentFacets
        public var anchor: ExchangeRequesterSpatialAnchor?
        public var needsLocationClarification: Bool

        public init(
            facets: ExchangeIntentFacets,
            anchor: ExchangeRequesterSpatialAnchor?,
            needsLocationClarification: Bool = false
        ) {
            self.facets = facets
            self.anchor = anchor
            self.needsLocationClarification = needsLocationClarification
        }
    }

    public static func prepare(
        facets: ExchangeIntentFacets,
        userText: String,
        shouldDiscover: Bool,
        locationProvider: (any ExchangeRequesterLocationProviding)?
    ) async -> Outcome {
        var updated = facets
        let locationRequirement = facets.locationRequirement
            ?? ExchangeLocationRequirementMapping.buildFromFacets(facets)

        let explicitPlacePresent = hasExplicitQueryLocation(locationRequirement)
        let localServiceLike = appearsLocalServiceLike(facets: facets, userText: userText)

        exchSpatialAnchorPrepLog(
            "prepare BEGIN appearsLocalServiceLike=\(localServiceLike) explicitPlacePresent=\(explicitPlacePresent) " +
            "shouldDiscover=\(shouldDiscover) queryClass=\(facets.queryIntentClass.rawValue)"
        )

        if explicitPlacePresent {
            let anchor = explicitQueryAnchor(from: locationRequirement)
            updated.requesterSpatialAnchor = anchor
            updated = finalizeResolvedNearMeFacets(updated)
            logAnchorOutcome(
                anchor: anchor,
                currentDeviceSucceeded: false,
                savedDefaultSucceeded: false,
                note: "explicitQuery"
            )
            return Outcome(facets: updated, anchor: anchor, needsLocationClarification: false)
        }

        updated = applyLocalServiceDefaults(to: updated, isLocalServiceLike: localServiceLike)

        guard shouldDiscover || localServiceLike else {
            exchSpatialAnchorPrepLog("prepare SKIP | not discover/local-service")
            return Outcome(facets: updated, anchor: nil, needsLocationClarification: false)
        }

        let wantsNearMe = locationRequirement?.kind == .nearMe
        let needsRequesterAnchor = wantsNearMe || localServiceLike

        guard needsRequesterAnchor else {
            exchSpatialAnchorPrepLog("prepare SKIP | no requester anchor needed")
            return Outcome(facets: updated, anchor: nil, needsLocationClarification: false)
        }

        let allowDiscoveryWithoutAnchor = localServiceLike && !explicitPlacePresent

        guard let locationProvider else {
            exchSpatialAnchorPrepLog(
                "prepare locationProvider=nil currentDevice=fail savedDefault=fail allowDiscoveryWithoutAnchor=\(allowDiscoveryWithoutAnchor)"
            )
            if allowDiscoveryWithoutAnchor {
                return Outcome(facets: updated, anchor: nil, needsLocationClarification: false)
            }
            return markLocationClarificationIfNeeded(
                facets: updated,
                locationRequirement: locationRequirement,
                wantsNearMe: wantsNearMe
            )
        }

        var currentDeviceSucceeded = false
        var savedDefaultSucceeded = false
        var resolvedCoordinate: ExchangeCoordinate?
        var anchorSource: ExchangeRequesterSpatialAnchor.Source?

        if let coordinate = await locationProvider.requestOneShotCoordinate(), coordinate.isValid {
            resolvedCoordinate = coordinate
            currentDeviceSucceeded = true
            anchorSource = .currentDevice
        } else if wantsNearMe {
            let status = await locationProvider.authorizationStatus
            if status == .notDetermined {
                let granted = await locationProvider.requestWhenInUsePermission()
                if granted,
                   let retryCoordinate = await locationProvider.requestOneShotCoordinate(),
                   retryCoordinate.isValid {
                    resolvedCoordinate = retryCoordinate
                    currentDeviceSucceeded = true
                    anchorSource = .currentDevice
                }
            }
        }

        if resolvedCoordinate == nil {
            if let fallback = await locationProvider.lastKnownCoordinate(), fallback.isValid {
                resolvedCoordinate = fallback
                savedDefaultSucceeded = true
                anchorSource = .savedDefault
            }
        }

        exchSpatialAnchorPrepLog(
            "prepare coordinate chain currentDeviceSucceeded=\(currentDeviceSucceeded) " +
            "savedDefaultSucceeded=\(savedDefaultSucceeded) wantsNearMe=\(wantsNearMe)"
        )

        if let coordinate = resolvedCoordinate, let source = anchorSource {
            let anchor: ExchangeRequesterSpatialAnchor
            switch source {
            case .currentDevice:
                anchor = ExchangeRequesterSpatialAnchorBuilder.makeCurrentDeviceAnchor(coordinate: coordinate)
            case .savedDefault:
                anchor = ExchangeRequesterSpatialAnchorBuilder.makeSavedDefaultAnchor(coordinate: coordinate)
            default:
                anchor = ExchangeRequesterSpatialAnchorBuilder.makeNone()
            }

            guard anchor.hasResolvedSpatial else {
                exchSpatialAnchorPrepLog("prepare anchor build failed | source=\(source.rawValue)")
                if allowDiscoveryWithoutAnchor {
                    return Outcome(facets: updated, anchor: nil, needsLocationClarification: false)
                }
                return markLocationClarificationIfNeeded(
                    facets: updated,
                    locationRequirement: locationRequirement,
                    wantsNearMe: wantsNearMe
                )
            }

            updated.requesterSpatialAnchor = anchor
            if wantsNearMe || source == .currentDevice {
                updated = applyNearMeResolution(to: updated, anchor: anchor)
            }
            updated = finalizeResolvedNearMeFacets(updated)
            logAnchorOutcome(
                anchor: anchor,
                currentDeviceSucceeded: currentDeviceSucceeded,
                savedDefaultSucceeded: savedDefaultSucceeded,
                note: "resolved"
            )
            return Outcome(facets: updated, anchor: anchor, needsLocationClarification: false)
        }

        exchSpatialAnchorPrepLog(
            "prepare no coordinate | allowDiscoveryWithoutAnchor=\(allowDiscoveryWithoutAnchor)"
        )
        if allowDiscoveryWithoutAnchor {
            return Outcome(facets: updated, anchor: nil, needsLocationClarification: false)
        }

        return markLocationClarificationIfNeeded(
            facets: updated,
            locationRequirement: locationRequirement,
            wantsNearMe: wantsNearMe
        )
    }

    private static func applyLocalServiceDefaults(
        to facets: ExchangeIntentFacets,
        isLocalServiceLike: Bool
    ) -> ExchangeIntentFacets {
        guard isLocalServiceLike else { return facets }
        var copy = facets
        if !copy.prefersLocalFirst {
            copy.prefersLocalFirst = true
        }
        if copy.fulfillmentMode == .unknown {
            copy.fulfillmentMode = .localPreferred
        }
        return copy
    }

    private static func logAnchorOutcome(
        anchor: ExchangeRequesterSpatialAnchor?,
        currentDeviceSucceeded: Bool,
        savedDefaultSucceeded: Bool,
        note: String
    ) {
        let source = anchor?.source.rawValue ?? "nil"
        let cellCount = anchor?.spatial?.h3Cells.count ?? 0
        exchSpatialAnchorPrepLog(
            "prepare END note=\(note) anchorSource=\(source) h3CellCount=\(cellCount) " +
            "currentDeviceSucceeded=\(currentDeviceSucceeded) savedDefaultSucceeded=\(savedDefaultSucceeded)"
        )
    }

    private static func explicitQueryAnchor(
        from requirement: ExchangeLocationRequirement?
    ) -> ExchangeRequesterSpatialAnchor? {
        guard let requirement else { return nil }
        if requirement.kind == .remote {
            return ExchangeRequesterSpatialAnchorBuilder.makeNone()
        }
        if let spatial = requirement.spatial, spatial.hasResolvedCells {
            let coordinate: ExchangeCoordinate?
            if let lat = spatial.centerLatitude, let lng = spatial.centerLongitude {
                coordinate = ExchangeCoordinate(
                    latitude: lat,
                    longitude: lng,
                    horizontalAccuracyMeters: nil,
                    capturedAt: spatial.capturedAt
                )
            } else {
                coordinate = nil
            }
            return ExchangeRequesterSpatialAnchorBuilder.makeExplicitQueryAnchor(
                coordinate: coordinate,
                spatial: spatial,
                radiusMeters: spatial.radiusMeters
            )
        }
        if requirement.hasNamedPlace {
            return ExchangeRequesterSpatialAnchor(
                source: .explicitQuery,
                coordinate: nil,
                spatial: nil,
                radiusMeters: nil,
                createdAt: Date()
            )
        }
        return nil
    }

    private static func hasExplicitQueryLocation(_ requirement: ExchangeLocationRequirement?) -> Bool {
        guard let requirement else { return false }
        switch requirement.kind {
        case .namedPlace, .nearPlace, .hybrid:
            return requirement.hasNamedPlace
        case .remote:
            return true
        case .none, .nearMe:
            return false
        }
    }

    private static func appearsLocalServiceLike(
        facets: ExchangeIntentFacets,
        userText: String
    ) -> Bool {
        if facets.prefersLocalFirst || facets.explicitRegionRequired {
            return true
        }
        switch facets.queryIntentClass {
        case .offerSearch, .providerSearch, .capabilitySearch:
            if facets.allowsRemoteOrShipped == false {
                return true
            }
        default:
            break
        }
        if facets.serviceCategory?.isEmpty == false {
            return true
        }
        let lower = userText.lowercased()
        let localSignals = [
            "near me", "nearby", "local", "in person", "onsite", "on-site", "in my area"
        ]
        return localSignals.contains(where: { lower.contains($0) })
    }

    private static func applyNearMeResolution(
        to facets: ExchangeIntentFacets,
        anchor: ExchangeRequesterSpatialAnchor
    ) -> ExchangeIntentFacets {
        var copy = facets
        var requirement = copy.locationRequirement
            ?? ExchangeLocationRequirement(kind: .nearMe, strictness: .preferred)

        requirement.kind = .nearMe
        requirement.strictness = .preferred
        requirement.spatial = anchor.spatial
        if let displayName = requirement.displayName,
           ExchangeNearMeLexicalSanitizer.isNearMeLiteral(displayName) {
            requirement.displayName = nil
        }
        if let rawText = requirement.rawText,
           ExchangeNearMeLexicalSanitizer.isNearMeLiteral(rawText) {
            requirement.rawText = nil
        }
        if let normalizedName = requirement.normalizedName,
           ExchangeNearMeLexicalSanitizer.isNearMeLiteral(normalizedName)
            || ExchangeNearMeLexicalSanitizer.isNearMeNoiseToken(normalizedName) {
            requirement.normalizedName = nil
        }
        if let sourcePhrase = requirement.sourcePhrase,
           ExchangeNearMeLexicalSanitizer.isNearMeLiteral(sourcePhrase) {
            requirement.sourcePhrase = nil
        }
        requirement.aliases = requirement.aliases.filter {
            !ExchangeNearMeLexicalSanitizer.isNearMeLiteral($0)
                && !ExchangeNearMeLexicalSanitizer.isNearMeNoiseToken($0)
        }
        copy.locationRequirement = requirement
        if copy.locationText?.lowercased() == "near me" {
            copy.locationText = nil
        }
        if copy.placeName?.lowercased() == "near me" {
            copy.placeName = nil
        }
        return copy
    }

    private static func finalizeResolvedNearMeFacets(
        _ facets: ExchangeIntentFacets
    ) -> ExchangeIntentFacets {
        ExchangeNearMeLexicalSanitizer.sanitizeFacets(facets)
    }

    private static func markLocationClarificationIfNeeded(
        facets: ExchangeIntentFacets,
        locationRequirement: ExchangeLocationRequirement?,
        wantsNearMe: Bool
    ) -> Outcome {
        var updated = facets
        let needsClarification = wantsNearMe
            || locationRequirement?.strictness == .required
            || facets.explicitRegionRequired

        if needsClarification {
            var requirement = locationRequirement ?? ExchangeLocationRequirement.nearMeDefault()
            requirement.strictness = .requiresClarification
            if wantsNearMe {
                requirement.kind = .nearMe
            }
            updated.locationRequirement = requirement
        }

        return Outcome(
            facets: updated,
            anchor: nil,
            needsLocationClarification: needsClarification
        )
    }
}

private extension ExchangeLocationRequirement {
    static func nearMeDefault() -> ExchangeLocationRequirement {
        ExchangeLocationRequirement(
            rawText: "near me",
            kind: .nearMe,
            strictness: .requiresClarification,
            sourcePhrase: "near me"
        )
    }
}

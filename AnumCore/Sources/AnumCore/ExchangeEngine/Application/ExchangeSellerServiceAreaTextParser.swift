import Foundation

/// Parses seller-entered service-area chip text into a place query and optional radius.
enum ExchangeSellerServiceAreaTextParser: Sendable {
    struct Parsed: Sendable, Hashable {
        let rawText: String
        /// Core place label for gazetteer lookup.
        let placeQuery: String
        /// Full string passed to geocoder when gazetteer misses.
        let geocodeQuery: String
        let radiusMeters: Double?
    }

    static func parse(_ raw: String) -> Parsed {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Parsed(rawText: "", placeQuery: "", geocodeQuery: "", radiusMeters: nil)
        }

        let lower = trimmed.lowercased()

        // "within 20km of Aurora", "20 km from Toronto", "around 15 miles of Markham"
        if let match = matchRadiusAroundPlace(in: lower, original: trimmed) {
            return match
        }

        // "Aurora within 20km", "Toronto in 25 km"
        if let match = matchPlaceWithinRadius(in: lower, original: trimmed) {
            return match
        }

        return Parsed(
            rawText: trimmed,
            placeQuery: trimmed,
            geocodeQuery: trimmed,
            radiusMeters: nil
        )
    }

    private static func matchRadiusAroundPlace(in lower: String, original: String) -> Parsed? {
        let pattern =
            #"(?i)(?:within\s+)?(\d+(?:\.\d+)?)\s*(km|kilometers?|mi|miles?)\s+(?:of|from|around|near)\s+(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              m.numberOfRanges >= 4,
              let amountRange = Range(m.range(at: 1), in: lower),
              let unitRange = Range(m.range(at: 2), in: lower),
              let placeRange = Range(m.range(at: 3), in: original)
        else {
            return nil
        }

        let amount = Double(lower[amountRange]) ?? 0
        let unit = String(lower[unitRange])
        let place = String(original[placeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0, !place.isEmpty else { return nil }

        return Parsed(
            rawText: original,
            placeQuery: place,
            geocodeQuery: original,
            radiusMeters: meters(amount: amount, unit: unit)
        )
    }

    private static func matchPlaceWithinRadius(in lower: String, original: String) -> Parsed? {
        let pattern = #"(?i)^(.+?)\s+(?:within|in)\s+(\d+(?:\.\d+)?)\s*(km|kilometers?|mi|miles?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              m.numberOfRanges >= 4,
              let placeRange = Range(m.range(at: 1), in: original),
              let amountRange = Range(m.range(at: 2), in: lower),
              let unitRange = Range(m.range(at: 3), in: lower)
        else {
            return nil
        }

        let place = String(original[placeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = Double(lower[amountRange]) ?? 0
        let unit = String(lower[unitRange])
        guard amount > 0, !place.isEmpty else { return nil }

        return Parsed(
            rawText: original,
            placeQuery: place,
            geocodeQuery: original,
            radiusMeters: meters(amount: amount, unit: unit)
        )
    }

    private static func meters(amount: Double, unit: String) -> Double {
        let u = unit.lowercased()
        if u.hasPrefix("mi") {
            return amount * 1609.344
        }
        return amount * 1000
    }
}

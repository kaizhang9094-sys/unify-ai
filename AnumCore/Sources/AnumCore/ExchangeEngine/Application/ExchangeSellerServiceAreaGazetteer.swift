import Foundation

/// Fixed coordinates for common seller service-area labels (Ontario-focused seed gazetteer).
/// Used before optional platform geocoding; not a full worldwide gazetteer.
enum ExchangeSellerServiceAreaGazetteer: Sendable {
    struct Hit: Sendable, Hashable {
        let canonicalName: String
        let coordinate: ExchangeCoordinate
        let defaultRadiusMeters: Double
    }

    static func lookup(normalizedKey: String) -> Hit? {
        let key = normalizedKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty else { return nil }
        return table[key]
    }

    private static let table: [String: Hit] = {
        func hit(
            _ name: String,
            _ keys: [String],
            lat: Double,
            lng: Double,
            radius: Double
        ) -> [(String, Hit)] {
            let coordinate = ExchangeCoordinate(latitude: lat, longitude: lng)
            let value = Hit(
                canonicalName: name,
                coordinate: coordinate,
                defaultRadiusMeters: radius
            )
            return keys.map { ($0, value) }
        }

        var out: [String: Hit] = [:]
        for pair in
            hit("Toronto", ["toronto", "city of toronto"], lat: 43.6532, lng: -79.3832, radius: 20_000)
            + hit("Markham", ["markham"], lat: 43.8561, lng: -79.3370, radius: 12_000)
            + hit("Mississauga", ["mississauga"], lat: 43.5890, lng: -79.6441, radius: 15_000)
            + hit("Aurora", ["aurora"], lat: 44.0065, lng: -79.4504, radius: 12_000)
            + hit(
                "Greater Toronto Area",
                ["gta", "greater toronto area", "greater toronto", "toronto area"],
                lat: 43.7184,
                lng: -79.5181,
                radius: 35_000
            )
        {
            out[pair.0] = pair.1
        }
        return out
    }()
}

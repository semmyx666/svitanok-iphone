import Foundation

struct PublicLocation: Codable, Sendable {
    let id: Int
    let name: String
    let type: String
    let parents: [Int]
}

enum PublicCatalog {
    static let all: [PublicLocation] = {
        guard let url = Bundle.main.url(forResource: "public-locations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([PublicLocation].self, from: data),
              Set(rows.map(\.id)).count == rows.count else { return [] }
        return rows
    }()
    static func find(_ id: Int?) -> PublicLocation? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
    static func oblastUID(for index: Int) -> Int? {
        guard Region.all.indices.contains(index) else { return nil }
        return all.first { $0.name == Region.all[index].name && $0.type == "State" }?.id
    }
}

private struct PublicAlert: Decodable {
    let regionId: String
    let regionType: String
    let type: String
}
private struct PublicRegionResponse: Decodable {
    let regionId: String
    let regionType: String
    let regionName: String
    let activeAlerts: [PublicAlert]
}

enum PublicAlerts {
    static func parse(_ data: Data, uid: Int, serverDate: String?, now: Date) throws -> Snapshot {
        guard data.count <= 65_536, let location = PublicCatalog.find(uid), let serverDate else { throw WakeError.invalidResponse }
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(secondsFromGMT: 0)
        date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let received = date.date(from: serverDate), (-5...45).contains(now.timeIntervalSince(received)) else { throw WakeError.invalidResponse }
        let rows = try JSONDecoder().decode([PublicRegionResponse].self, from: data)
        // Empty/error/partial response is NOT an all-clear. Require the exact selected location.
        guard rows.count == 1, let row = rows.first, row.regionId == String(uid),
              row.regionType == location.type, row.regionName == location.name else { throw WakeError.invalidResponse }
        var active = false
        for alert in row.activeAlerts {
            guard let id = Int(alert.regionId), id == uid || location.parents.contains(id),
                  let scope = PublicCatalog.find(id), scope.type == alert.regionType,
                  ["AIR", "ARTILLERY", "URBAN_FIGHTS", "CHEMICAL", "NUCLEAR"].contains(alert.type) else { throw WakeError.invalidResponse }
            if alert.type == "AIR" { active = true }
        }
        // AIR on a parent oblast/district applies to its child; a sibling's AIR is rejected.
        // No drone coordinates are inferred. Receipt freshness is not an upstream SLA.
        return Snapshot(fetchedAt: received.timeIntervalSince1970, statuses: nil,
                        locationUID: uid, locationStatus: active ? .active : .clear, source: "siren.pp.ua")
    }
}

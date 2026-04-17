import Foundation

struct AppSnapshot: Codable, Sendable {
    let fetchedAt: Date?
    let services: [ServiceSnapshot]

    static let empty = AppSnapshot(fetchedAt: nil, services: [])
}

import Foundation
import SQLite3

struct CursorAuthSession: Sendable {
    let userId: String
    let workosSessionCookieValue: String
    let accountEmail: String?
    let membershipDescription: String?
}

enum CursorAuthReader: Sendable {
    private static let stateDBRelativePath = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    private enum ItemKey {
        static let accessToken = "cursorAuth/accessToken"
        static let cachedEmail = "cursorAuth/cachedEmail"
        static let stripeMembership = "cursorAuth/stripeMembershipType"
        static let stripeStatus = "cursorAuth/stripeSubscriptionStatus"
    }

    static func loadSession() -> CursorAuthSession? {
        let dbURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(Self.stateDBRelativePath)
        guard let items = readItemTable(from: dbURL), let accessToken = items[ItemKey.accessToken], !accessToken.isEmpty else {
            return nil
        }

        guard let userId = JWTSubjectParser.userId(from: accessToken) else {
            return nil
        }

        let cookieValue = "\(userId)%3A%3A\(accessToken)"
        let email = items[ItemKey.cachedEmail].flatMap { $0.isEmpty ? nil : $0 }

        let membershipParts = [items[ItemKey.stripeMembership], items[ItemKey.stripeStatus]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let membershipDescription: String?
        if membershipParts.isEmpty {
            membershipDescription = nil
        } else {
            membershipDescription = membershipParts.joined(separator: " · ")
        }

        return CursorAuthSession(
            userId: userId,
            workosSessionCookieValue: cookieValue,
            accountEmail: email,
            membershipDescription: membershipDescription
        )
    }

    private static func readItemTable(from dbURL: URL) -> [String: String]? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let uri = Self.readOnlySQLiteURI(for: dbURL)
        guard sqlite3_open_v2(uri, &database, flags, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }

        defer {
            sqlite3_close(database)
        }

        sqlite3_busy_timeout(database, 2500)

        let query = """
        SELECT key, value FROM ItemTable WHERE key IN ('\(ItemKey.accessToken)', '\(ItemKey.cachedEmail)', '\(ItemKey.stripeMembership)', '\(ItemKey.stripeStatus)')
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        defer {
            sqlite3_finalize(statement)
        }

        var result: [String: String] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let keyPointer = sqlite3_column_text(statement, 0),
                let valuePointer = sqlite3_column_text(statement, 1)
            else {
                continue
            }

            let key = String(cString: keyPointer)
            let value = String(cString: valuePointer)
            result[key] = value
        }

        return result.isEmpty ? nil : result
    }

    private static func readOnlySQLiteURI(for dbURL: URL) -> String {
        let escapedPath = dbURL.path
            .replacingOccurrences(of: "?", with: "%3f")
            .replacingOccurrences(of: "#", with: "%23")
        return "file:\(escapedPath)?mode=ro"
    }
}

private enum JWTSubjectParser: Sendable {
    static func userId(from jwt: String) -> String? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else {
            return nil
        }

        let payloadSegment = String(segments[1])
        guard let payloadData = base64UrlDecode(payloadSegment) else {
            return nil
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let sub = json["sub"] as? String
        else {
            return nil
        }

        let subParts = sub.split(separator: "|")
        if subParts.count >= 2 {
            return String(subParts[1])
        }

        return sub
    }

    private static func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - base64.count % 4) % 4
        if paddingLength > 0 {
            base64 += String(repeating: "=", count: paddingLength)
        }

        return Data(base64Encoded: base64)
    }
}

import Foundation
import SQLite3

struct ClaudeDesktopSession: Sendable {
    let cookies: [HTTPCookie]
    let organizationUUID: String?
    let deviceID: String?
}

struct ClaudeDesktopCookieReader: Sendable {
    private let cookiesURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/Cookies")

    func loadClaudeSession() -> ClaudeDesktopSession? {
        guard let safeStoragePassword = KeychainReader.readGenericPassword(
            service: "Claude Safe Storage",
            account: "Claude Key"
        ) else {
            return nil
        }

        let rows = readCookieRows()
        guard !rows.isEmpty else {
            return nil
        }

        let decryptor = ChromiumCookieDecryptor(password: safeStoragePassword)
        let now = Date()
        let decryptedRows = rows.compactMap { row -> DecryptedClaudeCookieRow? in
            guard let value = decryptor.decryptCookie(row.encryptedValue, hostKey: row.hostKey) else {
                return nil
            }

            return DecryptedClaudeCookieRow(
                hostKey: row.hostKey,
                name: row.name,
                value: value,
                path: row.path,
                expirationDate: row.expirationDate,
                isSecure: row.isSecure,
                isHTTPOnly: row.isHTTPOnly
            )
        }

        let cookies = decryptedRows.compactMap { row in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: row.hostKey,
                .path: row.path,
                .name: row.name,
                .value: row.value,
                .secure: row.isSecure,
            ]

            if row.isHTTPOnly {
                properties[.init("HttpOnly")] = true
            }

            if let expirationDate = row.expirationDate, expirationDate > now {
                properties[.expires] = expirationDate
            }

            return HTTPCookie(properties: properties)
        }

        guard !cookies.isEmpty else {
            return nil
        }

        return ClaudeDesktopSession(
            cookies: cookies,
            organizationUUID: decryptedRows.first(where: { $0.name == "lastActiveOrg" })?.nonEmptyValue,
            deviceID: decryptedRows.first(where: { $0.name == "anthropic-device-id" })?.nonEmptyValue
        )
    }

    private func readCookieRows() -> [ClaudeCookieRow] {
        let fileManager = FileManager.default
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("agent-stats-claude-cookies-\(UUID().uuidString).sqlite")

        guard (try? fileManager.copyItem(at: cookiesURL, to: temporaryURL)) != nil else {
            return []
        }

        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(temporaryURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            return []
        }

        defer {
            sqlite3_close(database)
        }

        let query = """
        SELECT host_key, name, encrypted_value, path, expires_utc, is_secure, is_httponly
        FROM cookies
        WHERE host_key LIKE '%claude.ai%'
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        var rows: [ClaudeCookieRow] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let hostKeyPointer = sqlite3_column_text(statement, 0),
                let namePointer = sqlite3_column_text(statement, 1),
                let pathPointer = sqlite3_column_text(statement, 3)
            else {
                continue
            }

            let blobBytes = sqlite3_column_blob(statement, 2)
            let blobLength = Int(sqlite3_column_bytes(statement, 2))
            let encryptedValue: Data
            if let blobBytes, blobLength > 0 {
                encryptedValue = Data(bytes: blobBytes, count: blobLength)
            } else {
                encryptedValue = Data()
            }

            rows.append(
                ClaudeCookieRow(
                    hostKey: String(cString: hostKeyPointer),
                    name: String(cString: namePointer),
                    encryptedValue: encryptedValue,
                    path: String(cString: pathPointer),
                    expiresUTC: sqlite3_column_int64(statement, 4),
                    isSecure: sqlite3_column_int(statement, 5) != 0,
                    isHTTPOnly: sqlite3_column_int(statement, 6) != 0
                )
            )
        }

        return rows
    }
}

private struct ClaudeCookieRow {
    let hostKey: String
    let name: String
    let encryptedValue: Data
    let path: String
    let expiresUTC: Int64
    let isSecure: Bool
    let isHTTPOnly: Bool

    var expirationDate: Date? {
        guard expiresUTC > 0 else {
            return nil
        }

        // Chromium stores timestamps as microseconds since 1601-01-01 UTC.
        let seconds = (Double(expiresUTC) / 1_000_000) - 11_644_473_600
        return Date(timeIntervalSince1970: seconds)
    }
}

private struct DecryptedClaudeCookieRow {
    let hostKey: String
    let name: String
    let value: String
    let path: String
    let expirationDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    var nonEmptyValue: String? {
        value.isEmpty ? nil : value
    }
}

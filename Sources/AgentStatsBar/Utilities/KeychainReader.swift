import Foundation
import Security

enum KeychainReader {
    private struct CacheKey: Hashable {
        let service: String
        let account: String?
    }

    private final class SecretCache: @unchecked Sendable {
        private let lock = NSLock()
        private var secrets: [CacheKey: String] = [:]

        func secret(for cacheKey: CacheKey) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return secrets[cacheKey]
        }

        func insert(_ secret: String, for cacheKey: CacheKey) {
            lock.lock()
            defer { lock.unlock() }
            secrets[cacheKey] = secret
        }
    }

    private static let cache = SecretCache()

    static func readGenericPassword(service: String, account: String? = nil) -> String? {
        let cacheKey = CacheKey(service: service, account: account)
        if let cachedSecret = cachedSecret(for: cacheKey) {
            return cachedSecret
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        if let account {
            query[kSecAttrAccount as String] = account
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard
            status == errSecSuccess,
            let data = item as? Data
        else {
            guard let secret = readGenericPasswordViaSecurity(service: service, account: account) else {
                return nil
            }

            cache(secret, for: cacheKey)
            return secret
        }

        guard let secret = normalizedSecret(from: data) else {
            return nil
        }

        cache(secret, for: cacheKey)
        return secret
    }

    private static func readGenericPasswordViaSecurity(service: String, account: String?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")

        var arguments = ["find-generic-password", "-s", service]
        if let account {
            arguments += ["-a", account]
        }
        arguments.append("-w")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        let completion = DispatchGroup()
        completion.enter()
        process.terminationHandler = { _ in
            completion.leave()
        }

        do {
            try process.run()
        } catch {
            completion.leave()
            return nil
        }

        guard completion.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return normalizedSecret(from: data)
    }

    private static func normalizedSecret(from data: Data) -> String? {
        guard let secret = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSecret.isEmpty ? nil : trimmedSecret
    }

    private static func cachedSecret(for cacheKey: CacheKey) -> String? {
        cache.secret(for: cacheKey)
    }

    private static func cache(_ secret: String, for cacheKey: CacheKey) {
        cache.insert(secret, for: cacheKey)
    }
}

import CommonCrypto
import Foundation

struct ChromiumCookieDecryptor: Sendable {
    private let password: String

    init(password: String) {
        self.password = password
    }

    func decryptCookie(_ encryptedValue: Data, hostKey: String) -> String? {
        guard encryptedValue.count > 3 else {
            return nil
        }

        let prefix = encryptedValue.prefix(3)
        guard prefix == Data("v10".utf8) || prefix == Data("v11".utf8) else {
            return String(data: encryptedValue, encoding: .utf8)
        }

        let ciphertext = encryptedValue.dropFirst(3)
        let key = deriveKey()
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)

        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { ciphertextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            ciphertextBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            return nil
        }

        output.removeSubrange(outputLength..<output.count)
        let normalizedOutput = stripChromiumHostKeyPrefixIfPresent(from: output, hostKey: hostKey)
        return String(data: normalizedOutput, encoding: .utf8)
    }

    private func deriveKey() -> Data {
        let passwordData = Data(password.utf8)
        let salt = Data("saltysalt".utf8)
        var derivedKey = Data(count: kCCKeySizeAES128)
        let derivedKeyLength = derivedKey.count

        _ = derivedKey.withUnsafeMutableBytes { derivedBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        derivedKeyLength
                    )
                }
            }
        }

        return derivedKey
    }

    private func stripChromiumHostKeyPrefixIfPresent(from decryptedValue: Data, hostKey: String) -> Data {
        let hostDigest = sha256(Data(hostKey.utf8))
        guard
            decryptedValue.count >= hostDigest.count,
            decryptedValue.prefix(hostDigest.count) == hostDigest
        else {
            return decryptedValue
        }

        return decryptedValue.dropFirst(hostDigest.count)
    }

    private func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }

        return Data(digest)
    }
}

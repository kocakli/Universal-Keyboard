import CommonCrypto
import Foundation

/// Electron / Chromium `safeStorage` on macOS: "v10" + AES-128-CBC (IV of 16 spaces, PKCS#7), with the key derived
/// from the app's "<Name> Safe Storage" Keychain password by PBKDF2-SHA1 ("saltysalt", 1003 rounds).
enum SafeStorage {
    static func deriveKey(password: String) -> Data? {
        let password = Data(password.utf8), salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress, password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeAES128)
                }
            }
        }
        return status == kCCSuccess ? key : nil
    }

    static func decrypt(_ encrypted: Data, password: String, maximumBytes: Int = 65_536) -> Data? {
        guard encrypted.count > 3, encrypted.count <= maximumBytes,
              encrypted.starts(with: Data("v10".utf8)),
              (encrypted.count - 3).isMultiple(of: kCCBlockSizeAES128),
              let key = deriveKey(password: password)
        else { return nil }
        return crypt(CCOperation(kCCDecrypt), Data(encrypted.dropFirst(3)), key: key)
    }

    /// The inverse of `decrypt`, for tests.
    static func encrypt(_ plain: Data, password: String) -> Data? {
        guard let key = deriveKey(password: password),
              let sealed = crypt(CCOperation(kCCEncrypt), plain, key: key) else { return nil }
        return Data("v10".utf8) + sealed
    }

    private static func crypt(_ operation: CCOperation, _ input: Data, key: Data) -> Data? {
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: input.count + kCCBlockSizeAES128), count = 0
        let capacity = output.count
        let result = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress, inputBytes.baseAddress, input.count,
                                outputBytes.baseAddress, capacity, &count)
                    }
                }
            }
        }
        guard result == kCCSuccess else { return nil }
        output.count = count
        return output
    }
}

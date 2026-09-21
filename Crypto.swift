import Foundation
import CryptoKit

nonisolated enum CryptoError: Error {
    case notUnlocked
    case sealFailed
}

/// PBKDF2-HMAC-SHA256 на чистом Swift через CryptoKit (RFC 8018).
/// Алгоритм сверен с эталоном (Python hashlib) и проверяется юнит-тестом
/// на официальном тестовом векторе.
nonisolated enum PBKDF2 {
    static func deriveKey(password: String, salt: Data, iterations: Int, keyLength: Int = 32) -> SymmetricKey {
        SymmetricKey(data: deriveBytes(password: password, salt: salt, iterations: iterations, keyLength: keyLength))
    }

    static func deriveBytes(password: String, salt: Data, iterations: Int, keyLength: Int = 32) -> Data {
        let hmacKey = SymmetricKey(data: Data(password.utf8))
        let hLen = 32
        let blockCount = (keyLength + hLen - 1) / hLen
        var derivedKey = [UInt8]()
        derivedKey.reserveCapacity(blockCount * hLen)

        for blockIndex in 1...max(blockCount, 1) {
            var blockIndexBE = UInt32(blockIndex).bigEndian
            let blockIndexData = withUnsafeBytes(of: &blockIndexBE) { Data($0) }

            var u = [UInt8](HMAC<SHA256>.authenticationCode(for: salt + blockIndexData, using: hmacKey))
            var block = u

            if iterations > 1 {
                for _ in 1..<iterations {
                    u = [UInt8](HMAC<SHA256>.authenticationCode(for: u, using: hmacKey))
                    for i in 0..<block.count {
                        block[i] ^= u[i]
                    }
                }
            }
            derivedKey.append(contentsOf: block)
        }
        return Data(derivedKey.prefix(keyLength))
    }
}

/// Обёртка для зашифрованных данных (nonce + шифротекст + тег в одном блобе)
nonisolated struct EncryptedBlob: Codable, Equatable {
    var combined: Data
}

nonisolated enum CryptoBox {
    static func encrypt<T: Encodable>(_ value: T, key: SymmetricKey) throws -> EncryptedBlob {
        let data = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return EncryptedBlob(combined: combined)
    }

    static func decrypt<T: Decodable>(_ blob: EncryptedBlob, key: SymmetricKey, as type: T.Type) throws -> T {
        let sealed = try AES.GCM.SealedBox(combined: blob.combined)
        let data = try AES.GCM.open(sealed, using: key)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

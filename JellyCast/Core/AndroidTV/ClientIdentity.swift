import Foundation
import Security

/// This iPhone's certificate for the Android TV remote protocol: the TV pairs with it once and
/// recognises it afterwards. Made once and kept in the Keychain.
nonisolated enum ClientIdentity {
    private static let keyTag = Data("nl.jellycast.ios.androidtv.key".utf8)
    private static let certificateLabel = "nl.jellycast.ios.androidtv.certificate"
    private static let commonName = "JellyCast"
    private static let validityYears = 10

    enum Failure: Error { case keyGeneration, signing, certificate, keychain(OSStatus) }

    static func load() throws -> (identity: SecIdentity, certificate: SecCertificate) {
        if let existing = stored() { return existing }
        try create()
        guard let created = stored() else { throw Failure.keychain(errSecItemNotFound) }
        return created
    }

    /// Modulus and exponent as unsigned big-endian bytes, as the pairing secret hashes them.
    static func rsaComponents(of certificate: SecCertificate) -> (modulus: [UInt8], exponent: [UInt8])? {
        guard let key = SecCertificateCopyKey(certificate),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else { return nil }
        return DER.rsaPublicKeyComponents(Array(data))
    }

    private static func stored() -> (identity: SecIdentity, certificate: SecCertificate)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: certificateLabel,
            kSecReturnRef as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let result,
              CFGetTypeID(result) == SecIdentityGetTypeID()
        else { return nil }
        let identity = unsafeDowncast(result, to: SecIdentity.self)
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return nil }
        return (identity, certificate)
    }

    private static func create() throws {
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: certificateLabel] as CFDictionary)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ],
        ]
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else { throw Failure.keyGeneration }
        let tbs = DER.tbsCertificate(
            commonName: commonName, publicKey: Array(publicKeyData), validFrom: .now,
            validUntil: Calendar(identifier: .gregorian).date(byAdding: .year, value: validityYears, to: .now) ?? .now
        )
        guard let signature = SecKeyCreateSignature(
            privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data(tbs) as CFData, nil
        ) as Data? else { throw Failure.signing }
        let der = DER.certificate(tbs: tbs, signature: Array(signature))
        guard let certificate = SecCertificateCreateWithData(nil, Data(der) as CFData) else { throw Failure.certificate }
        let status = SecItemAdd([
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: certificateLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure.keychain(status) }
    }
}

/// Just enough DER to build a self-signed X.509 certificate and read an RSA public key.
nonisolated enum DER {
    private static let sha256WithRSA: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    private static let rsaEncryption: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    private static let commonNameOID: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]
    private static let null: [UInt8] = [0x05, 0x00]

    static func tbsCertificate(commonName: String, publicKey: [UInt8], validFrom: Date, validUntil: Date) -> [UInt8] {
        let name = sequence(set(sequence(commonNameOID + element(0x0C, Array(commonName.utf8)))))
        let algorithm = sequence(sha256WithRSA + null)
        let publicKeyInfo = sequence(sequence(rsaEncryption + null) + element(0x03, [0x00] + publicKey))
        return sequence(
            element(0xA0, integer([2])) + integer([0x10, 0x00]) + algorithm + name
                + sequence(utcTime(validFrom) + utcTime(validUntil)) + name + publicKeyInfo
        )
    }

    static func certificate(tbs: [UInt8], signature: [UInt8]) -> [UInt8] {
        sequence(tbs + sequence(sha256WithRSA + null) + element(0x03, [0x00] + signature))
    }

    /// PKCS#1 `RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }`.
    static func rsaPublicKeyComponents(_ bytes: [UInt8]) -> (modulus: [UInt8], exponent: [UInt8])? {
        var index = 0
        guard let sequence = read(bytes, &index, tag: 0x30) else { return nil }
        var inner = 0
        guard let modulus = read(sequence, &inner, tag: 0x02), let exponent = read(sequence, &inner, tag: 0x02) else {
            return nil
        }
        return (Array(modulus.drop { $0 == 0 }), Array(exponent.drop { $0 == 0 }))
    }

    private static func read(_ bytes: [UInt8], _ index: inout Int, tag: UInt8) -> [UInt8]? {
        guard index < bytes.count, bytes[index] == tag else { return nil }
        index += 1
        guard index < bytes.count else { return nil }
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard index + count <= bytes.count else { return nil }
            length = bytes[index..<index + count].reduce(0) { $0 << 8 | Int($1) }
            index += count
        }
        guard index + length <= bytes.count else { return nil }
        defer { index += length }
        return Array(bytes[index..<index + length])
    }

    private static func element(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    private static func sequence(_ content: [UInt8]) -> [UInt8] { element(0x30, content) }

    private static func set(_ content: [UInt8]) -> [UInt8] { element(0x31, content) }

    private static func integer(_ value: [UInt8]) -> [UInt8] {
        element(0x02, (value.first ?? 0) & 0x80 != 0 ? [0] + value : value)
    }

    private static func utcTime(_ date: Date) -> [UInt8] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return element(0x17, Array(formatter.string(from: date).utf8))
    }

    private static func length(_ count: Int) -> [UInt8] {
        guard count >= 0x80 else { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}

import Foundation
import CryptoKit
import LocalAuthentication
import Security

enum SecureCredentialError: LocalizedError {
    case emptyPassword
    case sessionLocked
    case unsupportedHardware
    case invalidVault

    var errorDescription: String? {
        switch self {
        case .emptyPassword: return "Password cannot be empty."
        case .sessionLocked: return "Unlock your Faceprint session first."
        case .unsupportedHardware: return "This Mac does not offer an available Secure Enclave."
        case .invalidVault: return "The saved Faceprint vault cannot be read. Its data has been preserved."
        }
    }
}

/// The Secure Enclave holds the private key. Its opaque representation can be
/// saved without inserting a biometric item into the data-protection Keychain,
/// which requires provisioning unavailable to this locally signed app.
enum SecureCredentialManager {
    private struct Vault: Codable {
        var version = 1
        let keyRepresentation: Data
        let peerPublicKey: Data
        let salt: Data
        var password: Data?
        var face: Data?
    }

    private static let lock = NSLock()
    private static var key: SymmetricKey?
    private static var vault: Vault?
    private static var activity: Date?

    // Retain the prototype storage location and derivation context so renaming
    // the app keeps existing hardware-protected passwords and face templates usable.
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlanceFill", isDirectory: true)
            .appendingPathComponent("vault-v1.json")
    }

    static var isSessionUnlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return key != nil
    }

    static var lastActivityAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        return activity
    }

    private static func readVault() throws -> Vault? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue < 4 * 1024 * 1024 else {
            throw SecureCredentialError.invalidVault
        }
        let saved = try JSONDecoder().decode(Vault.self, from: Data(contentsOf: fileURL))
        guard saved.version == 1, saved.peerPublicKey.count == 65,
              saved.salt.count == 32, !saved.keyRepresentation.isEmpty,
              saved.keyRepresentation.count < 65536 else { throw SecureCredentialError.invalidVault }
        return saved
    }

    private static func writeVault(_ saved: Vault) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(saved).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func deriveKey(from saved: Vault, context: LAContext) throws -> SymmetricKey {
        let protected = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            dataRepresentation: saved.keyRepresentation, authenticationContext: context
        )
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: saved.peerPublicKey)
        let secret = try protected.sharedSecretFromKeyAgreement(with: peer)
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: saved.salt,
            sharedInfo: Data("local.giao.glancefill.vault.v1".utf8), outputByteCount: 32
        )
    }

    /// Checks the ad-hoc runtime's hardware-key support without an auth prompt,
    /// persistent data, or access to the user's saved secrets.
    static func checkProtectionAvailability() throws {
        guard SecureEnclave.isAvailable else { throw SecureCredentialError.unsupportedHardware }
        let context = LAContext()
        context.interactionNotAllowed = true
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence], nil
        ) else { throw SecureCredentialError.unsupportedHardware }
        let probe = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access,
                                                                 authenticationContext: context)
        let restored = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: probe.dataRepresentation,
                                                                      authenticationContext: context)
        guard probe.publicKey.x963Representation == restored.publicKey.x963Representation else {
            throw SecureCredentialError.invalidVault
        }
    }

    /// Runs off the main thread. The ECDH operation itself requires userPresence
    /// inside the Secure Enclave. A separate yes/no authentication gate is not used.
    static func unlockSession(reason: String, authenticationContext: LAContext? = nil) throws {
        if isSessionUnlocked { return }
        guard SecureEnclave.isAvailable else { throw SecureCredentialError.unsupportedHardware }
        let context = authenticationContext ?? LAContext()
        context.localizedReason = reason
        let saved: Vault
        let creating: Bool
        if let existing = try readVault() {
            saved = existing
            creating = false
        } else {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.privateKeyUsage, .userPresence], &error
            ) else {
                if let error { throw error.takeRetainedValue() as Error }
                throw SecureCredentialError.unsupportedHardware
            }
            let protected = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                accessControl: access, authenticationContext: context
            )
            let peer = P256.KeyAgreement.PrivateKey()
            var salt = Data(count: 32)
            let status = salt.withUnsafeMutableBytes { bytes in
                SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
            }
            guard status == errSecSuccess else { throw SecureCredentialError.invalidVault }
            saved = Vault(keyRepresentation: protected.dataRepresentation,
                          peerPublicKey: peer.publicKey.x963Representation, salt: salt)
            creating = true
        }
        let sessionKey = try deriveKey(from: saved, context: context)
        if creating { try writeVault(saved) }
        lock.lock()
        vault = saved
        key = sessionKey
        activity = Date()
        lock.unlock()
    }

    static func lockSession() {
        lock.lock()
        key = nil
        vault = nil
        activity = nil
        lock.unlock()
    }

    static func hasStoredPassword() -> Bool { (try? readVault())?.password != nil }

    private static func save(_ plaintext: Data, face: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let key, var updated = vault else { throw SecureCredentialError.sessionLocked }
        let purpose = Data((face ? "face.v1" : "password.v1").utf8)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: purpose)
        guard let ciphertext = sealed.combined else { throw SecureCredentialError.invalidVault }
        if face { updated.face = ciphertext } else { updated.password = ciphertext }
        try writeVault(updated)
        vault = updated
        activity = Date()
    }

    private static func read(face: Bool) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let key, let vault else { throw SecureCredentialError.sessionLocked }
        guard let ciphertext = face ? vault.face : vault.password else { return nil }
        let sealed = try AES.GCM.SealedBox(combined: ciphertext)
        let plaintext = try AES.GCM.open(sealed, using: key,
                                        authenticating: Data((face ? "face.v1" : "password.v1").utf8))
        activity = Date()
        return plaintext
    }

    static func savePassword(_ bytes: Data) throws {
        guard !bytes.isEmpty else { throw SecureCredentialError.emptyPassword }
        try save(bytes, face: false)
    }

    static func readPassword() throws -> Data {
        guard let data = try read(face: false) else { throw SecureCredentialError.emptyPassword }
        return data
    }

    static func saveFaceData(_ data: Data) throws { try save(data, face: true) }
    static func readFaceData() throws -> Data? { try read(face: true) }

    static func deleteSavedData() throws {
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        key = nil
        vault = nil
        activity = nil
    }
}

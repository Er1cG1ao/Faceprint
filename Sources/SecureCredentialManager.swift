import Foundation
import CryptoKit
import LocalAuthentication
import Security

enum SecureCredentialError: LocalizedError, Equatable {
    case emptyPassword
    case sessionLocked
    case unsupportedHardware
    case invalidVault
    case migrationRequired

    var errorDescription: String? {
        switch self {
        case .emptyPassword: return "Password cannot be empty."
        case .sessionLocked: return "Unlock your Faceprint session first."
        case .unsupportedHardware: return "This Mac does not offer an available Secure Enclave."
        case .invalidVault: return "The saved Faceprint vault cannot be read. Its data has been preserved."
        case .migrationRequired: return "Unlock Settings once to upgrade saved data for automatic filling."
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
    private static let openingLock = NSLock()
    private static var revision: UInt64 = 0
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
        guard (1...2).contains(saved.version), saved.peerPublicKey.count == 65,
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
            sharedInfo: Data("local.giao.glancefill.vault.v\(saved.version)".utf8), outputByteCount: 32
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
            [.privateKeyUsage], nil
        ) else { throw SecureCredentialError.unsupportedHardware }
        let probe = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access,
                                                                 authenticationContext: context)
        let restored = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: probe.dataRepresentation,
                                                                      authenticationContext: context)
        guard probe.publicKey.x963Representation == restored.publicKey.x963Representation else {
            throw SecureCredentialError.invalidVault
        }
        // Exercise the actual noninteractive ECDH operation, not just key parsing.
        let peer = P256.KeyAgreement.PrivateKey()
        _ = try restored.sharedSecretFromKeyAgreement(with: peer.publicKey)
    }

    /// New vaults use a device-only hardware key available while the Mac is
    /// unlocked. Only a legacy v1 migration needs the explicit Settings LAContext.
    static func openAutofillStore(authenticationContext: LAContext? = nil) throws {
        openingLock.lock()
        defer { openingLock.unlock() }
        lock.lock()
        let ticket = revision
        let alreadyOpen = key != nil
        lock.unlock()
        if alreadyOpen { return }
        guard SecureEnclave.isAvailable else { throw SecureCredentialError.unsupportedHardware }
        let background = LAContext()
        background.interactionNotAllowed = true
        let existing = try readVault()
        var saved: Vault
        let sessionKey: SymmetricKey
        var mustWrite = false
        if let existing, existing.version == 1 {
            guard let authenticationContext else { throw SecureCredentialError.migrationRequired }
            // Settings has already authenticated. Never open a second Resume prompt.
            authenticationContext.interactionNotAllowed = true
            let oldKey = try deriveKey(from: existing, context: authenticationContext)
            (saved, sessionKey) = try createAutomaticVault(context: background)
            let migrated = try reencrypt(password: existing.password, face: existing.face,
                                         from: oldKey, to: sessionKey)
            saved.password = migrated.password
            saved.face = migrated.face
            mustWrite = true
        } else if let existing {
            saved = existing
            sessionKey = try deriveKey(from: saved, context: background)
        } else {
            (saved, sessionKey) = try createAutomaticVault(context: background)
            mustWrite = true
        }
        lock.lock()
        defer { lock.unlock() }
        guard ticket == revision else { throw SecureCredentialError.sessionLocked }
        if mustWrite {
            if existing?.version == 1 {
                let backup = fileURL.deletingLastPathComponent().appendingPathComponent("vault-v1-before-automatic.json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try Data(contentsOf: fileURL).write(to: backup, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                }
            }
            // Nothing is replaced until BOTH legacy payloads authenticate/decrypt.
            try writeVault(saved)
        }
        vault = saved
        key = sessionKey
        activity = Date()
    }

    private static func createAutomaticVault(context: LAContext) throws -> (Vault, SymmetricKey) {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], &error) else {
            if let error { throw error.takeRetainedValue() as Error }
            throw SecureCredentialError.unsupportedHardware
        }
        let protected = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access, authenticationContext: context)
        let peer = P256.KeyAgreement.PrivateKey()
        var salt = Data(count: 32)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }) == errSecSuccess else {
            throw SecureCredentialError.invalidVault
        }
        let saved = Vault(version: 2, keyRepresentation: protected.dataRepresentation,
                          peerPublicKey: peer.publicKey.x963Representation, salt: salt)
        return (saved, try deriveKey(from: saved, context: context))
    }

    static func reencrypt(password: Data?, face: Data?, from old: SymmetricKey,
                          to new: SymmetricKey) throws -> (password: Data?, face: Data?) {
        func reseal(_ data: Data?, purpose: String) throws -> Data? {
            guard let data else { return nil }
            var plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: old,
                                             authenticating: Data(purpose.utf8))
            defer { plaintext.resetBytes(in: 0..<plaintext.count) }
            guard let sealed = try AES.GCM.seal(plaintext, using: new, authenticating: Data(purpose.utf8)).combined else {
                throw SecureCredentialError.invalidVault
            }
            return sealed
        }
        return (try reseal(password, purpose: "password.v1"), try reseal(face, purpose: "face.v1"))
    }

    static func lockSession() {
        lock.lock()
        revision &+= 1
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
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("vault-v1-before-automatic.json")
        for path in [backup, fileURL] where FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        revision &+= 1
        key = nil
        vault = nil
        activity = nil
    }
}

import Foundation
import CryptoKit
import Security
import Darwin

enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ string: String) {
        let value = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(pieces.count), pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              pieces.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = pieces.map { Int($0)! }
    }
    static func == (a: Self, b: Self) -> Bool { !(a < b) && !(b < a) }
    static func < (a: Self, b: Self) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int64
        let digest: String?
        let browser_download_url: String
    }
    let tag_name: String
    let html_url: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    func available(after installed: String) throws -> ReleaseUpdate? {
        guard !draft, !prerelease else { return nil }
        guard let version = ReleaseVersion(tag_name), let current = ReleaseVersion(installed) else {
            throw UpdateError.message("This release has an unsupported version number.")
        }
        guard version > current else { return nil }
        let plain = tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
        let expected = "Faceprint-\(plain)-macos-arm64.zip"
        guard let asset = assets.first(where: { $0.name == expected }),
              (1...UpdatePolicy.maximumArchiveBytes).contains(asset.size),
              let digest = asset.digest, digest.hasPrefix("sha256:"),
              UpdatePolicy.validDigest(String(digest.dropFirst(7))),
              let url = URL(string: asset.browser_download_url),
              UpdatePolicy.isReleaseAsset(url, tag: tag_name, filename: expected),
              let page = URL(string: html_url), UpdatePolicy.isReleasePage(page, tag: tag_name) else {
            throw UpdateError.message("The release needs a compatible arm64 ZIP and GitHub SHA-256 digest.")
        }
        return ReleaseUpdate(version: plain, tag: tag_name, url: url, page: page,
                             digest: String(digest.dropFirst(7)).lowercased(), size: asset.size)
    }
}

struct ReleaseUpdate: Sendable {
    let version: String
    let tag: String
    let url: URL
    let page: URL
    let digest: String
    let size: Int64
}

enum UpdatePolicy {
    static let bundleID = "io.github.er1cg1ao.faceprint"
    static let maximumArchiveBytes: Int64 = 512 * 1024 * 1024
    static let apiURL = URL(string: "https://api.github.com/repos/Er1cG1ao/Faceprint/releases/latest")!
    static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
    private static func plainHTTPS(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil && url.query == nil && url.fragment == nil
    }
    static func isReleaseAsset(_ url: URL, tag: String, filename: String) -> Bool {
        plainHTTPS(url) && url.host == "github.com" && url.path == "/Er1cG1ao/Faceprint/releases/download/\(tag)/\(filename)"
    }
    static func isReleasePage(_ url: URL, tag: String) -> Bool {
        plainHTTPS(url) && url.host == "github.com" && url.path == "/Er1cG1ao/Faceprint/releases/tag/\(tag)"
    }
    static func allowedDownloadHost(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil else { return false }
        return ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }
    static func installLocationAllowed(_ url: URL, userApplications: URL) -> Bool {
        let normalized = url.standardizedFileURL
        let parent = normalized.deletingLastPathComponent()
        guard normalized.path == url.resolvingSymlinksInPath().standardizedFileURL.path,
              parent.path == parent.resolvingSymlinksInPath().standardizedFileURL.path,
              normalized.pathExtension == "app" else { return false }
        return parent.path == "/Applications" || parent.path == userApplications.standardizedFileURL.path
    }
}

/// Inspect ZIP paths and file kinds before invoking the native extractor. Update
/// packages contain one self-contained app, with no symlinks or ZIP64 entries.
enum UpdateArchive {
    static func validate(_ data: Data) throws {
        func fail() -> UpdateError { .message("The update ZIP contains unsupported or unsafe entries.") }
        func u16(_ i: Int) throws -> Int {
            guard i >= 0, i + 2 <= data.count else { throw fail() }
            return Int(data[i]) | Int(data[i + 1]) << 8
        }
        func u32(_ i: Int) throws -> Int {
            guard i >= 0, i + 4 <= data.count else { throw fail() }
            return Int(data[i]) | Int(data[i + 1]) << 8 | Int(data[i + 2]) << 16 | Int(data[i + 3]) << 24
        }
        guard data.count >= 22, Int64(data.count) <= UpdatePolicy.maximumArchiveBytes else { throw fail() }
        var end: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try u32(i) == 0x06054b50, try i + 22 + u16(i + 20) == data.count { end = i; break }
        }
        guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0,
              try u16(end + 8) == u16(end + 10) else { throw fail() }
        let count = try u16(end + 10)
        var index = try u32(end + 16)
        let centralEnd = try index + u32(end + 12)
        guard count > 0, count < 20000, centralEnd == end else { throw fail() }
        var total: Int64 = 0
        var seen = Set<String>()
        for _ in 0..<count {
            guard try u32(index) == 0x02014b50 else { throw fail() }
            let flags = try u16(index + 8)
            let method = try u16(index + 10)
            let packed = try u32(index + 20)
            let unpacked = try u32(index + 24)
            let nameLength = try u16(index + 28)
            let extraLength = try u16(index + 30)
            let commentLength = try u16(index + 32)
            let unixKind = try (u32(index + 38) >> 16) & 0o170000
            let local = try u32(index + 42)
            let nameStart = index + 46
            guard nameLength > 0, nameStart + nameLength <= centralEnd,
                  let name = String(data: data[nameStart..<(nameStart + nameLength)], encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  name.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }),
                  name == "Faceprint.app/" || name.hasPrefix("Faceprint.app/"),
                  seen.insert(name.lowercased()).inserted,
                  unixKind == 0 || unixKind == 0o100000 || unixKind == 0o040000,
                  flags & 1 == 0, method == 0 || method == 8,
                  packed < 0xffffffff, unpacked < 0xffffffff,
                  try u16(index + 34) == 0, try u32(local) == 0x04034b50,
                  try u16(local + 26) == nameLength else { throw fail() }
            let localNameStart = local + 30
            let bodyStart = try localNameStart + nameLength + u16(local + 28)
            guard localNameStart + nameLength <= data.count,
                  data[localNameStart..<(localNameStart + nameLength)] == data[nameStart..<(nameStart + nameLength)],
                  bodyStart <= index, bodyStart + packed <= index else { throw fail() }
            total += Int64(unpacked)
            guard total <= 2 * 1024 * 1024 * 1024 else { throw fail() }
            index = nameStart + nameLength + extraLength + commentLength
            guard index <= centralEnd else { throw fail() }
        }
        guard index == centralEnd, seen.contains("faceprint.app/contents/info.plist"),
              seen.contains("faceprint.app/contents/macos/faceprint") else { throw fail() }
    }

    static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct AppUpdateIdentity {
    let code: SecStaticCode
    let info: [String: Any]
    let requirement: SecRequirement
    var isAdHoc: Bool { ((info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0) & 2 != 0 }
    init(_ app: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) == errSecSuccess else {
            throw UpdateError.message("The application code signature is invalid.")
        }
        var info: CFDictionary?
        var requirement: SecRequirement?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any], info[kSecCodeInfoIdentifier as String] as? String == UpdatePolicy.bundleID,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement else {
            throw UpdateError.message("The update does not have Faceprint's code identity.")
        }
        self.code = code; self.info = info; self.requirement = requirement
    }
    static func check(candidate: URL, installed: URL) throws -> Bool {
        let old = try Self(installed)
        let new = try Self(candidate)
        let forward = SecStaticCodeCheckValidity(new.code, [], old.requirement) == errSecSuccess
        let reverse = SecStaticCodeCheckValidity(old.code, [], new.requirement) == errSecSuccess
        if !old.isAdHoc && (!forward || !reverse || new.isAdHoc) {
            throw UpdateError.message("The update's signing identity differs from the installed app. Installation was stopped.")
        }
        return !old.isAdHoc && !new.isAdHoc && forward && reverse
    }
}

struct UpdateInstallJob: Codable {
    let parentPID: Int32
    let workspace: URL
    let destination: URL
    let replacement: URL
    let expectedVersion: String
    let installedVersion: String
    let archiveDigest: String
}

enum UpdateInstaller {
    static func run(_ executable: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run(); task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdateError.message("Update step failed: \(URL(fileURLWithPath: executable).lastPathComponent).") }
    }
    static func verifyVersion(at url: URL, equals expected: String) throws {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == UpdatePolicy.bundleID,
              info?["CFBundleExecutable"] as? String == "Faceprint",
              info?["CFBundleShortVersionString"] as? String == expected,
              Bundle(url: url)?.executableArchitectures?.contains(NSNumber(value: 0x0100000c)) == true,
              let minOS = info?["LSMinimumSystemVersion"] as? String,
              let os = ReleaseVersion(minOS) else { throw UpdateError.message("The update app metadata does not match the release.") }
        let current = ProcessInfo.processInfo.operatingSystemVersion
        guard let running = ReleaseVersion("\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"),
              running >= os else { throw UpdateError.message("This update requires a newer macOS version.") }
    }
    static func atomicSwap(_ first: URL, _ second: URL) throws {
        guard renameatx_np(AT_FDCWD, first.path, AT_FDCWD, second.path, UInt32(RENAME_SWAP)) == 0 else {
            throw UpdateError.message("Could not replace Faceprint (\(String(cString: strerror(errno)))). The installed app was kept.")
        }
    }
    static func replace(_ job: UpdateInstallJob,
                        userApplications: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")) throws -> URL {
        let fm = FileManager.default
        guard UpdatePolicy.installLocationAllowed(job.destination, userApplications: userApplications),
              job.replacement.standardizedFileURL == job.workspace.appendingPathComponent("extracted/Faceprint.app").standardizedFileURL,
              job.workspace.path == job.workspace.resolvingSymlinksInPath().path,
              let old = ReleaseVersion(job.installedVersion), let new = ReleaseVersion(job.expectedVersion), new > old,
              try UpdateArchive.digest(of: job.workspace.appendingPathComponent("update.zip")) == job.archiveDigest else {
            throw UpdateError.message("The update installation job is invalid.")
        }
        try verifyVersion(at: job.destination, equals: job.installedVersion)
        try verifyVersion(at: job.replacement, equals: job.expectedVersion)
        _ = try AppUpdateIdentity.check(candidate: job.replacement, installed: job.destination)
        let sibling = job.destination.deletingLastPathComponent().appendingPathComponent(".Faceprint-backup-\(UUID().uuidString).app")
        try fm.copyItem(at: job.replacement, to: sibling)
        do {
            try verifyVersion(at: sibling, equals: job.expectedVersion)
            _ = try AppUpdateIdentity.check(candidate: sibling, installed: job.destination)
            try atomicSwap(sibling, job.destination)
        } catch { try? fm.removeItem(at: sibling); throw error }
        // The old bundle is retained beside the new one as a recovery copy.
        return sibling
    }
}

struct UpdateReceipt: Codable { let message: String }

enum UpdatePaths {
    static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.er1cg1ao.faceprint/Updates", isDirectory: true)
    }
    static var receipt: URL { root.appendingPathComponent("last-result.json") }
    static func makeWorkspace() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let workspace = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return workspace.resolvingSymlinksInPath()
    }
}

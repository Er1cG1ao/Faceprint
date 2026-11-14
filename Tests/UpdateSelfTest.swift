import Foundation

@main
enum UpdateSelfTest {
    static func check(_ condition: Bool, _ message: String = "Assertion failed", file: StaticString = #fileID, line: UInt = #line) { precondition(condition, message, file: file, line: line) }
    static func reject(_ action: () throws -> Void, _ message: String) {
        do { try action(); preconditionFailure(message) } catch { }
    }
    static func release(_ edits: [String: Any] = [:], assetEdits: [String: Any] = [:]) throws -> GitHubRelease {
        var asset: [String: Any] = ["name": "Faceprint-2.0.0-macos-arm64.zip", "size": 100,
            "digest": "sha256:" + String(repeating: "a", count: 64),
            "browser_download_url": "https://github.com/Er1cG1ao/Faceprint/releases/download/v2.0.0/Faceprint-2.0.0-macos-arm64.zip"]
        asset.merge(assetEdits) { _, value in value }
        var payload: [String: Any] = ["tag_name": "v2.0.0", "html_url": "https://github.com/Er1cG1ao/Faceprint/releases/tag/v2.0.0",
                                   "draft": false, "prerelease": false, "assets": [asset]]
        payload.merge(edits) { _, value in value }
        return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    static func zip(_ names: [(String, UInt32, UInt32)]) -> Data {
        func short(_ x: Int) -> Data { Data([UInt8(x & 255), UInt8((x >> 8) & 255)]) }
        func long(_ x: UInt32) -> Data { Data((0..<4).map { UInt8((x >> ($0 * 8)) & 255) }) }
        var local = Data(), central = Data()
        for (name, attributes, size) in names {
            let utf = Data(name.utf8)
            let offset = local.count
            local += long(0x04034b50) + short(20) + short(0) + short(0) + short(0) + short(0)
            local += long(0) + long(0) + long(size) + short(utf.count) + short(0) + utf
            central += long(0x02014b50) + short(0x0314) + short(20) + short(0) + short(0) + short(0) + short(0)
            central += long(0) + long(0) + long(size) + short(utf.count) + short(0) + short(0) + short(0) + short(0)
            central += long(attributes) + long(UInt32(offset)) + utf
        }
        return local + central + long(0x06054b50) + short(0) + short(0) + short(names.count) + short(names.count)
            + long(UInt32(central.count)) + long(UInt32(local.count)) + short(0)
    }

    static func main() throws {
        setbuf(stdout, nil)
        check(ReleaseVersion("v1.10.0")! > ReleaseVersion("1.9.9")!)
        check(ReleaseVersion("1.5") == ReleaseVersion("1.5.0"))
        check(ReleaseVersion("1.5-beta") == nil && ReleaseVersion("1..5") == nil)
        let good = try release()
        check(try good.available(after: "1.5.0")?.version == "2.0.0")
        check(try good.available(after: "2.0.0") == nil)
        check(try good.available(after: "3.0.0") == nil)
        check(try release(["draft": true]).available(after: "1.0.0") == nil)
        check(try release(["prerelease": true]).available(after: "1.0.0") == nil)
        reject({ _ = try release(assetEdits: ["digest": NSNull()]).available(after: "1.0.0") }, "Missing digest")
        reject({ _ = try release(assetEdits: ["digest": "sha256:bad"]).available(after: "1.0.0") }, "Malformed digest")
        reject({ _ = try release(assetEdits: ["size": Int64.max]).available(after: "1.0.0") }, "Oversize asset")
        reject({ _ = try release(assetEdits: ["name": "Faceprint-2.0.0-macos-intel.zip"]).available(after: "1.0.0") }, "Wrong architecture")
        for url in ["https://evil.test/update.zip", "http://github.com/Er1cG1ao/Faceprint/releases/download/v2.0.0/Faceprint-2.0.0-macos-arm64.zip",
                    "https://github.com/other/Faceprint/releases/download/v2.0.0/Faceprint-2.0.0-macos-arm64.zip"] {
            reject({ _ = try release(assetEdits: ["browser_download_url": url]).available(after: "1.0.0") }, "Wrong release host/repository")
        }
        check(!UpdatePolicy.allowedDownloadHost(URL(string: "https://github.com.evil.test")!))
        check(!UpdatePolicy.allowedDownloadHost(URL(string: "http://release-assets.githubusercontent.com/file")!))
        check(UpdatePolicy.allowedDownloadHost(URL(string: "https://release-assets.githubusercontent.com/path?token=x")!))
        print("PASS update versions, downgrade/prerelease exclusion, asset/digest/size and HTTPS repository/redirect scope")

        let base: [(String, UInt32, UInt32)] = [("Faceprint.app/Contents/Info.plist", 0o100644 << 16, 0),
                                                 ("Faceprint.app/Contents/MacOS/Faceprint", 0o100755 << 16, 0)]
        try UpdateArchive.validate(zip(base))
        for name in ["/tmp/evil", "Faceprint.app/../../escape", "Faceprint.app/./file", "Faceprint.app/Contents\\evil", "Else.app/Contents/file", "Faceprint.app/Contents/\u{0}evil"] {
            reject({ try UpdateArchive.validate(zip(base + [(name, 0o100644 << 16, 0)])) }, "Unsafe archive path")
        }
        reject({ try UpdateArchive.validate(zip(base + [("Faceprint.app/Contents/link", 0o120777 << 16, 0)])) }, "Archive symlink")
        reject({ try UpdateArchive.validate(zip(base + [("faceprint.app/contents/info.plist", 0o100644 << 16, 0)])) }, "Duplicate case-folded path")
        reject({ try UpdateArchive.validate(zip(base + [("Faceprint.app/huge", 0o100644 << 16, UInt32.max - 1)])) }, "ZIP bomb bound")
        let valid = zip(base)
        reject({ try UpdateArchive.validate(valid.dropLast()) }, "Truncated archive")
        var mismatch = valid; mismatch[30] = 88
        reject({ try UpdateArchive.validate(mismatch) }, "Local/central filename mismatch")
        print("PASS ZIP local/central path agreement, traversal/symlink/duplicate rejection and expansion limits")

        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FaceprintUpdateTest-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let first = root.appendingPathComponent("first"), second = root.appendingPathComponent("second")
        try fm.createDirectory(at: first, withIntermediateDirectories: false)
        try fm.createDirectory(at: second, withIntermediateDirectories: false)
        try Data("old".utf8).write(to: first.appendingPathComponent("marker"))
        try Data("new".utf8).write(to: second.appendingPathComponent("marker"))
        try UpdateInstaller.atomicSwap(first, second)
        check(try String(contentsOf: first.appendingPathComponent("marker"), encoding: .utf8) == "new")
        check(try String(contentsOf: second.appendingPathComponent("marker"), encoding: .utf8) == "old")
        try UpdateInstaller.atomicSwap(first, second)
        check(try String(contentsOf: first.appendingPathComponent("marker"), encoding: .utf8) == "old")
        reject({ try UpdateInstaller.atomicSwap(first, root.appendingPathComponent("missing")) }, "Failed swap")
        check(try String(contentsOf: first.appendingPathComponent("marker"), encoding: .utf8) == "old", "Failed replacement preserves old app")
        let userApps = root.appendingPathComponent("Applications")
        check(UpdatePolicy.installLocationAllowed(userApps.appendingPathComponent("Faceprint.app"), userApplications: userApps))
        check(!UpdatePolicy.installLocationAllowed(root.appendingPathComponent("Faceprint.app"), userApplications: userApps))
        try fm.createSymbolicLink(at: root.appendingPathComponent("Applications"), withDestinationURL: first)
        check(!UpdatePolicy.installLocationAllowed(userApps.appendingPathComponent("Faceprint.app"), userApplications: userApps), "Install paths cannot traverse symlinks")
        print("PASS atomic replacement/recovery, failed-swap preservation and install-location/symlink guards")

        if CommandLine.arguments.count >= 3 {
            let archive = URL(fileURLWithPath: CommandLine.arguments[1])
            let app = URL(fileURLWithPath: CommandLine.arguments[2])
            try UpdateArchive.validate(Data(contentsOf: archive, options: .mappedIfSafe))
            check(UpdatePolicy.validDigest(try UpdateArchive.digest(of: archive)))
            let info = try AppUpdateIdentity(app)
            let copy = root.appendingPathComponent("Faceprint.app")
            try fm.copyItem(at: app, to: copy)
            check(try AppUpdateIdentity.check(candidate: copy, installed: app) == !info.isAdHoc)
            let plist = copy.appendingPathComponent("Contents/Info.plist")
            try Data("corrupt".utf8).write(to: plist)
            reject({ _ = try AppUpdateIdentity.check(candidate: copy, installed: app) }, "Tampered app")
            if CommandLine.arguments.count >= 4 {
                let oldApp = URL(fileURLWithPath: CommandLine.arguments[3])
                let oldVersion = try PropertyListSerialization.propertyList(from: Data(contentsOf: oldApp.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
                let newVersion = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
                let oldNumber = oldVersion["CFBundleShortVersionString"] as! String
                let newNumber = newVersion["CFBundleShortVersionString"] as! String
                try fm.removeItem(at: userApps)
                try fm.createDirectory(at: userApps, withIntermediateDirectories: false)
                let installedApp = userApps.appendingPathComponent("Faceprint.app")
                try fm.copyItem(at: oldApp, to: installedApp)
                let workspace = root.appendingPathComponent("job")
                let extracted = workspace.appendingPathComponent("extracted")
                try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
                let replacement = extracted.appendingPathComponent("Faceprint.app")
                try fm.copyItem(at: app, to: replacement)
                try fm.copyItem(at: archive, to: workspace.appendingPathComponent("update.zip"))
                let job = UpdateInstallJob(parentPID: ProcessInfo.processInfo.processIdentifier,
                    workspace: workspace, destination: installedApp, replacement: replacement,
                    expectedVersion: newNumber, installedVersion: oldNumber, archiveDigest: try UpdateArchive.digest(of: archive))
                let mismatchJob = UpdateInstallJob(parentPID: job.parentPID, workspace: workspace,
                    destination: installedApp, replacement: replacement, expectedVersion: newNumber,
                    installedVersion: oldNumber, archiveDigest: String(repeating: "0", count: 64))
                reject({ _ = try UpdateInstaller.replace(mismatchJob, userApplications: userApps) }, "Digest mismatch installation")
                try UpdateInstaller.verifyVersion(at: installedApp, equals: oldNumber)
                let backup = try UpdateInstaller.replace(job, userApplications: userApps)
                try UpdateInstaller.verifyVersion(at: installedApp, equals: newNumber)
                try UpdateInstaller.verifyVersion(at: backup, equals: oldNumber)
                _ = try AppUpdateIdentity(installedApp)
                _ = try AppUpdateIdentity(backup)
                print("PASS real signed bundle installation \(oldNumber) → \(newNumber), digest rejection and retained recovery copy in temporary Applications")
            }
            print("PASS real package inspection, signed app-copy validation and tampered bundle rejection")
        }
    }
}

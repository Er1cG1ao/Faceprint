import AppKit
import Combine
import Foundation

private final class GitHubDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let expectedSize: Int64
    let progress: @Sendable (Double) -> Void
    init(expectedSize: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.expectedSize = expectedSize; self.progress = progress
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(UpdatePolicy.allowedDownloadHost) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= expectedSize, totalBytesWritten <= UpdatePolicy.maximumArchiveBytes else {
            downloadTask.cancel(); return
        }
        progress(min(1, Double(totalBytesWritten) / Double(max(1, expectedSize))))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var status = "Check GitHub for a newer release."
    @Published private(set) var checking = false
    @Published private(set) var installing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var available: ReleaseUpdate?
    @Published private(set) var automaticallyChecks = UserDefaults.standard.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
    @Published private(set) var signingNote = "Checking signing identity…"
    var canModifySettings: () -> Bool = { false }
    var prepareToRestart: () -> Void = {}
    private var task: Task<Void, Never>?
    private let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    init() {
        Task {
            let adhoc = await Task.detached { (try? AppUpdateIdentity(Bundle.main.bundleURL).isAdHoc) ?? true }.value
            signingNote = adhoc
                ? "This test build uses ad hoc signing. An update may require Camera and Accessibility access again. A consistent signing certificate is needed to preserve permissions."
                : "Updates must keep this app’s signing identity. macOS controls permission continuity."
        }
        let receipt = UpdatePaths.receipt
        if let data = try? Data(contentsOf: receipt),
           let result = try? JSONDecoder().decode(UpdateReceipt.self, from: data) {
            status = result.message
            try? FileManager.default.removeItem(at: receipt)
        }
    }

    func setAutomaticallyChecks(_ value: Bool) {
        guard canModifySettings() else { return }
        automaticallyChecks = value
        UserDefaults.standard.set(value, forKey: "automaticallyChecksForUpdates")
    }

    func checkAutomaticallyIfNeeded() {
        guard automaticallyChecks else { return }
        let last = UserDefaults.standard.object(forKey: "lastSuccessfulUpdateCheck") as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= 24 * 60 * 60 { check() }
    }

    func check() {
        guard !checking, !installing else { return }
        checking = true
        status = "Checking GitHub…"
        task = Task {
            defer { checking = false }
            do {
                var request = URLRequest(url: UpdatePolicy.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Faceprint/\(installed)", forHTTPHeaderField: "User-Agent")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.url?.host == "api.github.com", data.count <= 2 * 1024 * 1024 else {
                    throw UpdateError.message("GitHub could not return a release. Try again later (API limits may apply).")
                }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                available = try release.available(after: installed)
                status = available.map { "Faceprint \($0.version) is available." } ?? "You’re up to date (\(installed))."
                UserDefaults.standard.set(Date(), forKey: "lastSuccessfulUpdateCheck")
            } catch { status = "Update check failed: \(error.localizedDescription)" }
        }
    }

    func install() {
        guard canModifySettings(), !checking, !installing, let update = available else { return }
        let app = Bundle.main.bundleURL.standardizedFileURL
        let fm = FileManager.default
        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        guard UpdatePolicy.installLocationAllowed(app, userApplications: userApps),
              fm.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            status = "Move Faceprint to Applications (or ~/Applications) before installing updates."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Install Faceprint \(update.version)?"
        alert.informativeText = "Faceprint will download the release from GitHub, verify it, replace this app and restart. Your saved faces, password and preferences stay in place.\n\n\(signingNote)"
        alert.addButton(withTitle: "Install and Restart")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, canModifySettings() else { return }
        installing = true; progress = 0
        task = Task { [self] in
            var workspace: URL?
            var helperStarted = false
            defer {
                if !helperStarted, let workspace { try? fm.removeItem(at: workspace) }
                installing = false
            }
            do {
                let root = try UpdatePaths.makeWorkspace()
                workspace = root
                let archive = root.appendingPathComponent("update.zip")
                status = "Downloading Faceprint \(update.version)…"
                let delegate = GitHubDownloadDelegate(expectedSize: update.size) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 300
                let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (download, response) = try await session.download(for: URLRequest(url: update.url))
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.url.map(UpdatePolicy.allowedDownloadHost) == true,
                      (try fm.attributesOfItem(atPath: download.path)[.size] as? NSNumber)?.int64Value == update.size else {
                    throw UpdateError.message("The downloaded update has an unexpected response or size.")
                }
                try fm.moveItem(at: download, to: archive)
                status = "Verifying download and application…"
                let keepPermissions = try await Task.detached(priority: .userInitiated) {
                    guard try UpdateArchive.digest(of: archive) == update.digest else {
                        throw UpdateError.message("The update download failed its SHA-256 check.")
                    }
                    try UpdateArchive.validate(Data(contentsOf: archive, options: .mappedIfSafe))
                    let extracted = root.appendingPathComponent("extracted", isDirectory: true)
                    try fm.createDirectory(at: extracted, withIntermediateDirectories: false)
                    try UpdateInstaller.run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
                    let candidate = extracted.appendingPathComponent("Faceprint.app")
                    try UpdateInstaller.verifyVersion(at: candidate, equals: update.version)
                    return try AppUpdateIdentity.check(candidate: candidate, installed: app)
                }.value
                try Task.checkCancellation()
                guard canModifySettings() else { throw UpdateError.message("Unlock the session and install again.") }
                status = keepPermissions ? "Verified signing continuity. Restarting…" : "Verified update. Restarting; macOS may request permissions again."
                let helperSource = app.appendingPathComponent("Contents/Helpers/FaceprintUpdateInstaller")
                let helper = root.appendingPathComponent("FaceprintUpdateInstaller")
                try fm.copyItem(at: helperSource, to: helper)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
                let job = UpdateInstallJob(parentPID: ProcessInfo.processInfo.processIdentifier,
                    workspace: root, destination: app, replacement: root.appendingPathComponent("extracted/Faceprint.app"),
                    expectedVersion: update.version, installedVersion: installed, archiveDigest: update.digest)
                let jobURL = root.appendingPathComponent("job.json")
                try JSONEncoder().encode(job).write(to: jobURL, options: .atomic)
                let process = Process()
                process.executableURL = helper
                process.arguments = [jobURL.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                helperStarted = true
                prepareToRestart()
                NSApp.terminate(nil)
            } catch { status = "Update was not installed: \(error.localizedDescription)" }
        }
    }
}

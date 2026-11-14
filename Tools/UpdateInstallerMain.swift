import Foundation
import Darwin

@main
enum FaceprintUpdateInstallerMain {
    static func main() {
        var destination: URL?
        var recovery: URL?
        do {
            guard CommandLine.arguments.count == 2 else { throw UpdateError.message("Missing update job.") }
            let jobURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
            let attributes = try FileManager.default.attributesOfItem(atPath: jobURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max < 65536 else { throw UpdateError.message("Invalid update job.") }
            let job = try JSONDecoder().decode(UpdateInstallJob.self, from: Data(contentsOf: jobURL))
            let expectedRoot = UpdatePaths.root.resolvingSymlinksInPath()
            guard job.workspace.deletingLastPathComponent().path == expectedRoot.path,
                  jobURL == job.workspace.appendingPathComponent("job.json"), job.parentPID > 1 else {
                throw UpdateError.message("Unexpected update workspace.")
            }
            destination = job.destination
            // Parent must exit before its mapped app bundle is replaced. Never
            // kill it, request administrator access or modify the TCC database.
            let deadline = Date().addingTimeInterval(60)
            while kill(job.parentPID, 0) == 0 {
                guard Date() < deadline else { throw UpdateError.message("Faceprint did not quit; update cancelled.") }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard errno == ESRCH else { throw UpdateError.message("Could not confirm that Faceprint quit.") }
            let backup = try UpdateInstaller.replace(job)
            recovery = backup
            try JSONEncoder().encode(UpdateReceipt(message: "Updated to \(job.expectedVersion). Previous app saved as \(backup.lastPathComponent)."))
                .write(to: UpdatePaths.receipt, options: .atomic)
            try UpdateInstaller.run("/usr/bin/open", [job.destination.path])
            try? FileManager.default.removeItem(at: job.workspace)
        } catch {
            if let recovery, let destination {
                try? UpdateInstaller.atomicSwap(recovery, destination)
            }
            let result = UpdateReceipt(message: "Update failed: \(error.localizedDescription)")
            try? JSONEncoder().encode(result).write(to: UpdatePaths.receipt, options: .atomic)
            if let destination { try? UpdateInstaller.run("/usr/bin/open", [destination.path]) }
        }
    }
}

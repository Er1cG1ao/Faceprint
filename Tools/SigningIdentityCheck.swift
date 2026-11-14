import Foundation
import Security
import Darwin

/// Validate Apple's signature chain and pin the default designated requirement.
/// This never invents or weakens requirements to make TCC accept an update.
@main
enum SigningIdentityCheck {
    static func main() {
        do { try check() }
        catch {
            FileHandle.standardError.write(Data("Signing check failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    private static func check() throws {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--inspect-archive" {
            try UpdateArchive.validate(Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe))
            print("Update archive paths and limits verified.")
            return
        }
        guard args.count == 3 || args.count == 4 else {
            throw UpdateError.message("Usage: SigningIdentityCheck APP BASELINE [REFERENCE_APP]")
        }
        let app = URL(fileURLWithPath: CommandLine.arguments[1])
        let baseline = URL(fileURLWithPath: CommandLine.arguments[2])
        let identity = try AppUpdateIdentity(app)
        guard !identity.isAdHoc else { throw UpdateError.message("Ad hoc signing cannot provide stable update identity.") }
        var apple: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &apple) == errSecSuccess,
              let apple, SecStaticCodeCheckValidity(identity.code, [], apple) == errSecSuccess,
              let team = identity.info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else {
            throw UpdateError.message("Expected a valid Apple-issued signing identity with a Team ID.")
        }
        var raw: CFData?
        guard SecRequirementCopyData(identity.requirement, [], &raw) == errSecSuccess, let raw else {
            throw UpdateError.message("Could not obtain the application's designated requirement.")
        }
        let requirement = raw as Data
        if args.count == 4 {
            guard try AppUpdateIdentity.check(candidate: app, installed: URL(fileURLWithPath: args[3])) else {
                throw UpdateError.message("Cross-version signing requirements are not compatible.")
            }
            print("Mutually compatible cross-version signing identity verified.")
        }
        if FileManager.default.fileExists(atPath: baseline.path) {
            let previous = try Data(contentsOf: baseline)
            guard previous == requirement else {
                throw UpdateError.message("Signing identity requirements changed. Build stopped to avoid silently changing permission identity.")
            }
            print("Stable signing verified: Team \(team); designated requirement unchanged.")
        } else {
            try requirement.write(to: baseline, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: baseline.path)
            print("Stable signing baseline recorded: Team \(team).")
        }
    }
}

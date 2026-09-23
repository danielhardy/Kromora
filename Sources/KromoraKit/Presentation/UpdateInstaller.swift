#if KROMORA_DIRECT_DISTRIBUTION
import AppKit
import Foundation
import Security

/// Downloads, verifies, and installs the Kromora app contained in a release DMG.
///
/// The downloaded app must satisfy a requirement built from the currently running app: Apple
/// anchored Developer ID signing, the same Team ID, the same bundle identifier, and strict nested
/// validation. An unsigned `swift run` process has no identity to compare and can never install.
public enum KromoraUpdateInstaller {
    public enum InstallError: LocalizedError, Equatable {
        case notAnAppBundle
        case runningAppUnsigned
        case noDiskImage
        case insecureDownloadURL
        case mountFailed(String)
        case noAppInImage
        case signatureRejected(String)
        case destinationNotWritable(URL)
        case swapFailed(String)
        case downloadFailed(Int)

        public var errorDescription: String? {
            switch self {
            case .notAnAppBundle:
                return "This build is not an app bundle, so it cannot replace itself. Download the release instead."
            case .runningAppUnsigned:
                return "This copy of Kromora is not signed, so a downloaded update cannot be verified against it."
            case .noDiskImage:
                return "The release has no disk image to install from."
            case .insecureDownloadURL:
                return "The release download did not use HTTPS."
            case .mountFailed(let detail): return "The disk image could not be opened. \(detail)"
            case .noAppInImage: return "The disk image does not contain a Kromora app."
            case .signatureRejected(let detail):
                return "The downloaded app failed signature verification and was discarded. \(detail)"
            case .destinationNotWritable(let url):
                return "Kromora cannot write to \(url.path). Move the app somewhere you own, or install the update by hand."
            case .swapFailed(let detail): return "The update could not be put in place. \(detail)"
            case .downloadFailed(let status): return "The release download failed with status \(status)."
            }
        }
    }

    public struct SigningIdentity: Sendable, Equatable {
        public let teamID: String
        public let bundleID: String

        public init(teamID: String, bundleID: String) {
            self.teamID = teamID
            self.bundleID = bundleID
        }
    }

    public static func signingIdentity(of bundleURL: URL) -> SigningIdentity? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let teamID = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              let bundleID = dictionary[kSecCodeInfoIdentifier as String] as? String else {
            return nil
        }
        return SigningIdentity(teamID: teamID, bundleID: bundleID)
    }

    public static var runningAppBundle: URL? {
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.pathExtension.lowercased() == "app" ? bundleURL : nil
    }

    public static var canInstallInPlace: Bool {
        // Confirmed permanently false, not pending validation: a signed, sandboxed, provisioned
        // build tested against a real Developer ID identity shows `hdiutil attach` fails under
        // App Sandbox ("Device not configured") — Seatbelt denies the block-device access it
        // needs, with no entitlement able to grant it. See docs/PACKAGING.md's "Sandboxed
        // updater validation" section for the full test method and result.
        false
    }

    public static func download(_ url: URL, session: URLSession = .shared) async throws -> URL {
        guard url.scheme?.lowercased() == "https" else { throw InstallError.insecureDownloadURL }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kromora Update \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (temporaryURL, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.downloadFailed(http.statusCode)
        }
        let filename = url.lastPathComponent.isEmpty ? "update.dmg" : url.lastPathComponent
        let destination = directory.appendingPathComponent(filename)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    public static func mount(_ dmg: URL) async throws -> URL {
        let mountPoint = dmg.deletingLastPathComponent().appendingPathComponent("mount", isDirectory: true)
        let result = try await run("/usr/bin/hdiutil", [
            "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-noverify",
            "-mountpoint", mountPoint.path,
        ])
        guard result.status == 0 else { throw InstallError.mountFailed(result.output) }
        return mountPoint
    }

    public static func detach(_ mountPoint: URL) async {
        _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
    }

    public static func findApp(in mountPoint: URL) throws -> URL {
        let entries = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
        guard let app = entries.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw InstallError.noAppInImage
        }
        return app
    }

    public static func verify(_ appURL: URL, against identity: SigningIdentity) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            throw InstallError.signatureRejected("The app could not be read.")
        }

        let team = requirementEscaped(identity.teamID)
        let bundle = requirementEscaped(identity.bundleID)
        let requirementText = "anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6]"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"
            + " and certificate leaf[subject.OU] = \"\(team)\""
            + " and identifier \"\(bundle)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            throw InstallError.signatureRejected("The verification requirement could not be built.")
        }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        var errors: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &errors)
        guard status == errSecSuccess else {
            let detail = errors?.takeRetainedValue().localizedDescription ?? "OSStatus \(status)"
            throw InstallError.signatureRejected(detail)
        }
    }

    static func swap(newApp: URL, into currentApp: URL, identity: SigningIdentity) throws {
        try swap(newApp: newApp, into: currentApp) { staged in
            try verify(staged, against: identity)
        }
    }

    /// The verifier seam lets tests exercise the failure boundary without manufacturing a
    /// Developer ID signed app bundle. Production callers use the identity-based overload.
    static func swap(
        newApp: URL,
        into currentApp: URL,
        verifyStaged: (URL) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let parent = currentApp.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw InstallError.destinationNotWritable(parent)
        }
        let token = UUID().uuidString
        let staged = parent.appendingPathComponent(".Kromora-update-\(token).app")
        let retired = parent.appendingPathComponent(".Kromora-old-\(token).app")
        do {
            try fileManager.copyItem(at: newApp, to: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw InstallError.swapFailed(error.localizedDescription)
        }

        do {
            try verifyStaged(staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            if let installError = error as? InstallError,
               case .signatureRejected = installError {
                throw installError
            }
            throw InstallError.signatureRejected(error.localizedDescription)
        }

        do {
            try fileManager.moveItem(at: currentApp, to: retired)
            try fileManager.moveItem(at: staged, to: currentApp)
        } catch {
            try? fileManager.removeItem(at: staged)
            if fileManager.fileExists(atPath: retired.path), !fileManager.fileExists(atPath: currentApp.path) {
                try? fileManager.moveItem(at: retired, to: currentApp)
            }
            throw InstallError.swapFailed(error.localizedDescription)
        }
        try? fileManager.removeItem(at: retired)
    }

    @MainActor
    public static func relaunch(_ appURL: URL) {
        let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, appURL.path, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        UpdateCoordinator.log.info("relaunch helper started; terminating")
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UpdateCoordinator.log.info("terminate was ignored; exiting")
            exit(0)
        }
    }

    public static func install(_ release: KromoraRelease) async throws -> URL {
        guard let currentApp = runningAppBundle else { throw InstallError.notAnAppBundle }
        guard let identity = signingIdentity(of: currentApp) else { throw InstallError.runningAppUnsigned }
        guard let diskImageURL = release.diskImageURL else { throw InstallError.noDiskImage }

        let dmg = try await download(diskImageURL)
        UpdateCoordinator.log.info("downloaded \(dmg.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: dmg.deletingLastPathComponent()) }
        let mountPoint = try await mount(dmg)
        UpdateCoordinator.log.info("mounted update image")
        do {
            let newApp = try findApp(in: mountPoint)
            try verify(newApp, against: identity)
            UpdateCoordinator.log.info("signature verified for team \(identity.teamID)")
            try swap(newApp: newApp, into: currentApp, identity: identity)
            UpdateCoordinator.log.info("swapped update into place")
        } catch {
            await detach(mountPoint)
            throw error
        }
        await detach(mountPoint)
        return currentApp
    }

    private struct RunResult: Sendable {
        let status: Int32
        let output: String
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws -> RunResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: RunResult(status: process.terminationStatus, output: output))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func requirementEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

#endif

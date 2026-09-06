import Foundation
import CryptoKit

public enum LauncherError: LocalizedError {
    case unsupportedMac, invalidDownload, checksumMismatch, invalidBundle, destinationExists, commandFailed(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedMac: "This launcher requires Apple Silicon and macOS 14 or later. "
        case .invalidDownload: "The launcher download failed. Check your connection and try again."
        case .checksumMismatch: "The download did not match the verified release. Nothing was installed. Try again or check the upstream release."
        case .invalidBundle: "The launcher app is incomplete or unrecognized. Reveal its folder and move it aside before retrying."
        case .destinationExists: "An installation already exists. It has been left untouched."
        case .commandFailed(let message): message
        }
    }
}

public enum Release {
    public static let version = "5.0.5"
    public static let appName = "UTM.app"
    public static let bundleID = "com.utmapp.UTM"
    public static let executable = "UTM"
    public static let download = URL(string: "https://github.com/utmapp/UTM/releases/download/v5.0.5/UTM.dmg")!
    public static let sha256 = "713afe73c711f01344b8766654be531cd391ed2e30931206f43b5159f143764f"
    public static let project = URL(string: "https://github.com/utmapp/UTM/releases/tag/v5.0.5")!

    public static func verify(_ data: Data, expected: String = sha256) throws {
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw LauncherError.checksumMismatch }
    }
}

public struct MacHardware: Sendable {
    public let appleSilicon: Bool
    public let majorVersion: Int
    public var supported: Bool { appleSilicon && majorVersion >= 14 }
    public init(appleSilicon: Bool, majorVersion: Int) {
        self.appleSilicon = appleSilicon
        self.majorVersion = majorVersion
    }
    public static var current: MacHardware {
        var arm64: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &arm64, &size, nil, 0)
        return MacHardware(appleSilicon: arm64 == 1, majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}

public struct LauncherInstallation: Sendable {
    public let root: URL
    public var app: URL { root.appendingPathComponent(Release.appName) }
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacBedrock/Engine")) {
        self.root = root
    }
    public var isInstalled: Bool { (try? Self.validateBundle(app)) != nil }

    public static func validateBundle(_ url: URL) throws {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Release.bundleID,
              info["CFBundleExecutable"] as? String == Release.executable,
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/\(Release.executable)").path)
        else { throw LauncherError.invalidBundle }
    }

    /// Copies beside the destination, validates, then renames on the same volume.
    /// A failed install cannot replace an existing app or affect Minecraft worlds.
    public func commitBundle(from source: URL) throws {
        let fm = FileManager.default
        try Self.validateBundle(source)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: app.path) else { throw LauncherError.destinationExists }
        let staging = root.appendingPathComponent(".install-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: staging) }
        try Self.run("/usr/bin/ditto", [source.path, staging.path])
        try Self.validateBundle(staging)
        // Preserve macOS's first-open security review for this internet download.
        let quarantine = "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));MacBedrock;"
        try Self.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", quarantine, staging.path])
        try fm.moveItem(at: staging, to: app)
    }

    public func install(progress: @escaping @Sendable (String) async -> Void) async throws {
        guard MacHardware.current.supported else { throw LauncherError.unsupportedMac }
        if isInstalled { return }
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("MacBedrock-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        await progress("Downloading launcher \(Release.version)…")
        var request = URLRequest(url: Release.download)
        request.timeoutInterval = 90
        let (downloaded, response) = try await URLSession.shared.download(for: request)
        defer { try? fm.removeItem(at: downloaded) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LauncherError.invalidDownload }
        try Task.checkCancellation()
        await progress("Verifying SHA-256 checksum…")
        try Release.verify(Data(contentsOf: downloaded, options: .mappedIfSafe))
        let dmg = temporary.appendingPathComponent("launcher.dmg")
        try fm.moveItem(at: downloaded, to: dmg)
        let mount = temporary.appendingPathComponent("mount")
        await progress("Installing the verified launcher…")
        try Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        defer { try? Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }
        try Task.checkCancellation()
        let source = mount.appendingPathComponent(Release.appName)
        try Self.verifySignature(source)
        try commitBundle(from: source)
        await progress("Windows engine installed. Next: prepare your environment.")
    }

    public static func verifySignature(_ app: URL) throws {
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
    }

    public static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // File output avoids pipe-buffer deadlocks while waiting for hdiutil/ditto.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("MacBedrock-command-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = (try? String(contentsOf: log, encoding: .utf8)) ?? "Unknown system error"
            throw LauncherError.commandFailed("\(URL(fileURLWithPath: executable).lastPathComponent) failed: \(details.suffix(1500))")
        }
    }
}

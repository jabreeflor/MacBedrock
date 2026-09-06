import Foundation
import CryptoKit

public struct WindowsEnvironment: Sendable {
    public static let name = "MacBedrock Windows"
    public static let windowsSHA = "638aa2c88e94385b00f4f178d071e3df0b7d9e335577a83bd533b7f2eb65adf0"
    public static let toolsSHA = "7d2c0343e92358ad5e65078b08ec1dad873eb91b3c154aef60531bf6c2f04601"
    public static let toolsURL = URL(string: "https://github.com/utmapp/qemu/releases/download/v10.0.12-utm/utm-guest-tools-0.1.273.iso")!
    public let root: URL
    public var bundle: URL { root.appendingPathComponent("Environments/\(Self.name).utm") }
    public var media: URL { root.appendingPathComponent("Media") }
    public var windowsISO: URL { media.appendingPathComponent("Windows11-ARM64.iso") }
    public var engine: LauncherInstallation { LauncherInstallation(root: root.appendingPathComponent("Engine")) }
    public var isPrepared: Bool {
        let fm = FileManager.default
        return ["config.plist", "Data/windows.raw", "Data/efi_vars.fd", "Data/Windows11-ARM64.iso", "Data/drivers.iso"].allSatisfy { fm.fileExists(atPath: bundle.appendingPathComponent($0).path) }
    }
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacBedrock")) { self.root = root }

    /// Streams multi-gigabyte installer images instead of loading them into RAM.
    public static func verifyFile(_ url: URL, expected: String) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected.lowercased() else {
            throw LauncherError.checksumMismatch
        }
    }

    public static func configuration(id: UUID = UUID()) -> [String: Any] {
        func drive(_ name: String, _ type: String, _ interface: String, _ readOnly: Bool) -> [String: Any] {
            ["ImageName": name, "ImageType": type, "Interface": interface, "InterfaceVersion": 1, "Identifier": UUID().uuidString, "ReadOnly": readOnly]
        }
        let mac = "02:" + (0..<5).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined(separator: ":")
        return [
            "Backend": "QEMU", "ConfigurationVersion": 4,
            "Information": ["Name": name, "UUID": id.uuidString, "Icon": "windows", "IconCustom": false, "Notes": "Microsoft Store Bedrock environment. Experimental DirectX 11; game compatibility is unverified."],
            "System": ["Architecture": "aarch64", "Target": "virt", "CPU": "default", "CPUFlagsAdd": [], "CPUFlagsRemove": [], "CPUCount": 4, "ForceMulticore": false, "MemorySize": 8192, "JITCacheSize": 0],
            "QEMU": ["DebugLog": true, "UEFIBoot": true, "RNGDevice": true, "BalloonDevice": false, "TPMDevice": true, "Hypervisor": true, "TSO": false, "RTCLocalTime": true, "PS2Controller": false, "AdditionalArguments": []],
            "Input": ["UsbBusSupport": "3.0", "UsbSharing": false, "MaximumUsbShare": 0],
            "Sharing": ["DirectoryShareMode": "None", "DirectoryShareReadOnly": true, "ClipboardSharing": false],
            "Display": [["Hardware": "virtio-ramfb-gl", "DynamicResolution": true, "UpscalingFilter": "Linear", "DownscalingFilter": "Linear", "NativeResolution": false]],
            "Drive": [drive("windows.raw", "Disk", "NVMe", false), drive("Windows11-ARM64.iso", "CD", "USB", true), drive("drivers.iso", "CD", "USB", true)],
            "Network": [["Mode": "Emulated", "Hardware": "virtio-net-pci", "MacAddress": mac, "IsolateFromHost": false, "PortForward": []]],
            "Serial": [], "Sound": [["Hardware": "intel-hda"]]
        ]
    }

    public func prepare(iso: URL, progress: @escaping @Sendable (String) async -> Void) async throws {
        guard MacHardware.current.supported else { throw LauncherError.unsupportedMac }
        guard ProcessInfo.processInfo.physicalMemory >= 16 * 1024 * 1024 * 1024 else {
            throw LauncherError.commandFailed("This 8 GB VM profile requires a Mac with at least 16 GB RAM.")
        }
        if isPrepared { return }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: bundle.path) else { throw LauncherError.destinationExists }
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        let available = try media.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= 32 * 1024 * 1024 * 1024 else {
            throw LauncherError.commandFailed("Free at least 32 GB on this volume before creating Windows. The virtual disk can grow to 80 GB; monitor your Mac’s free space.")
        }
        await progress("Verifying Windows 11 25H2 English ARM64 v2 ISO…")
        try Self.verifyFile(iso, expected: Self.windowsSHA)
        try await engine.install(progress: progress)
        try LauncherInstallation.verifySignature(engine.app)
        let tools = media.appendingPathComponent("utm-guest-tools.iso")
        if !fm.fileExists(atPath: tools.path) {
            await progress("Downloading Windows graphics and device drivers…")
            let (download, response) = try await URLSession.shared.download(from: Self.toolsURL)
            defer { try? fm.removeItem(at: download) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LauncherError.invalidDownload }
            try Self.verifyFile(download, expected: Self.toolsSHA)
            try fm.moveItem(at: download, to: tools)
        }
        try Self.verifyFile(tools, expected: Self.toolsSHA)
        await progress("Creating your Windows environment…")
        let driverMedia = try Self.createDriverMedia(from: tools)
        defer { try? fm.removeItem(at: driverMedia.deletingLastPathComponent()) }
        try createBundle(iso: iso, tools: driverMedia, firmware: engine.app.appendingPathComponent("Contents/Resources/qemu/edk2-arm-secure-vars.fd"))
        await progress("Environment prepared. Open Windows to finish installation.")
    }

    /// Exclude upstream Autounattend.xml: it conflicts with this installer and
    /// changes Windows account/security defaults. Keep ordinary Windows Setup.
    public static func createDriverMedia(from source: URL) throws -> URL {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("MacBedrockDrivers-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        var complete = false
        defer { if !complete { try? fm.removeItem(at: temp) } }
        let mount = temp.appendingPathComponent("mount")
        try LauncherInstallation.run("/usr/bin/hdiutil", ["attach", source.path, "-readonly", "-nobrowse", "-mountpoint", mount.path])
        defer { try? LauncherInstallation.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }
        let contents = temp.appendingPathComponent("contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        for name in ["Drivers", "utm-guest-tools.exe", "Uninstall-VirtioGpu.cmd", "virtio-win_license.txt"] {
            try fm.copyItem(at: mount.appendingPathComponent(name), to: contents.appendingPathComponent(name))
        }
        let output = temp.appendingPathComponent("drivers.iso")
        try LauncherInstallation.run("/usr/bin/hdiutil", ["makehybrid", "-iso", "-joliet", "-default-volume-name", "MacBedrock-Drivers", "-o", output.path, contents.path])
        complete = true
        return output
    }

    /// The only replacement is a same-volume rename of a new bundle. Existing VMs are never overwritten.
    public func createBundle(iso: URL, tools: URL, firmware: URL) throws {
        let fm = FileManager.default
        let parent = bundle.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: bundle.path) else { throw LauncherError.destinationExists }
        let staging = parent.appendingPathComponent(".prepare-\(UUID().uuidString).utm")
        defer { try? fm.removeItem(at: staging) }
        let data = staging.appendingPathComponent("Data")
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        for (source, name) in [(iso, "Windows11-ARM64.iso"), (tools, "drivers.iso"), (firmware, "efi_vars.fd")] {
            // APFS clones avoid another 8 GB of physical installer storage. Fall back to copy on other filesystems.
            let destination = data.appendingPathComponent(name)
            do { try LauncherInstallation.run("/bin/cp", ["-c", source.path, destination.path]) }
            catch { try fm.copyItem(at: source, to: destination) }
        }
        let disk = data.appendingPathComponent("windows.raw")
        guard fm.createFile(atPath: disk.path, contents: nil) else { throw LauncherError.commandFailed("Could not create virtual disk.") }
        let handle = try FileHandle(forWritingTo: disk)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 80 * 1024 * 1024 * 1024)
        try handle.synchronize()
        let config = try PropertyListSerialization.data(fromPropertyList: Self.configuration(), format: .xml, options: 0)
        try config.write(to: staging.appendingPathComponent("config.plist"), options: .atomic)
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: bundle)
    }
}

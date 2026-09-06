import Foundation
import XCTest
@testable import MacBedrockCore

final class WindowsEnvironmentTests: XCTestCase {
    func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WindowsEnvironmentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testProfileUsesHardwareVirtualizationAndPrivatePersistentDisk() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: WindowsEnvironment.configuration(), format: .xml, options: 0)
        let profile = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let system = try XCTUnwrap(profile["System"] as? [String: Any])
        XCTAssertEqual(system["Architecture"] as? String, "aarch64")
        let qemu = try XCTUnwrap(profile["QEMU"] as? [String: Any])
        for key in ["Hypervisor", "UEFIBoot", "TPMDevice"] { XCTAssertEqual(qemu[key] as? Bool, true) }
        let network = try XCTUnwrap((profile["Network"] as? [[String: Any]])?.first)
        XCTAssertEqual(network["Mode"] as? String, "Emulated")
        XCTAssertEqual((network["PortForward"] as? [Any])?.count, 0)
        let sharing = try XCTUnwrap(profile["Sharing"] as? [String: Any])
        XCTAssertEqual(sharing["DirectoryShareMode"] as? String, "None")
        let drives = try XCTUnwrap(profile["Drive"] as? [[String: Any]])
        XCTAssertEqual(drives.count, 3)
        XCTAssertEqual(drives[0]["Interface"] as? String, "NVMe")
        XCTAssertEqual(drives[2]["ImageName"] as? String, "drivers.iso")
        XCTAssertTrue(drives.allSatisfy { !($0["ImageName"] as! String).contains("/") })
        XCTAssertEqual(drives[1]["ReadOnly"] as? Bool, true)
        XCTAssertEqual(drives[2]["ReadOnly"] as? Bool, true)
    }
    func testStreamingChecksumRejectsTampering() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("test.iso")
        try Data("abc".utf8).write(to: file)
        let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try WindowsEnvironment.verifyFile(file, expected: hash)
        try Data("abd".utf8).write(to: file)
        XCTAssertThrowsError(try WindowsEnvironment.verifyFile(file, expected: hash))
    }
    func testCreationIsAtomicSparseAndNeverReplacesExistingWorlds() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try Data("fixture".utf8).write(to: source)
        let environment = WindowsEnvironment(root: root.appendingPathComponent("directory with spaces"))
        XCTAssertThrowsError(try environment.createBundle(iso: source, tools: root.appendingPathComponent("missing"), firmware: source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.bundle.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: environment.bundle.deletingLastPathComponent().path), [])
        try environment.createBundle(iso: source, tools: source, firmware: source)
        XCTAssertTrue(environment.isPrepared)
        let disk = environment.bundle.appendingPathComponent("Data/windows.raw")
        XCTAssertEqual(try disk.resourceValues(forKeys: [.fileSizeKey]).fileSize, 80 * 1024 * 1024 * 1024)
        XCTAssertLessThan(try disk.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize ?? Int.max, 1024 * 1024)
        let handle = try FileHandle(forWritingTo: disk)
        try handle.write(contentsOf: Data("worlds".utf8)); try handle.close()
        XCTAssertThrowsError(try environment.createBundle(iso: source, tools: source, firmware: source))
        let reader = try FileHandle(forReadingFrom: disk); defer { try? reader.close() }
        XCTAssertEqual(try reader.read(upToCount: 6), Data("worlds".utf8))
    }
    func testDriverMediaDoesNotCarryUnattendedWindowsSettings() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Drivers"), withIntermediateDirectories: true)
        for name in ["utm-guest-tools.exe", "Uninstall-VirtioGpu.cmd", "virtio-win_license.txt", "Autounattend.xml"] {
            try Data(name.utf8).write(to: contents.appendingPathComponent(name))
        }
        let original = root.appendingPathComponent("original.iso")
        try LauncherInstallation.run("/usr/bin/hdiutil", ["makehybrid", "-iso", "-joliet", "-o", original.path, contents.path])
        let output = try WindowsEnvironment.createDriverMedia(from: original)
        defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
        let mount = root.appendingPathComponent("result")
        try LauncherInstallation.run("/usr/bin/hdiutil", ["attach", output.path, "-readonly", "-nobrowse", "-mountpoint", mount.path])
        defer { try? LauncherInstallation.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: mount.appendingPathComponent("Autounattend.xml").path))
        XCTAssertEqual(try Data(contentsOf: mount.appendingPathComponent("utm-guest-tools.exe")), Data("utm-guest-tools.exe".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mount.appendingPathComponent("Drivers").path))
    }
}

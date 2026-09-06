import Foundation
import XCTest
@testable import MacBedrockCore

final class LauncherTests: XCTestCase {
    func testKnownSHA256AndTampering() throws {
        try Release.verify(Data("abc".utf8), expected: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertThrowsError(try Release.verify(Data("abd".utf8), expected: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    }
    func testHardwareGate() {
        XCTAssertTrue(MacHardware(appleSilicon: true, majorVersion: 14).supported)
        XCTAssertFalse(MacHardware(appleSilicon: false, majorVersion: 26).supported)
        XCTAssertFalse(MacHardware(appleSilicon: true, majorVersion: 13).supported)
    }
    func testMissingOrWrongBundleIsRejected() throws {
        let temp = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        XCTAssertThrowsError(try LauncherInstallation.validateBundle(temp))
        let app = try fixture(in: temp)
        let plist = app.appendingPathComponent("Contents/Info.plist")
        try Data("not a plist".utf8).write(to: plist)
        XCTAssertThrowsError(try LauncherInstallation.validateBundle(app))
        let destination = LauncherInstallation(root: temp.appendingPathComponent("destination"))
        XCTAssertThrowsError(try destination.commitBundle(from: app))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.app.path))
    }
    func testAtomicInstallPreservesExistingAppAndCleansStaging() throws {
        let temp = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let source = try fixture(in: temp)
        let destination = LauncherInstallation(root: temp.appendingPathComponent("destination with spaces"))
        try destination.commitBundle(from: source)
        XCTAssertTrue(destination.isInstalled)
        let marker = destination.app.appendingPathComponent("user-marker")
        try Data("keep me".utf8).write(to: marker)
        XCTAssertThrowsError(try destination.commitBundle(from: source))
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "keep me")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.root.path), [Release.appName])
    }
    func testNonExecutableBundleIsRejected() throws {
        let temp = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let app = try fixture(in: temp)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: app.appendingPathComponent("Contents/MacOS/\(Release.executable)").path)
        XCTAssertThrowsError(try LauncherInstallation.validateBundle(app))
    }
    func testLiveVerifiedInstallationWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["MACBEDROCK_LIVE_INSTALL_TEST"] == "1" else {
            throw XCTSkip("Set MACBEDROCK_LIVE_INSTALL_TEST=1 to download and verify the real release in a temporary folder.")
        }
        let temp = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let installation = LauncherInstallation(root: temp.appendingPathComponent("Runtime"))
        try await installation.install { print($0) }
        XCTAssertTrue(installation.isInstalled)
        // Retrying an existing valid installation must be idempotent.
        try await installation.install { _ in XCTFail("Already installed; must not download again") }
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacBedrockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func fixture(in root: URL) throws -> URL {
        let app = root.appendingPathComponent(Release.appName)
        let executable = app.appendingPathComponent("Contents/MacOS/\(Release.executable)")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let info = ["CFBundleIdentifier": Release.bundleID, "CFBundleExecutable": Release.executable]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }
}

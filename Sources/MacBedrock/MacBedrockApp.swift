import SwiftUI
import AppKit
import MacBedrockCore

@MainActor
final class LauncherModel: ObservableObject {
    @Published var installed = false
    @Published var busy = false
    @Published var status = "A few steps from your next world."
    @Published var error: String?
    let installation = LauncherInstallation()
    let hardware = MacHardware.current

    init() { refresh() }
    func refresh() {
        let wasInstalled = installed || UserDefaults.standard.bool(forKey: "hasInstalledLauncher")
        installed = installation.isInstalled
        if installed { UserDefaults.standard.set(true, forKey: "hasInstalledLauncher") }
        else if wasInstalled {
            status = "The launcher is no longer in its install folder."
            error = "macOS may have moved the launcher to Trash. Reinstall only if you intend to review its first-open warning in Privacy & Security. If macOS identifies malware, do not override it. A local source-build recovery is documented in the README."
            UserDefaults.standard.set(false, forKey: "hasInstalledLauncher")
        }
    }
    func install() {
        guard !busy else { return }
        busy = true
        error = nil
        let destination = installation
        Task {
            do {
                try await Task.detached {
                    try await destination.install { message in
                        await MainActor.run { self.status = message }
                    }
                }.value
                refresh()
            } catch { self.error = error.localizedDescription; status = "Setup needs attention. You can try again." }
            busy = false
        }
    }
    func launch() {
        refresh()
        guard installed, !busy else { return }
        error = nil
        busy = true
        NSWorkspace.shared.openApplication(at: installation.app, configuration: .init()) { _, launchError in
            Task { @MainActor in
                self.busy = false
                if let launchError {
                    self.error = "macOS could not open the launcher. If it was blocked, use System Settings → Privacy & Security → Open Anyway, then try again. \(launchError.localizedDescription)"
                } else {
                    self.status = "Launch requested. Complete any macOS prompt, then sign in inside the launcher."
                }
            }
        }
    }
    func launcherTerminated() {
        refresh()
        status = "The Bedrock launcher closed."
        error = "If it never opened, macOS may have blocked it. Check Privacy & Security or use the local source-build recovery in the README."
        busy = false
    }
    func reveal() {
        let folder = installation.root
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch { self.error = error.localizedDescription }
    }
}

@main
struct MacBedrockApp: App {
    @StateObject private var model = LauncherModel()
    var body: some Scene {
        WindowGroup("MacBedrock") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 680)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { event in
                    if let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == Release.bundleID { model.launcherTerminated() }
                }
        }
        .defaultSize(width: 1020, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Launcher documentation") { NSWorkspace.shared.open(Release.project) }
            }
        }
    }
}

private let lime = Color(red: 0.73, green: 0.91, blue: 0.40)
private let muted = Color(red: 0.60, green: 0.66, blue: 0.62)
private let panel = Color(red: 0.085, green: 0.115, blue: 0.105)

struct ContentView: View {
    @ObservedObject var model: LauncherModel
    @State private var tab = "Play"
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 10) {
                    Image(systemName: "cube.fill").font(.system(size: 25)).foregroundStyle(lime)
                    Text("MacBedrock").font(.system(size: 17, weight: .bold))
                }.padding(.top, 35)
                Text("YOUR NEXT ADVENTURE").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(muted)
                VStack(spacing: 8) {
                    nav("Play", icon: "play.square")
                    nav("Setup guide", icon: "list.bullet.rectangle")
                    nav("Help & about", icon: "questionmark.circle")
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.hardware.appleSilicon ? "Apple Silicon" : "Intel Mac", systemImage: "desktopcomputer").font(.system(size: 12, weight: .medium))
                    Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)").font(.system(size: 10)).foregroundStyle(muted)
                    Text("UNOFFICIAL • INDEPENDENT").font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(muted)
                }
            }.padding(24).frame(width: 204).background(Color(red: 0.055, green: 0.075, blue: 0.067))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text(tab.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(muted)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(model.installed ? lime : Color.orange).frame(width: 6, height: 6)
                            Text(model.installed ? "Launcher installed" : "Setup required").font(.system(size: 11))
                        }.padding(.horizontal, 12).padding(.vertical, 7).background(panel, in: Capsule())
                    }
                    if tab == "Play" { play }
                    else if tab == "Setup guide" { guide }
                    else { help }
                }.padding(32)
            }.background(Color(red: 0.035, green: 0.055, blue: 0.047))
        }.tint(lime)
    }
    func nav(_ title: String, icon: String) -> some View {
        Button { tab = title } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(tab == title ? lime.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(tab == title ? lime : muted)
        }.buttonStyle(.plain)
    }
    var play: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .bottomLeading) {
                Landscape().frame(height: 245).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    Text("MINECRAFT: BEDROCK EDITION").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(lime)
                    Text("Your Mac.\nYour next world.").font(.system(size: 38, weight: .bold, design: .rounded)).lineSpacing(-3)
                    Text("A native starting point for Bedrock on Apple Silicon.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                }.padding(26)
            }.clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.installed ? "Ready for the next step" : "Let’s get you set up").font(.system(size: 21, weight: .semibold))
                        Text(model.installed ? "Open the launcher to sign in and choose a game version." : "Install the community launcher, then sign in to get your game.")
                            .font(.system(size: 12)).foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: model.installed ? "checkmark.seal" : "arrow.down.app").font(.system(size: 26)).foregroundStyle(lime)
                }
                if !model.hardware.supported {
                    Text("This route requires Apple Silicon and macOS 14+. Open Help for alternatives.").foregroundStyle(.orange)
                }
                if let error = model.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                }
                HStack(spacing: 14) {
                    Button {
                        if model.installed { model.launch() } else { model.install() }
                    } label: {
                        Label(model.busy ? "Working…" : model.installed ? "Open Bedrock launcher" : "Install Bedrock launcher", systemImage: model.installed ? "play.fill" : "arrow.down")
                            .font(.system(size: 13, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 9)
                    }.buttonStyle(.plain).foregroundStyle(.black)
                        .background(lime, in: RoundedRectangle(cornerRadius: 8))
                        .opacity(model.busy || !model.hardware.supported ? 0.5 : 1)
                        .disabled(model.busy || !model.hardware.supported)
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Button("Setup guide") { tab = "Setup guide" }.buttonStyle(.plain).foregroundStyle(muted) }
                }
                Text(model.status).font(.system(size: 11)).foregroundStyle(muted).accessibilityLabel("Status: \(model.status)")
            }.padding(22).background(panel, in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .top, spacing: 18) {
                info("01", "Bring your game", "Requires Minecraft purchased on Google Play.")
                info("02", "Keep your account", "Sign in inside the community launcher.")
                info("03", "Find your world", "Download a compatible version and press Play.")
            }
            Text("Uses hugonote’s Minecraft Bedrock Launcher and the mcpelauncher runtime. Game files are downloaded separately. Version and multiplayer compatibility vary.")
                .font(.system(size: 10)).foregroundStyle(muted)
        }
    }
    func info(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(lime)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var guide: some View {
        VStack(alignment: .leading, spacing: 25) {
            Text("From setup to spawn.").font(.system(size: 32, weight: .bold, design: .rounded))
            step("1", "Own the Android edition", "The Google Play account you use must own Minecraft. A Windows, Xbox, Java, or iPhone purchase does not unlock the Google Play download.")
            Link("View Minecraft on Google Play ↗", destination: URL(string: "https://play.google.com/store/apps/details?id=com.mojang.minecraftpe")!)
            step("2", "Install and open the launcher", "Use Install on the Play screen. MacBedrock checks the download and installs it in your user folder. If macOS blocks the app, open Privacy & Security and use Open Anyway for Minecraft Bedrock Launcher.")
            step("3", "Sign in and download", "In Minecraft Bedrock Launcher, sign in with the Google account that owns Minecraft. Let it install its runtime, choose an available compatible version, and download the game.")
            step("4", "Press Play", "Start Minecraft from that launcher. Sign in to your Microsoft account in the game for supported online features. Friends and servers need compatible game versions; current Realms support is not guaranteed.")
            Button("Back to Play") { tab = "Play" }.buttonStyle(.borderedProminent)
        }
    }
    func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(lime).frame(width: 32, height: 32).background(lime.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    var help: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("A little help along the way.").font(.system(size: 30, weight: .bold, design: .rounded))
            step("?", "An unofficial route", "MacBedrock installs a community launcher, not a new port of Minecraft. Rendering, game updates, and multiplayer depend on mcpelauncher. No game files or credentials are bundled with MacBedrock.")
            step("!", "Blocked by macOS?", "The upstream launcher is not notarized. Review it in System Settings → Privacy & Security → Open Anyway. MacBedrock leaves Gatekeeper enabled.")
            step("↻", "Setup interrupted?", "If macOS moved the launcher to Trash, review the first-open warning or use the README’s local source-build recovery. Retry Install. Downloads are verified before installation. If an incomplete launcher already exists, reveal its folder and move that app aside, then retry. This does not remove your worlds. Upstream launcher updates are managed in that launcher.")
            step("i", "Using an Intel Mac?", "This app’s install route supports Apple Silicon only. Consult the legacy mcpelauncher documentation for Intel builds and their version limits, or play through a Windows computer you can stream to your Mac.")
            HStack {
                Button("Reveal launcher folder", action: model.reveal)
                Link("Upstream launcher ↗", destination: Release.project)
            }
            Link("Runtime compatibility & known issues ↗", destination: URL(string: "https://github.com/minecraft-linux/mcpelauncher-manifest")!)
            Text("MacBedrock 0.1.0 • Initial launcher: \(Release.version)\nIndependent project. Not affiliated with Mojang, Microsoft, Google, or upstream maintainers.")
                .font(.system(size: 11)).foregroundStyle(muted)
        }
    }
}

/// Original vector landscape, drawn locally; no Minecraft assets are redistributed.
struct Landscape: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.15, green: 0.31, blue: 0.28), Color(red: 0.44, green: 0.57, blue: 0.35)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            let unit = size.width / 22
            context.fill(Path(CGRect(x: size.width * 0.76, y: 35, width: 42, height: 42)), with: .color(Color(red: 0.85, green: 0.91, blue: 0.65)))
            for layer in 0..<3 {
                for column in 0..<23 {
                    let height = CGFloat((column * 7 + layer * 11) % 5 + 2) * 15
                    let y = 120 + CGFloat(layer * 43) - height
                    context.fill(Path(CGRect(x: CGFloat(column) * unit, y: y, width: unit + 1, height: size.height - y)), with: .color([Color(red: 0.27, green: 0.43, blue: 0.33), Color(red: 0.16, green: 0.32, blue: 0.25), Color(red: 0.09, green: 0.22, blue: 0.17)][layer]))
                }
            }
            for x in [0.65, 0.85, 0.94] {
                let origin = size.width * x
                context.fill(Path(CGRect(x: origin, y: 105, width: 13, height: 92)), with: .color(Color(red: 0.15, green: 0.23, blue: 0.16)))
                context.fill(Path(CGRect(x: origin - 22, y: 80, width: 57, height: 50)), with: .color(Color(red: 0.20, green: 0.37, blue: 0.20)))
                context.fill(Path(CGRect(x: origin - 12, y: 64, width: 38, height: 34)), with: .color(Color(red: 0.29, green: 0.46, blue: 0.25)))
            }
        }.accessibilityHidden(true)
    }
}

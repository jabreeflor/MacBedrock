import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacBedrockCore

@MainActor
final class EnvironmentModel: ObservableObject {
    let environment = WindowsEnvironment()
    @Published var prepared = false
    @Published var busy = false
    @Published var status = "Prepare Windows for your Microsoft Store copy."
    @Published var error: String?
    @Published var selectedISO: URL?
    init() { refresh() }
    func refresh() {
        prepared = environment.isPrepared
        if selectedISO == nil, FileManager.default.fileExists(atPath: environment.windowsISO.path) { selectedISO = environment.windowsISO }
    }
    func chooseISO() {
        let panel = NSOpenPanel()
        panel.title = "Choose Windows 11 25H2 English ARM64 v2 ISO"
        panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .data]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { selectedISO = panel.url }
    }
    func prepare() {
        guard let iso = selectedISO, !busy else { return }
        busy = true; error = nil
        let destination = environment
        Task {
            do {
                try await Task.detached {
                    try await destination.prepare(iso: iso) { message in
                        await MainActor.run { self.status = message }
                    }
                }.value
                refresh()
            } catch { self.error = error.localizedDescription; status = "Setup needs attention." }
            busy = false
        }
    }
    func openWindows() {
        guard prepared, !busy else { return }
        error = nil; busy = true
        let destination = environment
        Task {
            do {
                try await Task.detached {
                    try LauncherInstallation.validateBundle(destination.engine.app)
                    try LauncherInstallation.verifySignature(destination.engine.app)
                }.value
                let configuration = NSWorkspace.OpenConfiguration()
                // UTM 5.0.5 supports these launch defaults. Existing UTM processes
                // keep their current renderer; the guide explains how to check it.
                configuration.arguments = ["-QEMUDirectXDriver", "2", "-QEMURendererBackend", "2"]
                NSWorkspace.shared.open([destination.bundle], withApplicationAt: destination.engine.app, configuration: configuration) { _, failure in
                    Task { @MainActor in
                        self.busy = false
                        if let failure { self.error = failure.localizedDescription }
                        else { self.status = "Environment opened. Press Run in the Windows window. Game readiness is not yet verified." }
                    }
                }
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }
    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([prepared ? environment.bundle : environment.root])
    }
}

@main
struct MacBedrockApp: App {
    @StateObject private var model = EnvironmentModel()
    var body: some Scene {
        WindowGroup("MacBedrock") {
            ContentView(model: model).frame(minWidth: 960, minHeight: 740).preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        }.defaultSize(width: 1060, height: 800).windowStyle(.hiddenTitleBar)
    }
}

private let lime = Color(red: 0.73, green: 0.91, blue: 0.40)
private let muted = Color(red: 0.60, green: 0.66, blue: 0.62)
private let panel = Color(red: 0.085, green: 0.115, blue: 0.105)

struct ContentView: View {
    @ObservedObject var model: EnvironmentModel
    @State private var tab = "Environment"
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 30) {
                Label("MacBedrock", systemImage: "cube.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(lime).padding(.top, 30)
                Text("YOUR WINDOWS WORLD").font(.system(size: 9, design: .monospaced)).tracking(1.5).foregroundStyle(muted)
                ForEach(["Environment", "Setup guide", "Help & about"], id: \.self) { name in
                    Button(name) { tab = name }.buttonStyle(.plain).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tab == name ? lime : muted)
                }
                Spacer()
                Label("Apple Silicon", systemImage: "desktopcomputer").font(.system(size: 12))
                Text("CUSTOM WINDOWS ENVIRONMENT\nUTM / QEMU • EXPERIMENTAL").font(.system(size: 8, design: .monospaced)).foregroundStyle(muted).lineSpacing(5)
            }.padding(25).frame(width: 210).background(Color(red: 0.055, green: 0.075, blue: 0.067))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text(tab.uppercased()).font(.system(size: 10, design: .monospaced)).tracking(2)
                        Spacer()
                        Label(model.prepared ? "VM prepared • gameplay unverified" : "Setup required", systemImage: "circle.fill").font(.system(size: 10)).foregroundStyle(lime)
                    }.foregroundStyle(muted)
                    if tab == "Environment" { environment }
                    else if tab == "Setup guide" { guide }
                    else { help }
                }.padding(32)
            }.background(Color(red: 0.035, green: 0.055, blue: 0.047))
        }.tint(lime)
    }
    var environment: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .bottomLeading) {
                Landscape().frame(height: 230).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 9) {
                    Text("MINECRAFT FOR WINDOWS").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(lime)
                    Text("Your purchase.\nA new place to play.").font(.system(size: 35, weight: .bold, design: .rounded))
                    Text("A dedicated Windows environment for your Mac.").font(.system(size: 12))
                }.padding(24)
            }.clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 16) {
                Text(model.prepared ? "Your environment is prepared" : "Build your Windows environment").font(.system(size: 22, weight: .semibold))
                Text(model.prepared ? "Open Windows, finish setup, then install your Microsoft Store copy of Minecraft." : "Download Windows from Microsoft, choose the ISO, and let MacBedrock create your VM.").font(.system(size: 13)).foregroundStyle(muted)
                if !model.prepared {
                    Link("Download Windows ARM64 from Microsoft ↗", destination: URL(string: "https://www.microsoft.com/en-us/software-download/windows11arm64")!)
                    Text("Required image: Windows 11 25H2 · English (United States) · ARM64 v2").font(.system(size: 11)).foregroundStyle(muted)
                    HStack { Button("Choose Windows ISO", action: model.chooseISO); Text(model.selectedISO?.lastPathComponent ?? "No ISO selected").font(.system(size: 11)).foregroundStyle(muted) }
                }
                if let error = model.error { Text(error).foregroundStyle(.orange).font(.system(size: 12)).textSelection(.enabled) }
                HStack {
                    Button {
                        if model.prepared { model.openWindows() } else { model.prepare() }
                    } label: {
                        Label(model.busy ? "Working…" : model.prepared ? "Open Windows environment" : "Create environment", systemImage: model.prepared ? "play.fill" : "plus.rectangle.on.rectangle").padding(8)
                    }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                        .disabled(model.busy || (!model.prepared && model.selectedISO == nil) || !MacHardware.current.supported)
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Button("Setup guide") { tab = "Setup guide" }.buttonStyle(.plain).foregroundStyle(muted) }
                }
                Text(model.status).font(.system(size: 11)).foregroundStyle(muted).accessibilityLabel("Status: \(model.status)")
            }.padding(22).background(panel, in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .top, spacing: 20) {
                info("4 CORES / 8 GB", "Windows ARM64", "Hardware virtualization on Apple Silicon.")
                info("80 GB CAPACITY", "A growing disk", "Uses space as needed. Keep free space available.")
                info("DIRECTX 11", "Experimental graphics", "Triton + DXMT. Minecraft gameplay is unverified.")
            }
            Text("Your Microsoft Store purchase is used inside Windows. A Windows license is separate. No game or account credentials are bundled.").font(.system(size: 11)).foregroundStyle(muted)
        }
    }
    func info(_ tag: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tag).font(.system(size: 9, design: .monospaced)).foregroundStyle(lime)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(lime).frame(width: 30)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    var guide: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("From Windows to your world.").font(.system(size: 30, weight: .bold, design: .rounded))
            step("1", "Start the environment", "Open your environment and press Run in UTM. Click the VM and press a key when asked to boot from CD. If an EFI shell appears, type exit, choose Boot Manager, then the first USB drive. Press a key at the CD prompt.")
            step("2", "Install Windows", "Choose your region and licensed Windows edition. Review Microsoft’s license terms yourself. Install only to the empty 80 GB virtual disk. Your Mac’s real disk is not attached. After the first restart, let Windows boot without pressing a key. If network setup needs a driver, choose Install driver and browse MacBedrock-Drivers → Drivers → NetKVM → w10 → ARM64.")
            step("3", "Install the graphics driver", "The MacBedrock-Drivers CD is mounted. Run its guest tools installer and select the experimental 3D graphics driver when prompted, then restart Windows. In UTM Settings → QEMU, use ANGLE Metal and DXMT for DirectX. Do not select D3DMetal unless separately configured.")
            step("4", "Use your Microsoft Store purchase", "Inside Windows, open Microsoft Store and sign in to the account that owns Minecraft for Windows. Install it from your library and launch it. The app never asks for your password.")
            step("5", "Check actual gameplay", "In Windows, run dxdiag and confirm a Triton/Neptune adapter and Direct3D feature level 11_0. Start Minecraft at 1280 × 720 with modest render distance. Create a world, check audio and input, then test joining friends. Booting Windows alone does not establish game compatibility.")
        }
    }
    var help: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Your environment, explained.").font(.system(size: 30, weight: .bold, design: .rounded))
            step("i", "Built on open-source components", "MacBedrock creates and opens a dedicated UTM/QEMU Windows VM. Triton and DXMT provide an experimental DirectX 11 path. This is not a native port of Minecraft or a new hypervisor. DirectX 12 features and game compatibility are not promised.")
            step("!", "If macOS blocks an app", "The downloaded UTM engine must pass checksum, signature, and Gatekeeper assessment. MacBedrock does not remove quarantine or disable Gatekeeper. This MacBedrock app is locally built; public downloads require developer signing and notarization for a smooth first launch.")
            step("↻", "Keep your worlds safe", "Shut Windows down before backing up the entire .utm bundle. Retrying setup never overwrites an existing environment. The disk can grow to 80 GB, so monitor free storage. If setup reports an incomplete bundle, reveal it and move it aside manually before retrying.")
            HStack { Button("Reveal environment", action: model.reveal); Link("Engine release notes ↗", destination: Release.project) }
            Link("Windows guest tools guide ↗", destination: URL(string: "https://docs.getutm.app/guest-support/windows/")!)
            Text("MacBedrock 0.2.0 • UTM 5.0.5 beta\nIndependent project. Not affiliated with Mojang, Microsoft, Apple, or UTM.").font(.system(size: 11)).foregroundStyle(muted)
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

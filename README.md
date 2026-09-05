# MacBedrock

A native macOS setup companion that installs and opens a real community Minecraft Bedrock launcher. Built for **Apple Silicon and macOS 14+**. This is not a Minecraft clone or a new compatibility engine.

## Play on your Mac

1. Build with `scripts/build-app.sh` (requires Xcode Command Line Tools with Swift 6+) or download the `MacBedrock-macOS-arm64` artifact from a successful [GitHub Actions build](https://github.com/jabreeflor/MacBedrock/actions/workflows/build.yml). Extract the ZIP to get `MacBedrock.app`.
2. Drag `MacBedrock.app` to your Applications folder and open it.
3. Click **Install Bedrock launcher**, then **Open Bedrock launcher**.
4. In the community launcher, sign in with a **Google Play account that owns Minecraft**. Download a compatible game version and press **Play**. Microsoft sign-in for online features happens inside Minecraft.

A Windows, Xbox, Java, or iPhone purchase does **not** unlock the Google Play download. MacBedrock does not include or sell Minecraft, handle your credentials, or bypass ownership checks. See the [upstream ownership requirements](https://mcpelauncher.readthedocs.io/en/latest/faq/index.html).

The app and the upstream launcher are not notarized. If macOS blocks first launch, review the app under **System Settings → Privacy & Security → Open Anyway**. MacBedrock preserves quarantine on the downloaded launcher and never disables Gatekeeper.

## If macOS moves the launcher to Trash

The upstream release is ad-hoc signed, not notarized. macOS can reject it and offer to move it to Trash. MacBedrock detects a removed installation and reports the problem rather than treating a LaunchServices callback as proof the app opened.

For an unverified-developer warning, you can review the app using the normal **Privacy & Security → Open Anyway** flow. If the warning identifies malware, do not override it.

On a Mac with **full Xcode 26+**, another option is to compile the published launcher source locally:

```sh
scripts/build-launcher-from-source.sh
```

This checks the upstream tag against commit `8830219a8b390e6ca7cec93b3574e1d0e4331c15`, builds the launcher and helpers, checks their local code signatures, and installs the result. It refuses to replace an existing app, does not empty Trash, and does not change Gatekeeper or remove quarantine from downloaded apps. Swift Package Manager resolves upstream dependencies; this source path is not a byte-for-byte reproduction of the published DMG. Local source builds have upstream app auto-updates disabled; repeat the source-build process for future launcher updates. Runtime and game downloads remain managed by the launcher.

## What it does

- Detects Apple Silicon, including when running under Rosetta, and checks macOS compatibility.
- Downloads the pinned [hugonote/mcpelauncher-swift 0.1.13 release](https://github.com/hugonote/mcpelauncher-swift/releases/tag/v0.1.13) over HTTPS and verifies its SHA-256 digest before mounting it read-only.
- Validates the expected app identifier and executable, stages the copy beside its destination, and moves it into place. Existing installs are left untouched; errors can be retried.
- Opens the installed launcher through macOS. That launcher handles Google Play authentication, downloads, runtime installation, compatibility patches, and its own updates.
- Includes an accessible setup guide, installation status, and actionable failure messages.

Initial release digest: `e56a08291837a998879a5bcdbae9fe90e0b60c17359a4c7e2d1af5b72e584c61` (verified against GitHub's release metadata on 2026-09-04). This is an integrity check against a pinned upstream release, not a notarization or security audit. To change the initial release, update the URL, version and digest together in `Sources/MacBedrockCore/Launcher.swift`, then run the live install test. Existing installations update through the upstream launcher's updater.

## Compatibility limits

The runtime is [minecraft-linux/mcpelauncher](https://github.com/minecraft-linux/mcpelauncher-manifest). This community route runs the Android edition; compatibility depends on the game version and runtime patches. **Latest Bedrock, Realms, servers, and Xbox invitations are not guaranteed.** Friends and servers need compatible versions. MacBedrock does not claim a successful game session until you sign in, download an owned compatible version, and launch it.

The selected upstream launcher requires Apple Silicon and macOS 14+. Intel users can investigate the legacy runtime's documented Intel builds or stream from a Windows computer. MacBedrock intentionally disables this installation route on unsupported Macs.

## Files and removal

- MacBedrock's managed launcher: `~/Library/Application Support/MacBedrock/Runtime/Minecraft Bedrock Launcher.app`
- Upstream game data: `~/Library/Application Support/Minecraft Bedrock Launcher/`
- Worlds, under the upstream data folder: `MinecraftData/games/com.mojang/minecraftWorlds/`

Use **Help & about → Reveal launcher folder** to inspect an installation. For an incomplete install, move the managed launcher app aside and retry. Removing `MacBedrock.app` and its `MacBedrock` support folder removes the companion and managed launcher; it does not remove upstream game data. Back up your worlds before manually changing any game-data folders. Existing Java installations are not touched.

## Development and verification

```sh
swift test
scripts/build-app.sh
open dist/MacBedrock.app
```

To exercise the actual HTTPS download, checksum, DMG mount, bundle installation, and idempotent retry in an isolated temporary folder:

```sh
MACBEDROCK_LIVE_INSTALL_TEST=1 swift test
```

Tests cover checksum tampering, incompatible hardware, malformed/missing/non-executable bundles, installation in paths containing spaces, existing-app preservation, and staging cleanup. The network test is opt-in; standard CI does not download or execute third-party software. CI builds an ad-hoc-signed arm64 `.app` ZIP. No external Swift packages are required.

Manual verification: open each sidebar page; install; confirm the button changes to Open; open the upstream launcher; check Google Play sign-in is offered. Paid-account authentication and actual gameplay require the user's account and are not automated.

## Credits

- [Minecraft Bedrock Launcher](https://github.com/hugonote/mcpelauncher-swift), hugonote — MIT. Downloaded separately, with upstream notices retained.
- [mcpelauncher](https://github.com/minecraft-linux/mcpelauncher-manifest), minecraft-linux contributors — GPL-3.0, installed separately by the upstream launcher.
- Minecraft is a trademark of Mojang/Microsoft. MacBedrock is independent and is not affiliated with Mojang, Microsoft, Google, or the upstream projects.

MacBedrock's code is MIT licensed. The interface uses original procedural vector artwork, not Minecraft game assets.

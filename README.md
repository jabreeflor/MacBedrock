# MacBedrock

A native Mac app that prepares a dedicated **Windows ARM64 environment for a Microsoft Store copy of Minecraft for Windows (Bedrock)**. Uses the open-source UTM/QEMU engine, Apple hardware virtualization, and experimental Triton → Neptune → DXMT graphics. No Parallels subscription or Google Play purchase is involved.

**Status:** environment creation and normal Windows installer boot are verified on this Apple Silicon Mac. Setup is waiting at the Windows product-key screen. Minecraft gameplay, Microsoft Store installation, and multiplayer are **not yet verified**. This is an experimental Windows VM setup companion, not a native Minecraft port or a new hypervisor.

## Requirements

- Apple Silicon Mac, macOS 14+, at least 16 GB RAM.
- At least 32 GB free **after** downloading the Windows installer. More is recommended: the virtual disk can grow to 80 GB and must share storage with macOS.
- A Windows license, separate from your Minecraft purchase.
- Minecraft for Windows ownership on your Microsoft account. Sign in only inside Windows/Microsoft Store.
- Windows 11 **25H2 English (United States) ARM64 v2** ISO from [Microsoft](https://www.microsoft.com/en-us/software-download/windows11arm64). This release pins its hash; another language/version is rejected.

## Build and open

```sh
swift test
bash scripts/build-app.sh
open dist/MacBedrock.app
```

The script produces an ARM64 `.app` and ZIP in `dist/`. It ad-hoc signs the locally built MacBedrock app. Public distribution still needs an Apple Developer ID signature and notarization. Do not disable Gatekeeper. The separate downloaded UTM engine must pass its pinned SHA-256, signature verification, and Gatekeeper assessment before installation.

## Setup

1. Download the specified Windows ISO from Microsoft. Open MacBedrock, choose it, then click **Create environment**. The app streams the checksum, installs UTM 5.0.5, fetches pinned driver media, and creates the VM atomically.
2. Click **Open Windows environment**, then **Run** in UTM. At the CD boot prompt, click the VM and press a key promptly. If you land in the EFI shell, type `exit`, choose **Boot Manager**, then the **first USB drive**. Press a key when prompted.
3. Complete Windows Setup. Choose the Windows edition you are licensed to use and review its license terms. The installation target is the empty **80 GB virtual disk**. No physical host disk is passed through. After the first restart, let it boot without pressing a key at the CD prompt.
4. If Windows needs a network driver, use **Install driver** and browse the mounted **MacBedrock-Drivers** CD to `Drivers\NetKVM\w10\ARM64`. Complete the normal Windows account setup.
5. In Windows, run `utm-guest-tools.exe` on the **MacBedrock-Drivers** CD. Choose the **experimental 3D graphics driver** when prompted, then restart. No automatic answer file is included on this CD. The original driver files and license are preserved.
6. MacBedrock requests **ANGLE Metal** and **DXMT** when starting UTM. If UTM was already running, its existing settings take precedence. Check **UTM Settings → QEMU** and select those backends, then restart the VM. D3DMetal is not included or required by this project.
7. Open Microsoft Store **inside Windows**. Sign into the account that owns Minecraft for Windows, install from your library, and launch it.
8. Verify `dxdiag` lists the Triton/Neptune display driver and Direct3D feature level `11_0`. Start Minecraft at 1280×720 with a modest render distance. Create a world, test mouse/keyboard, audio, save/reopen, and finally multiplayer. This validation remains outstanding; Windows boot alone is not evidence that Bedrock works.

## What MacBedrock creates

All state stays under `~/Library/Application Support/MacBedrock/`:

| Path | Purpose |
| --- | --- |
| `Engine/UTM.app` | Original signed/notarized upstream engine, installed per user |
| `Media/` | Downloaded installer/driver media |
| `Environments/MacBedrock Windows.utm/config.plist` | ARM64 / 4 cores / 8192 MiB RAM / HVF / GPU / devices |
| `Environments/MacBedrock Windows.utm/Data/windows.raw` | Sparse 80 GiB persistent Windows disk |
| `Environments/MacBedrock Windows.utm/Data/efi_vars.fd` | Private UEFI variables with preloaded Secure Boot keys |
| `Environments/MacBedrock Windows.utm/Data/tpmdata` | Private TPM state, created by UTM |
| `Environments/MacBedrock Windows.utm/Data/drivers.iso` | Manual driver media, without upstream unattended setup |
| `Environments/MacBedrock Windows.utm/Data/debug.log` | Local QEMU launch diagnostics |

Installer files are cloned on APFS to avoid duplicate physical storage; other filesystems use a normal copy. Networking uses outbound NAT with no forwarded ports. Folder, clipboard, and USB sharing start disabled. The VM has its own disk; no game binaries or credentials are stored in the repository.

Setup never replaces an existing environment. If a partial bundle blocks a retry, reveal it and move it aside yourself. Shut Windows down before backing up the entire `.utm` bundle. Do not delete `windows.raw` or TPM/UEFI state to fix an unrelated launcher problem.

## Verified dependencies

| Download | Pinned SHA-256 |
| --- | --- |
| [UTM 5.0.5 beta](https://github.com/utmapp/UTM/releases/tag/v5.0.5) `UTM.dmg` | `713afe73c711f01344b8766654be531cd391ed2e30931206f43b5159f143764f` |
| Microsoft Windows 11 25H2 English ARM64 v2 | `638aa2c88e94385b00f4f178d071e3df0b7d9e335577a83bd533b7f2eb65adf0` |
| [UTM guest tools 0.1.273](https://github.com/utmapp/qemu/releases/tag/v10.0.12-utm) | `7d2c0343e92358ad5e65078b08ec1dad873eb91b3c154aef60531bf6c2f04601` |

The driver ISO is rebuilt locally using an allowlist of original driver files. The upstream `Autounattend.xml` caused Windows Setup error `0x80070006 - 0x40031` in the initial trial and also changes Windows account/security settings. It is deliberately excluded; installation follows normal Windows setup.

UTM 5's DirectX driver is experimental and game compatibility is limited. See the [release notes](https://github.com/utmapp/UTM/releases/tag/v5.0.5), [Triton technical announcement](https://blog.getutm.app/2026/introducing-triton-directx-11-driver-for-qemu/), and [Windows guest tools documentation](https://docs.getutm.app/guest-support/windows/). DXMT currently provides the DirectX 11 path used here; DirectX 12 features are not promised.

## Validation

`swift test` covers checksum failures, malformed engines, atomic engine/VM installation, preservation of an existing disk, sparse allocation, VM device configuration, and exclusion of unattended Windows settings from driver media. `MACBEDROCK_LIVE_INSTALL_TEST=1 swift test --filter testLiveVerifiedInstallationWhenRequested` additionally downloads and checks the actual engine in a temporary folder.

CI builds the app on macOS and uploads the ZIP. Windows and Minecraft tests require a Mac capable of virtualization and a user's own licenses/accounts.

MacBedrock source is MIT licensed. UTM/QEMU and drivers retain their upstream licenses; they are fetched separately. Independent project, not affiliated with Mojang, Microsoft, Apple, or UTM.

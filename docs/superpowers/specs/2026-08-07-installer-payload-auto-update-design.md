# AccessXI Installer Payload Auto-Update Design

## Goal

When a user clicks Install in any AccessXI installer containing this bootstrap, the installer checks the public `buu420/AccessXI` GitHub repository for the latest published `AccessXI-Ashita-Installer.zip`. If that release payload differs from the embedded payload, the installer downloads, verifies, and installs the newer package automatically. If the network or update service is unavailable, the installer clearly reports the fallback and installs its complete embedded payload.

This updates AccessXI content: the addon, navigation data, Ashita files, native PlayOnline accessibility files, prerequisites, and setup guide. It does not replace the running installer executable.

## Trust and Safety Boundary

- Only `GET https://api.github.com/repos/buu420/AccessXI/releases/latest` is accepted as update metadata.
- Only the exact uploaded asset name `AccessXI-Ashita-Installer.zip` is eligible.
- The initial download URL must be HTTPS and point to `github.com` under the exact AccessXI release-download path.
- GitHub's release asset `digest` must be present as a SHA-256 value. The completed download's byte count and SHA-256 must both match the metadata before use.
- The ZIP is validated before extraction: no absolute or parent-traversal names, reasonable entry and expanded-size bounds, and all required AccessXI package files must exist.
- Downloads use a unique temporary directory and a `.partial` filename. A partial, mismatched, malformed, or unsafe package is never installed.
- Any check or download failure produces an explicit warning in the installer log and falls back to the complete embedded package. Installation remains usable offline.

The HTTPS connection and the GitHub repository/release permissions are the publisher trust root. The asset digest protects against corruption, truncation, and a mismatched download; it is not an independent signature against compromise of the publisher's GitHub account. A separately signed release manifest can be added later if AccessXI adopts offline signing-key management.

## Current-versus-Latest Decision

The installer computes SHA-256 over its embedded ZIP stream and compares it with the latest release asset digest.

- Same digest: use the embedded package without downloading 590+ MB again.
- Different digest: download and verify the latest package.
- Metadata unavailable or invalid: use the embedded package and disclose why.

This compares the actual payload rather than guessed semantic versions or timestamps.

## User Experience

The existing Install button remains the only action required.

1. Validate the selected installation and PlayOnline locations and handle the existing prerequisite choice.
2. Enter the Installing state and announce `Checking GitHub for AccessXI updates.`
3. Report one of:
   - `The embedded AccessXI package is already current.`
   - `Downloading AccessXI update <tag>.`
   - `Verified AccessXI update <tag>.`
   - `Update check failed; using the embedded AccessXI package. <reason>`
4. Extract only the selected, complete package and run the existing `install_accessxi.ps1` flow.
5. Clean update temporary files best-effort after installation.

No new prompt interrupts normal installation. Update progress is mapped into the existing determinate progress bar.

## Code Shape

- `ReleasePayloadUpdater.cs`: network metadata, embedded digest comparison, streaming download, SHA-256/size verification, ZIP safety validation, and a result describing embedded or downloaded payload use.
- `Program.cs`: async orchestration, progress/log integration, passing the selected ZIP into the existing installer runner, and cleanup.
- A dependency-free console test project uses a fake HTTP handler and real in-memory ZIPs to test current, update, offline, digest mismatch, invalid URL, and traversal cases.
- PowerShell structure guards ensure updater behavior remains wired into the public installer and dependency installers remain bundled rather than downloaded.

## Non-Goals

- Silent background updates while FFXI is running.
- Updating from branches, pull requests, prereleases, or arbitrary URLs.
- Replacing or relaunching the running installer EXE.
- Character-specific configuration or routing behavior.

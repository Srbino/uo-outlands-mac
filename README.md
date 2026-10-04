# Outlands for Mac

A native macOS installer for **UO Outlands on Apple Silicon**. Download an app, follow the setup, and let the official Outlands launcher download the game.

[![macOS build and tests](https://github.com/Srbino/uo-outlands-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/Srbino/uo-outlands-mac/actions/workflows/ci.yml)
[![Runtime smoke test](https://github.com/Srbino/uo-outlands-mac/actions/workflows/runtime-smoke.yml/badge.svg)](https://github.com/Srbino/uo-outlands-mac/actions/workflows/runtime-smoke.yml)

[Releases](https://github.com/Srbino/uo-outlands-mac/releases) · [Report a problem](https://github.com/Srbino/uo-outlands-mac/issues/new/choose)

> **Release status:** the native installer is a release candidate. **Stable release is blocked:** earlier clean-prefix launcher probes exited 255. Registering the intended game directory now prevents the immediate exit and allowed game downloads in an isolated test, but a working launcher window and gameplay remain unverified. The complete installer pipeline passed, but launcher startup and gameplay are not yet verified. Builds and automated checks are available, but a clean installation through first login and gameplay still needs the hardware acceptance checks in [TESTING.md](docs/TESTING.md). Do not interpret a green build as a guarantee that every Wine/game combination works. Outlands [does not officially support macOS](https://wiki.uooutlands.com/Install_UO_on_Mac).

![Native Outlands Installer interface](docs/installer.png)

## Independent review

The complete review brief, source map, known blockers, UI/UX acceptance matrix and local test evidence start in [docs/REVIEW.md](docs/REVIEW.md). Run `python3 tools/prepare_review.py` to create a source snapshot including untracked files, with a verified SHA-256 manifest. This is preparation for independent review, not a completed review.

## Install

1. Open [Releases](https://github.com/Srbino/uo-outlands-mac/releases) and download `Outlands-Installer-<version>-arm64.zip` from a **published, notarized release**. If no native release is published yet, use the developer build instructions below; the source ZIP is not an installable application.
2. Unzip it, drag **Outlands Installer.app** into Applications, and open it.
3. Click **Install Outlands**. If Rosetta is missing, review Apple's licence and enable the Rosetta installation option. macOS may request permission to install it.
4. Keep your Mac awake and online. Runtime setup can take 15–45 minutes and may display Microsoft installer windows. Complete them if requested.
5. When installation checks pass, click **Open Outlands**. Let the official launcher finish downloading and verifying the game before playing.

No Terminal, Homebrew, Python or Xcode is required for an end-user release. The installer is written in Swift/SwiftUI; it invokes the pinned upstream Winetricks tool for Microsoft runtimes. It does not run the old `install.sh`.

### Requirements

| Requirement | Details |
| --- | --- |
| Mac | Apple Silicon (M-series); Intel is not supported by this installer |
| macOS | **14.6 or later**, matching the current Sikarugir requirement |
| Free space | At least **20 GB**, or **30 GB** for a rebuild; larger existing installations may need more |
| Network | HTTPS access to GitHub, Microsoft and Outlands; runtime mirrors may also be used by Winetricks |
| Rosetta 2 | Verified by running an Intel executable; installed only with the user's licence consent |

## What the app handles

- Guided setup, current step, elapsed time, live logs, cancellation and retry.
- Pinned Sikarugir engine, wrapper template and macOS Winetricks fork, with SHA-256 and exact size checks. Corrupt cached files are downloaded again.
- Downloads are written to temporary files before use; HTML error pages are rejected as launchers.
- A separate staging application, a lock against concurrent installers, scoped Wine cleanup, and a Windows command smoke test.
- .NET validation checks both framework runtime files and the registry release value for **4.8**. A successful subprocess exit alone is insufficient.
- Read-only installation diagnostics and a reviewed GitHub issue draft. No account token or automatic log upload is required.
- Optional update checks against this repository's stable GitHub releases, at most once daily. Updates open the release page; the app does not silently replace itself or change the installed Wine engine.

### Existing installations and recovery

The installer detects `~/Applications/Sikarugir/outlands.app`. Use **Open Outlands** or **Check installation** without changing it.

**Rebuild with backup** copies the existing Windows prefix, game files and profiles into staging and applies the new runtime there. Close the game and launcher first. Only after validation does the installer move the original app to `outlands-backup-<id>.app` and promote the new copy. Keep that backup until you have verified your profiles and gameplay; it is not automatically deleted.

A failed or cancelled install leaves staging available for retry. If an older recipe or an unrecognised staging folder is present, the app stops and shows its location. Use **Preserve staging & start fresh** to keep that copy under a separate name before retrying; do not delete it if it may contain files you need. An interrupted final rename can leave the original under its backup name; restore it in Finder while the installer and game are closed.

### Locations

| Item | Location |
| --- | --- |
| Game and profiles | `~/Applications/Sikarugir/outlands.app` |
| In-progress installation | `~/Applications/Sikarugir/.outlands-installing.app` |
| Rebuild backups | `~/Applications/Sikarugir/outlands-backup-<id>.app` |
| Verified component and runtime caches | `~/Library/Caches/OutlandsInstaller/` |
| Installer logs | `~/Library/Logs/OutlandsInstaller/` |
| Installation lock | `~/Library/Application Support/OutlandsInstaller/` |

The app does not install global audio settings, kill unrelated Wine processes, remove other Sikarugir wrappers, or merge libraries from unrelated Wine builds.

## Troubleshooting and reporting

| Problem | Next step |
| --- | --- |
| macOS blocks the installer | Use a notarized release from this repository. CI and local builds are ad-hoc signed, not notarized. Do not disable Gatekeeper globally. See [release setup](docs/RELEASING.md). |
| Download interrupted or checksum mismatch | Retry with a stable connection. Invalid cached components are replaced; upstream asset changes require a reviewed installer update. |
| .NET setup appears stuck | Check for an open Microsoft setup window and expand **Installation log**. Use **Stop installation** if necessary, then retry. |
| Launcher ready, but no game files | Open the Outlands launcher and finish its first download. Use its **Verify** function for game-file problems. |
| Nothing happens when opening the game | Close the game/launcher, run **Check installation**, and review diagnostics. File checks alone do not prove that graphics or login work. |
| Existing game stopped working | Keep the backup. Close both apps before restoring the original wrapper in Finder. |
| Audio crackles | Connect the output device before launching. Try wired audio or 48 kHz in Audio MIDI Setup. No global audio workaround is applied automatically. |

Choose **Report a problem…**, describe what happened, and review the report. **Continue to GitHub** opens a prefilled public issue draft; you submit it yourself after signing in. Installer failures never silently post anything.

**Export diagnostics…** saves the report and the last 128 KB of the installer log. Home paths, common secret patterns and email addresses are redacted. Redaction cannot recognise every secret: review the file before attaching it. The installer does not collect game profiles, account credentials, hostnames or environment dumps. See [privacy details](docs/PRIVACY.md).

## Archive and restore everything

The **Backups** page defaults to **Settings & scripts**. Use **Create backup…**, **Add existing…** or **Restore…**.

- **Create backup…** opens a read-only preview showing file counts, profile files, scripts/macros, uncompressed size and excluded linked data. Compressed size is known only after creation. Close Outlands, Razor and the launcher first. The recommended backup saves ClassicUO settings.json, character profiles (including interface settings, hotkeys and macros), Razor profiles/scripts/macros and configuration files. Both Assistant and legacy Razor layouts are supported. Shared client settings, map icons and fonts are included; game assets, Wine, plugin binaries and journal logs are excluded.
- **Full installation** is an optional complete recovery copy of outlands.app, including game downloads and the Wine runtime. Existing full backups remain readable. Settings backups use manifest format 2; full backups use format 1.
- Each .outlandsbackup folder contains outlands.tar.gz and a dated JSON manifest with scope, sizes and SHA-256. Keep both files together. Creation finishes only after checksum and full archive-read verification; failed/cancelled temporary output is removed.
- Restore first creates a separate recovery folder. For settings backups, choose **Review & apply…**, search and select individual files, then apply them while Outlands is closed. Unselected files remain unchanged. The installer prepares a copy of the current ClassicUO directory, overlays the selected settings and swaps directories, preserving the original as ClassicUO-before-settings-… for **Undo restore…**. Game assets and Wine are outside this swap. Preparing ClassicUO needs additional disk space; retained recovery directories are never deleted automatically. Manual copy instructions remain included. Full recovered installations offer explicit activation that preserves the previous installation.
- Restore copies the payload into private staging and validates that copy before extraction. Verification reads file bodies, checks expanded sizes and rejects unsafe paths, duplicate names, special files and unsafe link chains. Restore needs space for the compressed copy, expanded files and a safety margin.
- Backups are local and **unencrypted**, and may include stored account information. They are never attached to issue reports. External symbolic-link targets are not included. Redirected settings roots and a nonstandard ClassicUO profilespath produce an explicit error; back up those locations separately. Custom launcher arguments and third-party plugins are outside the selective backup coverage. Full backups include only files inside the wrapper.
- The catalog supports custom names, notes, sorting and **Refresh locations**. Availability and the date of the last integrity check are shown separately. The catalog remembers a backup's location, date, size, type and notes; it does not store another copy of the archive. **File missing** means the saved path is absent. **Locate…** verifies a moved backup and reconnects a matching record. **Remove from list…** removes only catalog metadata and never deletes files. Backups are not deleted automatically.
- Keep the game and launcher closed throughout backup. Settings-only backups allow recognized Wine background services; active or unknown applications still block them. Full backups require every process in the selected Wine prefix to exit. The preview checks this before asking for a destination. Metadata comparisons include change timestamps, but are a consistency check rather than a filesystem snapshot.

The selection is based on the [Razor migration FAQ](https://www.razorce.com/faq/), the [ClassicUO settings implementation](https://github.com/ClassicUO/ClassicUO/blob/main/src/ClassicUO.Client/Configuration/Settings.cs) and a read-only inspection of the current Outlands layout. The [ClassicUO launch documentation](https://github.com/ClassicUO/ClassicUO/wiki/Launch-Arguments) also describes custom settings/profile paths, which require separate handling.

## Uninstall

Close Outlands and its launcher. In Finder, move `~/Applications/Sikarugir/outlands.app` to the Trash. **This includes game files and profiles**; copy any profiles you want to keep first. Backups, caches and installer logs can be removed separately when no longer needed. Remove Outlands Installer.app like any other Mac app.

Do not remove the entire `~/Library/Application Support/Sikarugir` directory: other wrappers may use it. Rosetta and any Homebrew/Wine software installed by older versions are shared dependencies and are not removed by this app.

## Build from source

Maintainers need macOS 14.6+, Apple Silicon, Python 3.9+ and Xcode Command Line Tools with Swift 5.9 or newer.

```console
swift test -Xswiftc -warnings-as-errors
python3 tools/build.py
open "dist/Outlands Installer.app"
```

Output: standalone `.app`, distributable ZIP, `SHA256SUMS`, and signing metadata under `dist/`. This build is **ad-hoc signed**. Publishing a smooth end-user experience requires a Developer ID certificate and Apple notarization; [RELEASING.md](docs/RELEASING.md) explains the configured pipeline.

### Continuous checks and updates

| Workflow | Runs | Checks |
| --- | --- | --- |
| [macOS build and tests](.github/workflows/ci.yml) | Push, pull request, manual | Unit tests, release build, bundle resources and signature on macOS 14/15/26 and `macos-latest` |
| [Download and Wine smoke test](.github/workflows/runtime-smoke.yml) | Weekly, manual | Real pinned downloads, hashes, extraction, prefix creation and a Windows command on macOS 15/26/latest |
| [Upstream component review](.github/workflows/upstream.yml) | Weekly, manual | Detects new Sikarugir/Winetricks versions and opens a recipe-update PR for review |
| [Dependabot](.github/dependabot.yml) | Weekly | Updates pinned GitHub Actions dependencies |
| [Signed release candidate](.github/workflows/release.yml) | Manual, protected `release` environment | Tests, Developer ID signing, notarization, stapling and a draft GitHub release |

The project currently has no third-party Swift package dependencies. Dependabot watches Actions; the separate upstream checker watches downloaded runtime components. Neither auto-merges or updates working game installations.

GitHub's current runner list identifies `macos-latest` as Apple Silicon macOS 26; this alias can change. The explicit `macos-26` job keeps Tahoe coverage. [Runner source](https://github.com/actions/runner-images#available-images).

See [TESTING.md](docs/TESTING.md) for test boundaries and the remaining clean-Mac acceptance checklist. The beta implementation passed the [hosted macOS 14/15/26/latest matrix](https://github.com/Srbino/uo-outlands-mac/actions/runs/37199468538), including tests, bounded memory checks and packaged-app verification. This does not certify fresh game login, accessibility or notarization.

## Upstream review: 2026-10-03

- [Sikarugir](https://github.com/Sikarugir-App/Sikarugir) now requires **macOS 14.6+**.
- [Homebrew wine-stable](https://formulae.brew.sh/cask/wine-stable) is **disabled**. The native installer therefore uses upstream Sikarugir components directly.
- The recipe pins **WS12WineSikarugir11.0_1**, **Template 1.0.21**, and commit **0814a5a** of Sikarugir's `sikarugir` Winetricks branch. That fork supplies the `dotnet48` verb and macOS library-path handling. See the [exact manifest](Sources/OutlandsCore/recipe.json).
- The wrapper repository is now [Sikarugir-App/Template](https://github.com/Sikarugir-App/Template/releases/tag/v1.0). Download URLs are taken from upstream release metadata, not guessed from filenames.

The current [official launcher](https://patch.uooutlands.com/download) inspected on this date is a self-contained .NET 9 application. The recipe installs native .NET Framework 4.8 for legacy Windows components and validates it by registry and executable probes. The old `dotnet481` recipe could report success after a no-op Windows servicing operation while leaving only .NET 4.0 installed; it is no longer used.

These are source/version checks, not a claim that all combinations have passed gameplay testing.

## Migration from the shell installer

The native installer replaces `install.sh` and the old install/repair/launch diagnostic scripts. Older instructions that pipe remote scripts into a shell, copy arbitrary Wine libraries, kill every Wine process, or erase shared Sikarugir data should not be used.

The independent, advanced [`helpers/sync-config.sh`](helpers/sync-config.sh) SSH profile-sync utility is retained for existing users. It is not called or bundled by the native installer and is outside the new GUI's tested installation path. Review its backup and SSH options before use.

## Licence and attribution

Installer source: [MIT](LICENSE). Wine, Sikarugir, Winetricks, Microsoft runtimes and Outlands have their own licences. Runtime components are downloaded on demand, not redistributed in the installer ZIP. D3DMetal is subject to Apple's licence; this is an unofficial, non-commercial community helper, not an official Outlands or Apple product.

Upstream monitoring runs daily and assigns new component PRs to the repository owner. It dispatches macOS build and Wine checks explicitly. Pushing a `vX.Y.Z` tag starts the protected signing workflow and creates a draft release; publication follows manual acceptance. See [release setup](docs/RELEASING.md).

## Game management

The app has **Game**, **Backups**, **Diagnostics** and **Settings** sections, with an English interface. Upstream tools and detailed diagnostic messages can remain English.

**Close Outlands processes** asks you to save changes, sends termination to processes belonging to this wrapper, then forcibly stops unresponsive ones after three seconds. It uses kernel executable paths, user IDs and process start times; a Wine process explicitly using a different prefix is excluded. No global `killall` or `pkill` is used. The process list is available in Diagnostics. Processes launched through a separate external Wine engine are outside this manager's scope.

Finder shortcuts open **Contents**, the game folder, Razor settings, scripts and profiles directly. The current Outlands layout stores Razor data in `ClassicUO/Data/Plugins/Assistant`; the old `Razor` directory is supported as a fallback. Missing folders produce a message instead of being silently created. The installation-backup shortcut opens the parent of the game application; portable archives remain in the location you selected.

The backup catalog records known archive locations, dates, sizes, personal notes and the last successful verification. Add older archives using **Add / verify backup**. Verification dates describe a past check; disconnected or changed archives must be checked again. A reminder appears when the catalog has no backup from the last seven days. There is no background scheduler or automatic deletion. Diagnostics lists external game/user symlinks whose target data is excluded from archives.

During installation, backup and restore the app requests that macOS prevent automatic idle sleep; closing a laptop lid, manual sleep or power loss can still interrupt an operation. A stopped or stale rebuild can be preserved and restarted from the UI. Rebuilds compare the original prefix before/after work and include that fingerprint in their retry marker, preventing a stale staged copy from silently replacing newer profiles.

The app icon and sidebar use Game Icons SVG artwork from [React Icons](https://react-icons.github.io/react-icons/) (`react-icons/gi` 5.7.0), with a shared teal palette. Action buttons use standard macOS controls. These are bundled vector assets rendered in SwiftUI; the app requires no React or Node runtime. Artwork is licensed under CC BY 3.0; [individual credits](Sources/OutlandsInstaller/Resources/GameIcons/CREDITS.txt) and the React Icons licence ship with the app. The pinned import manifest is in `tools/game-icons.json`; `tools/import_game_icons.py` verifies the upstream package integrity before regenerating assets. Packaging checks that all bundled artwork loads successfully.

Diagnostics scans run off the UI thread, with progress and cancellation, so inspecting a large game folder does not block navigation. A process count is shown only after it has been checked.

Diagnostics identifies Wine Mono separately from Microsoft .NET Framework; a Mono informational result does not establish that an existing game is broken. Legacy backup activation checks the recovered application structure without requiring the fresh installer's Framework recipe. New installations still require executable runtime probes. Reports use the most recent explicit diagnostic snapshot, avoiding a filesystem scan when opening the report sheet. See the [follow-up findings](docs/review/FINDINGS.md) for the current evidence and remaining release blockers.


### Settings recovery and keyboard navigation

An interrupted settings swap leaves a bounded local recovery journal next to ClassicUO. The Backups page detects it and offers **Recover…**: it rolls back an interrupted first rename or retains the Undo copy after a completed swap. Ambiguous or redirected paths are preserved for inspection. Never delete an original recovery directory until you have checked the game and profiles. Reboot/power-loss behaviour still needs hardware acceptance.

Use Command–1 through Command–4 to switch pages, Command–B to preview a backup, Escape to cancel sheets, and Command–Return to apply reviewed settings. Custom actions and sidebar controls include focus outlines; full button Tab navigation follows your macOS keyboard navigation settings. Increase Contrast strengthens control/card outlines. VoiceOver and comprehensive keyboard/oldest-macOS acceptance are still pending.

# UO Outlands Mac Installer

Automated installation script for [UO Outlands](https://uooutlands.com/) on Apple Silicon Macs using Wine + [Sikarugir](https://github.com/Sikarugir-App).

## Requirements

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 13 (Ventura) or later
- ~10 GB free disk space
- [Homebrew](https://brew.sh) installed
- Internet connection

## Installation

### One-liner (copy & paste into Terminal)

```bash
/bin/bash -c "$(curl -fsSL 'https://api.github.com/repos/Srbino/uo-outlands-mac/contents/install.sh' -H 'Accept: application/vnd.github.raw')"
```

### Step by step

If you've never used Terminal before:

1. Open **Terminal** (press `Cmd + Space`, type `Terminal`, hit Enter)
2. Install [Homebrew](https://brew.sh) (if you don't have it) — paste this and follow the prompts:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
   **Important:** After Homebrew install, follow the instructions it prints to add it to your PATH:
   ```bash
   echo >> ~/.zprofile
   echo 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv zsh)"
   ```
3. Download and run the installer:
   ```bash
   curl -fsSL 'https://api.github.com/repos/Srbino/uo-outlands-mac/contents/install.sh' -H 'Accept: application/vnd.github.raw' -o install.sh
   chmod +x install.sh
   ./install.sh
   ```
4. Follow the on-screen instructions. The Outlands installer GUI will pop up — install the game and **close the installer window** when done.
5. Launch the game by double-clicking `outlands.app` in `~/Applications/Sikarugir/`

The script will install and configure everything automatically:
- Rosetta 2
- Wine Stable + Sikarugir (via Homebrew)
- Latest Wine engine + wrapper template (auto-detected from GitHub)
- Outlands wrapper with D3DMetal, WINEESYNC/WINEMSYNC
- .NET Framework runtimes (dotnet20sp2, dotnet40, dotnet481) with validation
- UO Outlands game client

## Diagnostics

If the game doesn't start, run the diagnostic script:

```bash
curl -fsSL 'https://api.github.com/repos/Srbino/uo-outlands-mac/contents/helpers/fix-and-diagnose.sh' -H 'Accept: application/vnd.github.raw' | bash
```

This auto-fixes known issues and validates 13 checkpoints including Wine, .NET, engine libraries, quarantine, and game files.

### Manual Wine launch (for debugging)

```bash
curl -fsSL 'https://api.github.com/repos/Srbino/uo-outlands-mac/contents/helpers/launch-direct.sh' -H 'Accept: application/vnd.github.raw' | bash
```

## Uninstall

```bash
# Remove game only (wrapper + Sikarugir data)
./install.sh --uninstall

# Remove everything including Wine and Sikarugir brew casks
./install.sh --purge
```

## What It Installs

| Component | Location |
|-----------|----------|
| Wrapper | `~/Applications/Sikarugir/outlands.app` |
| Engines/Templates | `~/Library/Application Support/Sikarugir/` |
| Wine Stable | `/Applications/Wine Stable.app` (via Homebrew) |
| Sikarugir Creator | `/Applications/Sikarugir Creator.app` (via Homebrew) |
| Install log | `~/Library/Logs/outlands_install_*.log` |
| Debug log | `~/Library/Logs/outlands_install_*_debug.log` |
| Audio fix | `~/Library/LaunchAgents/com.sikarugir.outlands.audio.plist` |

## Features

- Bash 3.2 compatible (stock macOS `/bin/bash`)
- Idempotent — safe to re-run, skips completed steps, fixes missing components
- Auto-detects latest engine and template versions from GitHub
- All downloads verified (`curl -f`, non-empty check)
- .NET Framework validation (detects Wine Mono stubs vs real DLLs)
- Wine smoke test after engine injection
- Missing shared library auto-copy from Wine Stable.app
- Quarantine attribute clearing (Homebrew 5.x compatibility)
- Cleanup trap for temp files on failure
- Full install log + separate bash trace debug log

## Manual Installation via Sikarugir Creator

If the automated script fails on .NET installation, you can install manually through Sikarugir Creator:

1. Open `/Applications/Sikarugir Creator.app`
2. Create new wrapper named `outlands` in `~/Applications/Sikarugir/`
3. Select engine: **WS12WineSikarugir 10.0**
4. Configure graphics:
   - **D3DMETAL: ON** (critical)
   - **MOLTENVKCX: ON**
   - **WINEESYNC: ON**
   - **WINEMSYNC: ON**
   - DXVK: OFF, DXMT: OFF, D9VK: OFF
5. Install .NET via Winetricks (in this exact order):
   - `remove_mono`
   - `dotnet20sp2`
   - `dotnet40`
   - `dotnet481`
6. Set Windows version to **Windows 10** (via winecfg or Winetricks `win10`)
7. Set program path: `/Program Files (x86)/Ultima Online Outlands/Outlands.exe`
8. Download Outlands.exe from https://patch.uooutlands.com/download into the wrapper's `drive_c/Program Files (x86)/Ultima Online Outlands/`

## Audio Setup

Wine on macOS often produces audio crackling. The installer configures `SDL_AUDIODRIVER=directsound` via a LaunchAgent which fixes this automatically.

Additional tips:
- Connect headphones/AirPods **before** launching the game (Wine doesn't hot-switch audio)
- Wired headphones work better than Bluetooth for Wine audio
- If crackling persists, open **Audio MIDI Setup.app** and change sample rate to **48000 Hz**

## Troubleshooting

### Installer fails silently at step 1 (Pre-flight checks)
**Cause:** BSD `sed` crashes on non-English locales (`sed: RE error: illegal byte sequence`)
**Fix:** Fixed in v0.3.0. Re-download the latest install.sh.

### `brew: command not found`
**Cause:** Homebrew not in PATH after installation.
**Fix:** Run `eval "$(/opt/homebrew/bin/brew shellenv)"` and add to `~/.zprofile`.

### `Error: Calling the --[no-]quarantine switch is disabled!`
**Cause:** Homebrew 5.x removed the `--no-quarantine` flag.
**Fix:** Fixed in v0.3.0. Script now clears quarantine manually via `xattr -cr`.

### Wine Stable "cannot be opened" / Gatekeeper blocks Wine
**Cause:** macOS quarantine attribute on downloaded app.
**Fix:** Run `xattr -cr "/Applications/Wine Stable.app"`

### `Library not loaded: @rpath/libinotify.0.dylib`
**Cause:** Sikarugir engine bundle doesn't include all shared libraries that wineserver needs.
**Fix:** Fixed in v0.3.0. Script auto-copies missing dylibs from Wine Stable.app. Manual fix:
```bash
cp "/Applications/Wine Stable.app/Contents/Resources/wine/lib/"*.dylib \
   ~/Applications/Sikarugir/outlands.app/Contents/SharedSupport/wine/lib/
```

### Outlands launcher exits with code 255 (no window appears)
**Cause:** .NET Framework installed as Wine Mono stubs (~752KB) instead of real Windows .NET DLLs (~5MB). The Outlands launcher is a .NET WPF application that requires real .NET Framework.
**Fix:** Fixed in v0.4.0. Script now validates DLL sizes after installation. If you hit this:
1. Install .NET manually via Sikarugir Creator Winetricks (see Manual Installation above)
2. Or copy .NET DLLs from a working wrapper

### Outlands launcher exits with code 255 (Windows XP mode)
**Cause:** Wine prefix set to Windows XP, but Outlands launcher requires Windows 10.
**Fix:** Fixed in v0.4.0. Run `winecfg` and set Windows version to Windows 10.

## Tips

- Switch between Razor and Game windows: **Cmd + \`** (backtick)
- Reconfigure wrapper: Right-click `outlands.app` → Show Package Contents → `Configure.app`
- Razor profiles location: `drive_c/users/crossover/Application Data/Razor/`
- Game logs: `drive_c/Program Files (x86)/Ultima Online Outlands/Logs/`
- Debug launch: `~/Applications/Sikarugir/outlands.app/Contents/MacOS/Sikarugir 2>&1 | tee ~/Desktop/debug.log`
- **Kill stuck Wine processes before re-launching** — Wine on macOS doesn't always clean up after itself. If the game won't start, kill all Wine processes first:
  ```bash
  pkill -f wineserver; pkill -f wine; pkill -f Outlands
  ```

## Helper Scripts

| Script | Description |
|--------|-------------|
| `helpers/fix-and-diagnose.sh` | Auto-fix known issues + validate 13 checkpoints (Wine, .NET, engine, quarantine, game files, etc.) |
| `helpers/launch-direct.sh` | Launch Outlands directly via Wine (bypass Sikarugir wrapper for debugging) |
| `helpers/diagnose-wrapper.sh` | Read-only diagnostic — validates all components without making changes |
| `helpers/sync-config.sh` | Backup, restore, and sync ClassicUO profiles/scripts between two Macs via SSH |

Run any helper script directly:
```bash
curl -fsSL 'https://api.github.com/repos/Srbino/uo-outlands-mac/contents/helpers/<script>.sh' \
  -H 'Accept: application/vnd.github.raw' | bash
```

## Changelog

### v0.4.0 (2026-03-31)
- **Fix:** .NET validation now checks DLL file sizes to detect Wine Mono stubs vs real .NET Framework
- **Fix:** Windows version set to Windows 10 (was XP — caused Outlands launcher crash)
- **Add:** Post-install .NET validation with per-version report
- **Add:** Windows version verification after winecfg
- **Add:** `fix-and-diagnose.sh` — comprehensive auto-fix + 13-point diagnostic
- **Add:** `launch-direct.sh` — direct Wine launch for debugging

### v0.3.0 (2026-03-31)
- **Fix:** `sed` crash on non-English locales (Czech, German, etc.) — `LC_ALL=C` for ANSI stripping
- **Fix:** Homebrew 5.x removed `--no-quarantine` — now clears quarantine via `xattr -cr`
- **Fix:** Missing `libinotify.0.dylib` — auto-copies shared libs from Wine Stable.app into engine
- **Fix:** Wine binary detection (`wine` not `wine64` in Sikarugir engine)
- **Add:** Defensive pre-flight validation (macOS version, disk space with locale-safe parsing)
- **Add:** Wine smoke test after wrapper creation
- **Add:** Quarantine clearing for Wine Stable.app and Sikarugir Creator.app
- **Add:** GitHub API URL for downloads (bypasses raw.githubusercontent.com CDN cache)
- **Add:** Idempotent re-run: symlinks, quarantine, dylib copy always execute
- **Add:** `diagnose-wrapper.sh` — wrapper diagnostic script

### v0.2.0 (2026-03-15)
- **Add:** Comprehensive debug logging with separate trace file
- **Add:** Config sync script for multi-Mac setups

### v0.1.0 (2026-03-01)
- Initial release
- Automated Wine + Sikarugir installation
- Audio fix (SDL_AUDIODRIVER=directsound via LaunchAgent)

## Tested On

- M3 MacBook Air, macOS Tahoe (26.3.1)
- M4 Pro MacBook Pro, macOS Tahoe (26.x)
- M4 Mac Mini, macOS Tahoe (26.x)
- Engine: WS12WineSikarugir 10.0 (revision 4)
- Template: 1.0.10
- Homebrew: 5.1.3

## License

MIT

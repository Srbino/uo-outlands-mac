# UO Outlands Mac Installer

Automated installation script for [UO Outlands](https://uooutlands.com/) on Apple Silicon Macs using Wine + [Sikarugir](https://github.com/Sikarugir-App).

## Requirements

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 13 (Ventura) or later
- ~10 GB free disk space
- [Homebrew](https://brew.sh) installed
- Internet connection

## Quick Start

```bash
chmod +x install.sh
./install.sh
```

The script will install and configure everything automatically:
1. Rosetta 2
2. Wine Stable + Sikarugir (via Homebrew)
3. Latest Wine engine + wrapper template (auto-detected from GitHub)
4. Outlands wrapper with D3DMetal, WINEESYNC/WINEMSYNC
5. .NET runtimes (dotnet20sp2, dotnet40, dotnet481)
6. UO Outlands game client

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

## Features

- Bash 3.2 compatible (stock macOS `/bin/bash`)
- Idempotent -- safe to re-run, skips completed steps
- Auto-detects latest engine and template versions from GitHub
- All downloads verified (curl -f, non-empty check)
- Cleanup trap for temp files on failure
- Full install log with timestamps

## Audio Setup

Wine on macOS often produces audio crackling. After installation:

1. Open **Audio MIDI Setup.app** (Spotlight: "audio midi")
2. Select your output device
3. Change sample rate to **48000 Hz** or **96000 Hz**

Wired headphones work better than Bluetooth for Wine audio.

## Tips

- Switch between Razor and Game windows: `Cmd + backtick`
- Reconfigure wrapper: Right-click `outlands.app` -> Show Package Contents -> `Configure.app`
- Razor profiles location: `drive_c/users/crossover/Application Data/Razor/`

## Tested On

- M3 MacBook Air, macOS Tahoe (26.x)
- M4 Mac Mini, macOS Tahoe (26.x)
- Engine: WS12WineSikarugir 10.0
- Template: 1.0.10

## License

MIT

Native macOS installer with a guided interface, verified component downloads, recoverable installation staging and backups when rebuilding.

- No Homebrew or user-run shell installer required.
- Read-only installation checks, live logs and reviewed GitHub problem reports.
- Optional daily checks for new installer releases.
- Apple Silicon, macOS 14.6 or later; 20 GB free space (30 GB for rebuilds).

The Outlands launcher downloads the game on first launch. This is an unofficial community project; Outlands does not officially support macOS. See the README for tested coverage and current limitations.

Known release blocker: the current official launcher exited 255 in a separate manual investigation prefix. Resolve startup in a retained clean installation and complete gameplay acceptance before publishing a stable release. See TESTING.md.

Added full local archive creation, SHA-256 verification and restore into a separate folder, including all Razor/scripts/profiles inside the wrapper. Daily Sikarugir update PRs dispatch macOS checks; version tags start draft release preparation.

Added scoped Outlands process termination, direct Finder shortcuts into the package/game/Razor folders, English navigation, a backup catalog with notes and reminders, activation of recovered copies with preservation of the old app, source consistency checks, idle-sleep prevention and release gates pinned to the exact tag commit.

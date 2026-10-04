# Privacy and diagnostics

There is no analytics SDK, account login, crash-upload service, or embedded GitHub token.

## Network requests

- Optional update checks call this repository's public GitHub Releases API at most once per day, or when **Check now** is clicked. GitHub receives normal connection information such as the IP address and the installer User-Agent. The request contains no logs or diagnostic report. Disable the checkbox to stop automatic checks.
- Installation downloads the pinned Sikarugir engine, template and Winetricks source from GitHub, the official Outlands launcher from `patch.uooutlands.com`, and Microsoft prerequisites through Winetricks. Winetricks uses its upstream download URLs and integrity checks, which may include archival mirrors. Its usage reporting and own latest-version checks are disabled.
- Rosetta installation uses Apple's `softwareupdate` service with the user's licence consent.
- **Continue to GitHub** sends the reviewed report in the URL of a new issue draft. This becomes part of normal browser history. Nothing is posted until the user submits the issue on GitHub.

## Local information

Session logs contain step names, command output and errors. They do not intentionally collect game profiles, usernames, passwords, hostnames, environment-variable dumps or unrelated process output. Local process inspection supports diagnostics, operation preconditions and explicitly confirmed shutdown of this wrapper. Process environment dumps are not logged.

Log files use owner-only file permissions. Common home-path, token, password, email and Authorization patterns are redacted before saving. The export contains a report plus the last 128 KB of the current session log. Redaction is best effort: error messages can contain information no generic pattern recognises. Review exports and issue drafts before sharing them.

No game credentials are required by this installer. Enter them only in the official game client.

Logs and verified caches remain on the Mac until the user removes them. There is no background upload or persistent installer agent. See the README for exact locations. The official game and upstream runtimes have their own privacy behaviour.

Full backup packages are separate from diagnostics: they intentionally contain all files inside the game application, potentially including private profiles and account-related data. They are local and unencrypted, never uploaded or included in issue drafts. External symlink targets are not copied.

Process management reads kernel process metadata and the `WINEPREFIX` setting solely to identify this wrapper and exclude another prefix using its engine. Environment dumps are neither logged nor exported. The local backup catalog stores archive paths, dates, verification times and notes in app preferences; it is not included in issue reports. Diagnostic external-link lists show relative link names without reading their target files.

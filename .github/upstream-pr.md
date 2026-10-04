Official upstream component versions or checksums changed. This updates the pinned recipe; it does not update installed games automatically.

Before merging:

- Review the version, source URL, SHA-256 and size changes. An unchanged filename with a different digest needs explicit investigation.
- Review the explicitly dispatched **macOS build and tests** and **Download and Wine smoke test** runs for this branch. If dispatch failed, run them manually. Token-created PR checks may additionally require approval.
- Complete the clean-install and upgrade checks in `docs/TESTING.md`, including .NET 4.8.1, first game download and gameplay.
- Ship the approved recipe in a new installer release. Do not merge solely because unit tests pass.

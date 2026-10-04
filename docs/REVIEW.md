# Independent review of Outlands for Mac

This package prepares the current implementation for independent technical and UI/UX review. It records what changed, what was observed and what still needs proof. It is a handoff prepared by the implementing assistant, not an independent approval. All review material is in English.

**Recommendation: do not publish a stable release yet.** The critical standalone-comparison memory incident (R13) now has a passing bounded regression; its history and limits remain recorded in [FINDINGS.md](review/FINDINGS.md). See [current acceptance](review/ACCEPTANCE.md) for feature-by-feature results. The earlier exit-255 failure now has a candidate directory-registration fix that prevented immediate exit and allowed game downloads in an isolated prefix. Visible launcher startup, download completion, login, rendering and audio have not passed acceptance. Read [the follow-up findings](review/FINDINGS.md) for the newer evidence.

## Review baseline

Updated on 2026-10-04 for `Srbino/uo-outlands-mac`. The parent commit is `37cffc270516a16bc782f57a0f450f254127f0c6`. The original review baseline was a local working tree with modified files, staged script deletions and untracked source, tests, documentation and workflows. The owner subsequently authorized beta integration on GitHub. Historical local snapshots and findings remain dated evidence; use the reviewed PR/commit for the integrated source. No stable release or independent review approval is claimed.

The review archive produced by `python3 tools/prepare_review.py` contains the current source snapshot, a SHA-256 file manifest, Git status and the tracked-file diff against HEAD. It excludes `.git`, game installations, private backups, caches, credentials, QA prefixes and build outputs. The app ZIP is a separate local development artifact. The manifest identifies the exact reviewed bytes; repeat packaging after any changes.

## Reading order

1. Read this document, especially the release blockers and evidence limits.
2. Use [the review prompt](review/PROMPT.md) as the independent review brief.
3. Review [UI and UX acceptance](review/UI_UX.md), including interaction, accessibility and all non-happy paths.
4. Inspect the source map below and reproduce the relevant tests in a disposable environment.
5. Record findings using [the findings template](review/FINDINGS.md), with file/line references and evidence.
6. Assess [testing](TESTING.md), [release operations](RELEASING.md), [privacy](PRIVACY.md) and the final user-facing [README](../README.md).

## Scope and implementation map

| Area | Implementation | Intended behaviour and review focus |
| --- | --- | --- |
| Native app | `Sources/OutlandsInstaller/App.swift`, `Model.swift`, `Package.swift` | SwiftUI app with Game, Backups, Diagnostics and Settings; English copy; UI state, responsiveness, keyboard and cancellation |
| Installation | `Sources/OutlandsCore/Installer.swift` | Isolated staging, original preservation, retry marker, .NET registry and executable probes, transactional promotion and rollback |
| Downloads | `Downloads.swift`, `recipe.json` | Pinned runtime sizes and hashes, HTTPS, retries, extraction; official launcher is mutable and not cryptographically pinned |
| Process execution | `Command.swift` | Direct argument arrays, bounded output, timeouts, cancellation and process-group termination |
| Shared protection | `Support.swift`, `Snapshot.swift` | Locks, private logs, redaction, metadata fingerprints, archive listing checks; verify limits and races |
| Backups and recovery | `Backups.swift`, `BackupInput.swift`, `BackupArchive.swift`, `SettingsBackup.swift`, `BackupPreview.swift`, `SettingsRecovery.swift`, `Library.swift`, `Sources/CArchive` | Complete in-bundle archive, checksum/readability checks, separate restore, explicit activation preserving current app, catalog and notes |
| Game shutdown | `GameProcesses.swift` | Same-user kernel path and process identity checks; exclude another prefix borrowing this engine; TERM then KILL; no global Wine kill |
| Updates and reports | `Updates.swift`, `Model.swift`, issue templates | Stable release checks; reviewed issue draft; no automatic issue posting, attachments or telemetry |
| Artwork | `GameArt.swift`, `Resources/GameIcons`, `tools/icon.swift`, `tools/import_game_icons.py`, `tools/game-icons.json` | Pinned React Icons Game Icons artwork, teal app icon/sidebar, standard native action buttons, attribution and resource loading |
| Build and release | `tools/build.py`, `tools/release.py`, `.github/workflows/release.yml` | Standalone arm64 bundle, signing checks, optional notarization, protected draft release after required gates |
| Continuous checks | `.github/workflows/ci.yml`, `runtime-smoke.yml` | macOS matrix, normal tests, isolated real Wine smoke tests and optional full install |
| Maintenance | `.github/workflows/upstream.yml`, `.github/dependabot.yml`, `tools/check_upstream.py` | Daily component PR, notification through assignment, explicit check dispatch, no auto-merge; Actions updates |
| Migration | Deleted `install.sh`, `helpers/diagnose-wrapper.sh`, `helpers/fix-and-diagnose.sh`, `helpers/launch-direct.sh` | End users use the app; independent advanced `helpers/sync-config.sh` remains outside native installer coverage |

Core paths in the table are relative to `Sources/OutlandsCore/` unless otherwise specified.

## Evidence and its limits

Local machine: Apple M4, macOS 26.5.1, Swift 6.3.2. A result from this machine is not evidence for every supported macOS or hardware combination. Selected output excerpts are in [review/evidence](review/evidence/); timestamps in XCTest output use the local system time.

| Check | Recorded result | Limit |
| --- | --- | --- |
| Latest normal Swift run | 57 tests executed, 50 passed and 7 deliberately skipped, zero failures | Seven opt-in runtime/archive/inspection tests require explicit environment configuration; no automated UI tests |
| Python tool checks | 11 tests passed | Does not establish actual GitHub workflow permissions or network behaviour |
| Workflow validation | actionlint passed | Static validation only; hosted workflows have not run for this working tree |
| Release build | Warnings treated as errors; successful ad-hoc signature and self-check | Not Developer ID signed or notarized |
| Standalone ZIP | Extracted outside the checkout; signature and bundled recipe/artwork self-check passed | Does not prove Gatekeeper acceptance of an Internet download |
| Real runtime smoke | Previously passed in 65.8 seconds | Earlier local run; no gameplay |
| Full clean install | Retained run passed in 551.4 seconds | Does not start launcher GUI; subsequent launcher experiment failed |
| Real backup | Approximately 3.23 GiB compressed, completed and verified through UI in 128 seconds | Historical manual observation; no external-disk disconnect test |
| Real restore | Separate restore passed in approximately 21 seconds | Original installation not replaced |
| Restored content comparison | Earlier manual comparison matched 9,715 files and 258 links | Comparison transcript/script is not bundled; independently repeat before treating as a release gate |
| Real Wine shutdown | Isolated wrapper test passed in 3.84 seconds; original game process identities unchanged | Uses a disposable QA wrapper; does not cover all Wine launch patterns |
| UI inspection | Navigation, native controls, read-only diagnostics and collapsed process details inspected; earlier report sheet inspected | No complete VoiceOver, keyboard, scale/contrast or oldest-macOS acceptance |

The latest app changes redesigned the four pages (requirements checklist, installation step list, backup table with availability states, global status bar, theme setting, version 0.9.0 beta), removed 22 unused bundled icons, moved the diagnostic filesystem/process scan into a detached task with cancellation, added an unknown process state before scanning and collapsed process details. Unit and build evidence is local. The original game application was not rebuilt, replaced or forcibly closed during these checks.

## Release blockers and open questions

These entries distinguish observed failures from review hypotheses. They are not all confirmed bugs.

| ID | Type | Concern and evidence needed |
| --- | --- | --- |
| R01 | Observed blocker | Earlier direct startup exited 255; staging directory registration now prevents immediate exit in retained-prefix probes. Identify cause, fix or establish a supported launch path, then prove first GUI startup, game download and login. A successful .NET probe is insufficient. |
| R02 | Missing release evidence | No hosted matrix results, Developer ID signature, notarization or clean-Mac Gatekeeper acceptance for this change. Configure credentials/protected environment and obtain results before publication. |
| R03 | Missing hardware acceptance | Rosetta absent/declined, external disk unplug, actual low-space failure, reboot/resume, audio and GPU gameplay remain unverified. |
| R04 | Archive security question | Challenge symlink/hardlink chains, paths containing newlines, malicious manifests, archive bombs, payload changes between verification and extraction, and bsdtar protections. Metadata and SHA checks are not authentication of a third-party backup. |
| R05 | Consistency question | Metadata fingerprints are not filesystem snapshots or full content hashes. Probe same-size writes with preserved timestamps, externally launched Wine, and mutation during copy/promotion. Do not assume the lock stops other applications. |
| R06 | Runtime scope question | Shutdown intentionally ignores Wine engines outside the selected wrapper. Test PID reuse, missing process permissions, children starting during shutdown and another prefix borrowing the engine. |
| R07 | UI responsiveness question | Diagnostics traversal moved off the main thread. Other paths still use synchronous filesystem calls and modal panels. Test report preparation, catalog access, process refresh and launch failures on slow or disconnected volumes. |
| R08 | Recovery compatibility question | Activation now checks recovered wrapper structure independently of the fresh-install .NET recipe. Test a valid legacy installation that runs with different runtime contents; verify useful messaging rather than assuming all backups are activatable. |
| R09 | CI configuration question | Confirm runner architecture and disk capacity in actual Actions jobs. Full install needs 20 GB free; standard capacity may be insufficient. Verify reusable workflows and immutable source inputs, tag/version consistency, environment protection and duplicate upstream PR handling. |
| R10 | UI and accessibility question | Validate tab order, visible focus, VoiceOver labels, native button states, long paths, scroll behaviour, contrast and minimum window size on supported OS versions. |
| R11 | Privacy and provenance question | Redaction is best effort. Reports sent in a browser URL can enter history. Check exports, backup notes/paths and errors for secrets; review all asset credits and pinned import provenance. |
| R12 | Maintenance boundary | Update checks open a release page, not an automatic updater. Backups are manual, local and unencrypted, with no automatic retention. Upstream notification is a GitHub PR assignment, subject to owner settings. Confirm these boundaries are clear to users. |

Additional visible UX concern: operation status now lives in one bottom status bar, so a completed diagnostic message can still be visible on another page. Evaluate whether that reads as global status. Long checks can also require scrolling to reach secondary actions. These are review candidates, not acceptance claims.

## Reproduction commands

Start with a disposable copy of the source archive or a clean checkout containing all new files. No credentials are needed for normal local checks. Use an Apple Silicon Mac and the deployment/toolchain requirements in `Package.swift`.

```console
swift test -Xswiftc -warnings-as-errors
python3 -m unittest discover -s tools -p 'test_*.py'
actionlint
python3 tools/build.py
"dist/Outlands Installer.app/Contents/MacOS/OutlandsInstaller" --self-check
```

The native app resolves the real user's game path. Use a disposable macOS account for destructive/manual acceptance. A clean checkout alone does not isolate GUI operations. Do not click rebuild, activate or close processes against someone's production game to test this package.

Read [TESTING.md](TESTING.md) before opt-in tests. On a disposable environment with Rosetta already present:

```console
OUTLANDS_NETWORK_TESTS=1 swift test --filter IntegrationTests
OUTLANDS_FULL_INSTALL_TESTS=1 swift test --filter FullInstallTests
```

The first full installation command can require 20 GB free and substantial downloads. Set `OUTLANDS_TEST_ROOT` to an appropriate disposable test volume if necessary. The full installation test does not prove GUI startup. Set `OUTLANDS_KEEP_TEST_INSTALL=1` to retain a successful isolated installation for launcher investigation; otherwise successful test homes are removed. See [launcher investigation notes](review/LAUNCHER.md) before interpreting the existing failure. Real backup restore and Wine shutdown tests require explicit disposable paths documented in their test source; do not invent a production target.

## Acceptance decision

The reviewer should return a prioritized finding list and separate verdicts for code/data safety, UI/UX, automation and stable-release readiness. Every blocker needs a reproduction or a clearly stated evidence gap, an owner and an acceptance condition. Re-run relevant tests after fixes. Do not turn unchecked acceptance items into passes based on code inspection alone.

Stable publication requires resolving R01, successful hosted gates for the exact source revision, signing/notarization, and hardware acceptance. No review or publication is automatically authorized by generating this package.

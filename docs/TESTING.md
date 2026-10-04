# Test coverage and acceptance

## Automated local tests

```console
swift test -Xswiftc -warnings-as-errors
python3 tools/build.py
"dist/Outlands Installer.app/Contents/MacOS/OutlandsInstaller" --self-check
```

The unit tests cover checksums and truncated downloads, archive path traversal, PE headers, transactional promotion and rollback, concurrent-install locks, subprocess argument handling, failure/timeout/cancellation, private-output exclusion, redaction, issue URL encoding, read-only diagnostics, semantic versions, and GitHub release responses including no releases, rate limits, invalid JSON and unexpected download destinations.

`--self-check` reads the recipe from the packaged app's resources. CI also runs it from a copy outside the checkout so that an accidentally missing resource cannot be hidden by SwiftPM's build directory.

## Opt-in real runtime test

On an Apple Silicon Mac with Rosetta already installed:

```console
OUTLANDS_NETWORK_TESTS=1 swift test --filter IntegrationTests
```

This downloads pinned components into a temporary area, checks SHA-256 and archive layout, creates an isolated wrapper and prefix, verifies support for the required Winetricks verb, and runs a Windows command. It does **not** use or modify the user's game wrapper. Failed integration artifacts are retained at the path printed by the test; successful temporary wrappers are removed. Optional `OUTLANDS_COMPONENT_CACHE` and `OUTLANDS_TEST_LOGS` paths allow a disposable CI runner to retain cached downloads and logs.

The scheduled GitHub workflow runs on `macos-15`, `macos-26` and `macos-latest`, installs Rosetta on the disposable runner, and saves logs even on failure. It does not log into Outlands, use private credentials, download the complete game, or simulate GPU gameplay. Runner timeouts bound stalled jobs.

## Opt-in complete installer test

```console
OUTLANDS_FULL_INSTALL_TESTS=1 swift test --filter FullInstallTests
```

This exercises the actual installation pipeline in an isolated temporary home, including .NET installation, the release registry value, x86/x64 managed WPF probes, the official launcher download, and final promotion. It needs Rosetta already installed and 20 GB free on the test volume. `OUTLANDS_TEST_ROOT` can point to a test folder on a larger volume. It does not open the game, download game assets or log in. Successful test homes are removed; failures retain artifacts for investigation. The runtime workflow has a **full_install** manual option for the same check.

## Hardware acceptance before a stable release

Use a disposable macOS account or a dedicated test Mac. Record macOS version, Mac chip, installer version, recipe revision, and results in the release notes. Never label a release “fully tested” based only on unit tests.

- [ ] Clean supported macOS without Homebrew, Wine or Sikarugir: GUI install and first game download.
- [ ] Rosetta missing: declined consent, accepted consent, interrupted Apple installer and retry.
- [ ] .NET 2.0 SP2, 4.0, 4.8 and Windows 10 setup. The installer verifies the 4.8 release registry value, DLLs and actual x86/x64 managed programs that load WPF.
- [ ] Open the official launcher, finish its download, run Verify, log in and play with graphics, Razor and audio.
- [ ] Quit and relaunch after a reboot; test wired and Bluetooth output.
- [ ] Interrupted download, offline launch, GitHub rate limiting, low disk space, corrupt cache and cancellation during each long step.
- [ ] Resume staged installation after closing the installer or an OS restart.
- [ ] Existing legacy installation: preserve profiles, rebuild with backup, verify the backup and rollback.
- [ ] Low space during copying: preserve the original and show an actionable error.
- [ ] Concurrent installer windows/processes: second writer is refused.
- [ ] Non-English macOS, spaces and non-ASCII home paths, minimum macOS 14.6 and current stable macOS.
- [ ] Notarized ZIP downloaded through a browser on a clean Mac: Gatekeeper, opening, update link, diagnostics export and public issue draft review.

## Remaining boundaries

A file check does not validate the rendering path or server compatibility. The official Outlands launcher is mutable and has no pinned digest in this repository; its HTTPS origin and PE structure are checked, but this is not an Authenticode verification. Wine and Winetricks can change behaviour independently of this app, which is why the component recipe is pinned and upstream changes require review.

Signing/notarization requires the repository owner's Apple Developer credentials. GitHub-hosted matrix results only exist after the workflows are pushed and run; local execution on one Mac cannot stand in for the entire matrix.

## Runtime version evidence

The installer follows [Microsoft's release-key detection guidance](https://learn.microsoft.com/en-us/dotnet/framework/install/how-to-determine-which-versions-are-installed): `Release >= 528040` establishes .NET Framework 4.8 or newer. It additionally compiles and executes x86 and x64 managed probes that load WPF.

The 2026-10-03 investigation reproduced a misleading success from `dotnet481`: the Wine servicing path returned a restart-success code but left .NET 4.0 files and no `Release` value. The recipe therefore uses `dotnet48`, whose installed release value was verified as `528049` on the local test Mac. The downloaded official Outlands launcher contained `.NETCoreApp,Version=v9.0`; do not describe that launcher as a .NET Framework 4.8.1 application.

## Recorded local validation — 2026-10-03

Apple M4, macOS 26.5.1, Swift 6.3.2; recipe revision 2. Tests used isolated prefixes and did not change the existing game installation.

| Check | Result |
| --- | --- |
| Swift tests in the latest default run | 26 passed; four opt-in integration tests skipped; release build passed with warnings as errors |
| Upstream checker unit tests | 4 passed |
| Download / Wine integration | Passed, 65.8 seconds |
| Full fresh installation including .NET/WPF and transactional promotion | Passed, 521.9 seconds |
| Workflow static validation | actionlint passed |
| Release build, ad-hoc signature and bundled recipe self-check | Passed |
| Native installer UI and reviewed issue sheet | Opened and inspected; no issue submitted |
| GitHub-hosted matrix / Apple notarization | Not run locally; requires repository execution / owner credentials |
| Official launcher opening and gameplay | **Release blocker: not passed** |

The initial launcher experiment used a separate investigation prefix and exited 255 before displaying a window. A later retained clean installation also reproduced direct-launch exit 255; trying the existing Wine 10 engine in that test prefix did not resolve it. Opening through the Sikarugir wrapper stalled in an earlier investigation, with a sampled stack waiting for Wine servers. The cause remains unresolved. Do not work around this by terminating unrelated Wine processes. First login, game download, graphics and audio remain unverified.

## Backup coverage

The backup tests archive and restore an isolated wrapper with a Unicode Razor script and a dangling external symlink; compare recovered bytes; preserve the current app; reject overwriting an existing backup, damaged payloads and a recursive destination; and verify cancellation removes partial output. Archive tests run in the normal macOS matrix, without downloading the game. A real full-wrapper backup also completed through the native UI on the local M4/macOS 26.5.1: approximately 3.23 GiB compressed, in 128 seconds including SHA-256 and complete archive-read verification. The existing installation was preserved. Restoring this real backup over the active game was intentionally not performed; automated isolated restore passed. External-drive unplug handling still requires hardware acceptance.

## Management acceptance — 2026-10-03

- A second clean installation completed in 551.4 seconds and was retained for launcher checks. The downloaded launcher still exited 255 when invoked directly in that clean prefix. Testing the existing Wine 10 engine in that investigation prefix did not resolve the direct-launch failure. No engine downgrade was shipped.
- The real 3.23 GiB backup was restored into a separate test directory in 21.0 seconds. A streaming comparison against the archive matched **9,715 files byte-for-byte and 258 symbolic links**. The user's active installation was not replaced.
- Added kernel process ownership tests, including an unrelated similarly named wrapper and another Wine prefix borrowing the selected engine. macOS test executables are ad-hoc signed after copying to avoid platform-binary signature failures. Added activation/backup-preservation and source-metadata-change tests.
- The release job now requires the build matrix, runtime matrix and full installation for the same resolved commit. These remote gates still require actual GitHub execution; local actionlint is a static check only.

Optional real Wine process test: set `OUTLANDS_PROCESS_TEST_WRAPPER` to a disposable `.qa` wrapper and run `swift test --filter WineProcessTests`. It verifies termination in that wrapper while checking identities of processes belonging to the active user installation remain unchanged. Never use a production wrapper as the disposable target.

Unplugging a real external disk, Rosetta installation on a clean Mac, first login, graphics/audio and notarized Gatekeeper acceptance still require hardware testing. Local process and archive tests do not simulate those conditions.

The opt-in real Wine process shutdown test passed in 3.84 seconds on the retained clean wrapper. Processes belonging to the active user installation kept their original kernel identities. Normal automated coverage is now 26 Swift tests plus 4 Python tests; four opt-in integration tests are skipped by default.

## Review evidence

The independent review package starts at [REVIEW.md](REVIEW.md). It contains selected historical test results and distinguishes those results from checks that still need to run. The latest UI build uses consistent custom action button styles, follows the system appearance, keeps game artwork in the app identity and sidebar, runs diagnostics scanning off the main thread and collapses process details. The default test suite does not provide automated UI or accessibility coverage.

## Handoff follow-up on 2026-10-03

Baseline passed 30 tests with 4 skips. After the follow-up, the normal suite passes 28 tests with 6 opt-in skips (34 total). Two new normal checks cover Mono/unknown assembly classification and architecture-specific registry parsing. Legacy activation preservation no longer relies on a fake large Framework DLL. The new opt-in `FrameworkTests.testReadOnlyRuntimeInspectionWhenRequested` reads `OUTLANDS_INSPECT_WRAPPER` without executing Wine; set `OUTLANDS_EXPECT_MONO=1` for the known Mono case. Both production read-only and clean QA inspections passed.

`OUTLANDS_LAUNCHER_TEST_WRAPPER` enables the registration regression test only for a disposable `.qa` wrapper. It passed, as did scoped QA process shutdown. The full-install test now checks registration after promotion, but the complete pipeline was not rerun in this follow-up. Launcher probes and remaining acceptance limits are in [LAUNCHER.md](review/LAUNCHER.md); the current findings are in [FINDINGS.md](review/FINDINGS.md).

The staged launcher registration allowed game download activity; it does not establish a visible working window, a complete verified game, or login. No Rosetta installation, licence acceptance, production mutation, global Wine shutdown or public issue submission was performed.


## Backup and responsiveness follow-up — 2026-10-04

Implemented private-copy restoration: source payloads are opened as regular files without following replacement symlinks, copied while checking SHA-256, then inspected and extracted only from private staging. Verification uses macOS system libarchive through the small CArchive declaration shim; it reads all entry bodies instead of relying on bounded, line-based tar output. Validation checks expanded size, traversal, duplicate/case-normalized paths, special files, link ancestors and hard-link chains. External symbolic links remain links. It does not authenticate a backup or make executable content trustworthy. Conservative path restrictions can reject archives containing case-only collisions or newline/backslash names.

Six new normal tests cover malicious entries, understated expanded size, payload symlinks, source replacement after private-copy verification, cancellation during restore, changing source bytes while preserving modification time, and valid internal hard links/external symlinks. The full normal suite passes **40 tests total, 6 opt-in skips, 0 failures** (34 passed), with warnings as errors. Temporary restore/backup output is checked absent after failures. Metadata snapshots now include lstat change timestamps and mode; they still do not provide a filesystem snapshot against arbitrary concurrent writers.

Folder resolution, startup/staging existence checks, post-operation checks, staged-copy preservation, process inspection/shutdown, and diagnostic export now run outside the main thread. Views use cached staging state refreshed on activation and operation completion. Backup availability refreshes discard older results. These code changes build successfully; slow-volume interaction, VoiceOver and complete keyboard focus acceptance have not been reverified in this follow-up.

No production installation was modified or stopped. No fresh game installation, commit, push, publication, issue submission, Rosetta installation or licence acceptance was performed. R01 remains open for visible launcher/gameplay acceptance; hosted CI, signing/notarization, oldest supported macOS and hardware interruption tests remain unverified.

Final release build, strict ad-hoc signature verification, bundled self-check, and extraction/self-check outside the checkout passed. Python tests: 4 passed; actionlint and tracked diff whitespace checks passed. See evidence/backup-followup.json and evidence/app-artifact.json in the review directory for this follow-up. The app remains a local, unnotarized development artifact.


## Selective settings backups — 2026-10-04

The GUI defaults to Settings & scripts; Full installation remains optional. Format 2 identifies selective settings packages; format 1 and old catalogs remain supported. Selection includes ClassicUO settings.json, Data/Profiles, shared client configuration/map icons/fonts, and both Assistant/Razor profiles/scripts/macros/language/config files. It excludes game assets, Wine, plugin binaries and journal logs. Selection was checked against https://www.razorce.com/faq/ and the upstream ClassicUO Settings.cs and Launch-Arguments documentation, plus read-only directory inspection of the owner's current layout.

Restore keeps settings separate, writes restore instructions and does not offer full-app activation for a settings-only recovery. Copying recovered settings into a current installation is manual. Custom profilespath, redirected roots and unsupported custom layouts are explicitly outside automatic coverage. No production files were changed.

Catalog rows now show scope, explain that catalog entries are saved locations, and offer Locate and Remove from list. Relocation verifies the selected package; a date/size match reconnects the old record and preserves its note, while a different backup is added separately. Removal does not delete files. Missing files are not treated as successful availability checks.

Five additional normal tests cover selective round-trip/exclusions and both layouts, redirected settings roots, custom profilespath, legacy manifest/catalog decoding, and a settings manifest trying to include non-settings members. Current suite: **45 total, 6 opt-in skips, 39 passed, 0 failures**, warnings as errors. Remaining game-launcher, hardware, hosted CI and accessibility acceptance items are unchanged.


## Backup preview and settings recovery UI — 2026-10-04

Added a read-only backup preview (file/profile-file/script/macro counts, uncompressed data and links), per-file settings import review with search, All/None/New only selection, and explicit apply. Recovery preserves the previous complete ClassicUO directory for Undo, merges only selected regular files into a prepared copy, rejects redirected sources/destinations, checks source/current metadata again before promotion and keeps a bounded rename-recovery journal. The game assets and Wine engine remain outside the swapped directory. Preparation needs additional space for ClassicUO, not only the small settings archive. Old directories and interrupted staging are retained for inspection.

The catalog now has names, sorting, Refresh locations, and separate availability/last-integrity-check text. Game status separates an installation being found from passed local checks and unverified game startup. Operations expose phase messages, elapsed time and actionable completion; there is no fabricated percentage/ETA for unmeasured compression. Targeted recovery actions supplement error/report/dismiss controls. Focus outlines cover actions, tiles, links and sidebar buttons; Increase Contrast strengthens outlines. Page, preview and sheet keyboard shortcuts were added.

Normal suite: **53 tests total, 6 opt-in skips, 47 passed, 0 failures**, warnings as errors. Eight added tests cover preview counts, selective merge and Undo, stale source rejection, injected swap failure/rollback, cancellation/cleanup, redirected destinations/unrelated Undo, interrupted rename recovery and completed/unsafe journals. The tests use disposable folders only.

Bundled UI observed: revised Game status, catalog layout, read-only production settings preview (about 32.7 MB uncompressed; no backup created), and Escape cancellation. Command–2 navigation was observed after state refresh. Full Keyboard Access/VoiceOver, every recovery sheet interaction, minimum window/large text, oldest supported macOS and real power loss remain acceptance work. Core apply/Undo/recovery were executed only on fixtures; the owner's game was not modified or stopped. UI automation encountered repeated external state changes during an isolated archive-picker attempt; no production apply was performed.


## 2026-10-04: settings backup process guard and runtime diagnostics

The reported backup failure was reproduced in the session log before archive creation. Read-only native inspection found 47 owned Wine background services and no recognized applications. Settings backups and selective settings recovery now allow a bounded list of kernel-reported Wine services only when the native executable is a recognized Wine engine. Game, launcher, unknown applications and misleading names remain blockers. Full backups still require the entire selected prefix to be closed. Backup preview performs the process guard before destination selection. No production process was stopped.

An actual read-only settings backup of the production installation succeeded into an isolated external-SSD `.qa` directory: 15,581,230 compressed bytes / 32,686,615 source bytes. Verification and restoration into a separate QA directory succeeded; source ClassicUO metadata remained unchanged. No settings were applied to production, and private archives are excluded from the review package.

Both production Framework assemblies remain 752,128-byte Mono assemblies with SHA-256 `57dad5c007d52244b7681eacbbf83f9cf03824e83b86884e84f3461bf40cccdf`. No `clr.dll`, `mscorwks.dll` or `mscoree.dll` was found in either inspected v4.0.30319 Framework directory. This is read-only identification, not an executable compatibility test. Wine Mono is now informational in the UI and reports; Microsoft .NET is not certified from registry values alone. Fresh-install executable runtime gates remain unchanged.

Validation: 55 Swift tests, 6 opt-in skips, 0 failures (49 passed), warnings as errors. The targeted opt-in read-only production runtime test also passed. New tests distinguish Wine services from application or spoofed names and require CLR plus matching architecture-specific installed registry evidence for a Microsoft candidate. Launcher/login/gameplay acceptance remains open.

Bundled UI verification: Diagnostics displayed 5 verified, 2 informational and 0 needing attention, with 0 applications / 47 background services. Settings backup preview opened successfully and was cancelled before destination selection. Release build, strict ad-hoc signature, bundled and extracted self-check passed. Python tests (4), actionlint and whitespace checks passed. The desktop shortcut targets this local unnotarized app. See `evidence/backup-process-runtime.json`.


## 2026-10-04: backup page horizontal overflow

Reproduced with the owner's available settings archive plus a missing full archive: the five-column Grid and action buttons expanded beyond a narrow window, clipping the sidebar and right-hand actions. The page now receives an explicit viewport width. Backup collection uses a compact stacked record layout when the complete table cannot fit; table actions are shared by both layouts. Backup information chips and page-header actions also have vertical fallbacks. Backup content and catalog records were not changed.

Bundled UI was visually verified at the minimum allowed window width (940 points), at 960 points and at a wider 1263-point window, using both available and missing records. All sidebar content, name/note fields and backup actions were visible; wider windows selected the table and smaller windows selected stacked records. No backup, restore, game launch or process termination was performed during this layout fix. Normal Swift suite: 55 tests, 6 skips, 0 failures; warnings as errors. Python tests (4), actionlint, whitespace checks, release build and extracted signature/self-check passed. Full VoiceOver and historical macOS acceptance remain unverified. Desktop shortcut targets this rebuilt local development app.


## 2026-10-04: expanded validation and critical memory-pressure incident (R13)

Normal suite after adding the disposable managed runtime test: 56 total, 7 opt-in skips, 49 passed, 0 failures. Additional explicit QA tests passed: pinned-component extraction/new Wine prefix/Windows command (66.400 s on the external SSD); exact x86/x64 installer WPF probes; launcher registry registration; selected-prefix process shutdown with production identities unchanged; production read-only Mono classification. The targeted Framework/Launcher/Process run executed 7 tests without skips/failures. Fresh .NET installation/full clean installer pipeline and visible launcher/login/gameplay were not rerun or certified.

Bundled UI: verified the actual settings archive, exported redacted diagnostics locally, opened and cancelled the issue draft, restored the actual settings package into a separate external QA folder, and reviewed 1,120 import candidates without applying anything. Clear selection disabled Apply; search filtered the list. Light appearance was inspected and restored to System. GitHub returned rate limiting; the UI correctly exposed that condition, but a live successful update response was not verified. Escape cancellation passed. Command page shortcuts were not reliably observed; complete keyboard/VoiceOver acceptance remains open. Bulk import labels now explicitly say All files / Clear all / New files only; preview/comparison success and failure messages no longer retain an in-progress status after completion.

A real full backup of the retained QA wrapper completed and verified (6,972,423,983 compressed bytes), and restored to a separate external QA directory. The subsequent standalone file-by-file comparison was interrupted by a system restart: it MUST NOT be recorded as passed. The backup source was a disposable .qa wrapper, not production. Backup packages and actual restore output were on SSD 990 PRO. Some earlier small fixture tests and the first integration bootstrap used macOS's internal temporary directory; all test fixture roots now honor OUTLANDS_TEST_ROOT and otherwise default to .qa/unit-tests in the checkout. Local QA commands must use the external root explicitly. User directive: never save backups on the internal disk.

**Critical incident, R13 OPEN:** JetsamEvent at 11:44:30 names outlands-full-qa-validation (PID 12071) as the largest process, with 11,484,463,104 accounted bytes. Pre-restart observation: approximately 208 MiB free on the startup volume and 15,616 MiB swap fully occupied. The 11:50:49 panic reports WindowServer watchdog check-in timeout (120 s), compressor segment exhaustion and low swap space. This strongly implicates the implementing agent's unbounded standalone comparison workload in the incident; it is not proof that a user GUI backup alone triggers the same failure. After restart the helper was absent, startup free space was about 36 GiB and swap was empty. No other user's process was signaled.

Foundation streaming hash/copy loops now drain an autorelease pool per chunk to avoid retaining temporary NSData across long synchronous workloads. This is a defensive correction to a suspected mechanism, not a confirmed large-load resolution. Small fixture checks pass; the large comparison was not restarted. No stable-release sign-off. Future large verification requires a disposable machine, bounded memory/CPU, runtime memory and startup-disk monitoring, and abort thresholds; never repeat the unbounded helper on the owner's Mac. Raw crash/system reports and private QA data are excluded from the review archive.

Post-incident packaging: release compilation with two jobs, small external fixture suite (56 total / 7 skips / 0 failures), Python tests (4), actionlint, whitespace checks and extracted ad-hoc signature/resource self-check passed. No large-load test was restarted. The desktop shortcut points to the rebuilt app; no new post-restart UI or gameplay acceptance is claimed.


## 2026-10-04: bounded completion of R13 validation

Following the owner's instruction to complete verification, new QA subprocesses ran under an external resource supervisor: 256 MiB monitored physical-footprint threshold, 50 ms sampling, 10 GiB startup-disk reserve, 120 s wall-clock bound, 90 s CPU bound, lower scheduling priority, no core dumps, and termination only of the new QA process group. Memory measurement uses macOS proc_pid_rusage physical footprint rather than RSS, so compressed private memory is counted. Loss of monitoring aborts the QA child. No unbounded helper was restarted.

- Repeated SHA-256 checks: 128 repetitions of a 16 MiB external fixture, peak 4,342,216 bytes (1.123 s). A subsequent run of the checked-in CI driver also passed at 4,325,832 bytes.
- Full restored QA application comparison: 15,315 regular files matched by SHA-256 and 262 symbolic links matched by target; source fingerprint unchanged. Peak 17,662,480 bytes, 34.760 s.
- Full archive verification after the fix: 6,972,423,983 compressed bytes, peak 12,059,152 bytes, 19.774 s.
- A new full restoration through the actual private-copy/extraction code completed into an external QA directory. Peak of the QA parent 13,107,728 bytes, 53.585 s. Native tar runs in the same supervised process group; its separate footprint is not included in the parent peak statistic.

The per-chunk Foundation autorelease fix and per-file pool in the standalone comparison resolved the observed accumulation in these bounded cases. R13's targeted regression is now verified; retain the incident history and never infer universal resource guarantees or GUI/gameplay acceptance from these measurements. Startup volume remained approximately 33 GiB free and swap remained empty during the bounded runs. Backup packages, fixture inputs, recovered files, binaries and logs were on SSD 990 PRO only.

The normal Swift suite remains 56 total / 7 opt-in skips / 49 passed / 0 failures. Python suite now has 11 passing tests, including watchdog boundary, fail-closed monitoring and process-group cleanup tests. CI gained the bounded checksum regression via tools/verify_backup_resources.py; the driver was executed locally. Hosted CI execution, signing/notarization, fresh installer GUI/login/gameplay, full accessibility and hardware interruption acceptance remain unverified. The current feature-by-feature verdict is in ACCEPTANCE.md.


## 2026-10-04: final beta integration preparation

The owner authorized continuing toward GitHub beta integration; this does not authorize a stable release. R06 was tightened before integration: a recognized Wine engine with absent/unreadable WINEPREFIX now blocks ownership inspection and shutdown instead of falling back to executable location. Prefix and kernel identity are rechecked before each signal. A new disposable executable test proves an ambiguous Wine process remains alive; known borrowed prefixes remain excluded. Native bundle helpers retain directory-based ownership. Remaining adversarial race/external-engine boundaries are not claimed closed.

Final normal baseline: 57 Swift tests, 7 opt-in skips, 50 passed, 0 failures, warnings as errors; 11 Python tests passed. Release integration is beta only. Launcher/login/gameplay, complete accessibility, Apple signing/notarization and hosted workflow execution remain explicit acceptance boundaries. No tag or stable release is part of this integration.

Final scoped-process validation: 6 targeted tests passed without skips, including real Wine shutdown in the disposable external wrapper and unchanged production process identities. A Wine child disappearing between identity and environment reads is ignored only after the kernel identity no longer matches; live ambiguous engines still block shutdown.

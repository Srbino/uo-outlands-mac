# Follow-up review findings

Status: partial implementation follow-up on 2026-10-03. This is not independent sign-off. Baseline was uncommitted `0.9.0 beta` on parent `37cffc270516a16bc782f57a0f450f254127f0c6`. No commit, push, tag, issue submission or publication was performed.

## Verdicts

| Area | Verdict | Evidence still needed |
| --- | --- | --- |
| Code and data safety | Targeted fixes and local regression checks passed | Complete adversarial archive/race and recovery acceptance |
| UI and UX | Real catalog, diagnostics, report and Light appearance inspected | Full Keyboard Access, VoiceOver, increased contrast, minimum size and macOS 14.6 |
| CI and release | Static validation passed; local app built and self-checked | Hosted matrix, protected environment, signing, notarization and Gatekeeper |
| Stable publication | Blocked | Visible launcher, first login, complete download verification, Razor, graphics/audio and relaunch |

## High severity launcher first-run deployment failure

**R01, provisional fix, acceptance open.** Source: `Sources/OutlandsCore/Installer.swift`, `registerLauncherDirectory` (line 276).

Reproduction in the retained isolated prefix produced exit 255 with both inherited and minimal environments. The Wine trace showed a copy into a nonexistent nested game directory. Registering the intended `InstallDir` changed the outcome: no immediate exit during 25- and 120-second probes, followed by approximately 6.8 GB of downloaded game files. Normal wrapper GUI opening could not be verified through the available computer-use interface.

The installer now writes the known game directory in the staging prefix before promotion. A real Wine regression test verified the registry value. Do not close this finding until a new clean GUI install, download verification, first login and relaunch pass. See [launcher notes](LAUNCHER.md). The .NET Framework diagnostic problem below is distinct from this self-contained modern .NET launcher's directory-deployment failure.

## Medium severity misleading Framework diagnosis and legacy activation rejection

**R08, code corrected.** Sources: `Sources/OutlandsCore/FrameworkInspection.swift:5`, `Installer.swift:49`, `Backups.swift:113`.

Both production `mscorlib.dll` files are 752,128 bytes and byte-identical to the bundled Wine Mono 9.4.0 `lib/mono/4.0-api/mscorlib.dll`; SHA-256 `57dad5c007d52244b7681eacbbf83f9cf03824e83b86884e84f3461bf40cccdf`. They contain Mono attribution. These are Mono API/reference assemblies, not an unidentified small Microsoft Framework version. The registry alone is insufficient: this prefix also contains a Microsoft-style Framework release key. The clean QA prefix instead has architecture-specific Microsoft assemblies and release 528049.

The size threshold was replaced by read-only identification of Mono attribution, Microsoft file evidence, CLR presence and the corresponding architecture's installed/release registry key. Unknown or Mono contents are not certified as Microsoft .NET. Wording explicitly avoids declaring a working legacy game broken. Fresh installations still require the existing executable x86/x64 WPF runtime probes.

Recovery activation now checks wrapper/engine/prefix/launcher structure independently of the new runtime recipe, allowing legacy backups to be activated with the existing trust confirmation. A regression test proved current-installation preservation when the restored fixture has no Microsoft Framework. Real production reads and clean-prefix reads passed targeted inspection tests. Real legacy activation and gameplay were not performed.

## Medium severity unavailable backup described as verified

**R10, corrected and observed in the final UI.** Sources: `Sources/OutlandsInstaller/App.swift:238`, `Model.swift:54`.

The actual catalog contained a currently missing archive. Its table correctly showed Not found, but the sidebar displayed a teal verified status. The sidebar now uses availability, labels missing/disconnected/pending states, and distinguishes past verification. The recent-backup reminder counts available records. The existing catalog and files were not edited to manufacture the failure.

## Low severity non-English relative time

**R10, corrected.** `Sources/OutlandsInstaller/App.swift`, `backupSummary`.

On Czech macOS, the app-owned relative date rendered in Czech. Its formatter now explicitly uses English. Native regional numeric dates/file sizes can still follow system preferences. Available-record relative-date rendering remains to be rechecked with a currently available archive; the missing-record branch was verified directly.

## Medium severity synchronous report preparation

**R07, partially corrected.** `Sources/OutlandsInstaller/Model.swift:345`, `Sources/OutlandsCore/Updates.swift`, `ProblemReport.make`.

Preparing a report previously rescanned runtime files synchronously on the UI thread. Reports now use the latest explicit diagnostic snapshot and clearly state that no new scan was performed. The report sheet opened with this wording and was cancelled without transmission. `openFolder`, initial local-file checks and the staging view's synchronous existence check still require slow/disconnected-volume review.

## Remaining review questions

| IDs | Work performed | What remains |
| --- | --- | --- |
| R04 | Isolated direct macOS bsdtar symlink, hardlink and parent-traversal extraction probes all failed safely with external sentinel unchanged | Full pipeline tests for link chains, newline names, decompression limits, understated manifest sizes and verification/extraction races. Manifest checksum is not authentication. |
| R05 | Metadata fingerprint implementation inspected; limits documented | Same-size/time-preserving mutations and concurrent external writers are not excluded by metadata fingerprints. No filesystem snapshot guarantee. |
| R06 | Normal process tests and real QA Wine shutdown passed; production identities checked unchanged | Adversarial PID churn, unreadable environment metadata and external engines. Latest beta preparation blocks live Wine engines with missing prefix metadata; native helpers retain executable ownership. |
| R09 | actionlint passed | Actual runner architecture/storage, protected environment, required gates and upstream dispatch permissions on GitHub |
| R10 | Backup row with missing real record, diagnostic messages, report, Light settings and text-field Tab focus inspected | Keyboard focus for all custom buttons, VoiceOver, 940×700 acceptance, long/disconnected catalog records, contrast measurement and oldest OS |
| R11 | No raw logs or private game contents placed in the review bundle; selected evidence redacted | Exhaustive redaction/provenance review and potential URL history exposure remain manual acceptance |
| R12 | Manual update/download, local unencrypted backup, manual retention and draft issue boundaries reviewed | Owner acceptance of those product limits and notification configuration |

## Commands and observations

- Baseline `swift test -Xswiftc -warnings-as-errors`: 30 executed, 4 skipped, zero failures.
- Final core/test changes: 34 executed, 6 opt-in tests skipped, zero failures (28 passed).
- Additional targeted runs: production read-only Framework inspection passed; clean QA Framework inspection passed; QA registry registration passed; scoped Wine shutdown passed in 3.83 seconds.
- Python checker: 4 passed. `actionlint` and `git diff --check`: passed.
- Release build with warnings as errors, ad-hoc signature and bundled resource self-check: passed. Not notarized.
- Internal startup disk: about 17 GiB available. Checkout/retained prefixes are on the external SSD with about 1.2 TiB free. No new full installation or licence acceptance was performed.
- UI automation: catalog missing-record case and final Mono wording observed; report opened and cancelled; theme changed to Light for inspection and restored to System. In the current keyboard navigation mode, Tab reached the note field and did not establish custom-button focus coverage.

The latest archive manifest and `evidence/app-artifact.json` identify the review source snapshot and local app ZIP. Historical and follow-up evidence are separate; earlier full-install results do not certify the changed first-run path.


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

Bundled UI verification passed for the default settings scope, old missing full-backup record, Locate/cancel and Remove/cancel. The existing catalog entry was preserved. Final page layout was inspected; this does not establish exhaustive keyboard/VoiceOver acceptance. Final release build, extracted signature/self-check, Python tests (4), actionlint and whitespace checks passed. See evidence/settings-backup.json.


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


## 2026-10-04: expanded validation and critical memory-pressure incident (R13)

Normal suite after adding the disposable managed runtime test: 56 total, 7 opt-in skips, 49 passed, 0 failures. Additional explicit QA tests passed: pinned-component extraction/new Wine prefix/Windows command (66.400 s on the external SSD); exact x86/x64 installer WPF probes; launcher registry registration; selected-prefix process shutdown with production identities unchanged; production read-only Mono classification. The targeted Framework/Launcher/Process run executed 7 tests without skips/failures. Fresh .NET installation/full clean installer pipeline and visible launcher/login/gameplay were not rerun or certified.

Bundled UI: verified the actual settings archive, exported redacted diagnostics locally, opened and cancelled the issue draft, restored the actual settings package into a separate external QA folder, and reviewed 1,120 import candidates without applying anything. Clear selection disabled Apply; search filtered the list. Light appearance was inspected and restored to System. GitHub returned rate limiting; the UI correctly exposed that condition, but a live successful update response was not verified. Escape cancellation passed. Command page shortcuts were not reliably observed; complete keyboard/VoiceOver acceptance remains open. Bulk import labels now explicitly say All files / Clear all / New files only; preview/comparison success and failure messages no longer retain an in-progress status after completion.

A real full backup of the retained QA wrapper completed and verified (6,972,423,983 compressed bytes), and restored to a separate external QA directory. The subsequent standalone file-by-file comparison was interrupted by a system restart: it MUST NOT be recorded as passed. The backup source was a disposable .qa wrapper, not production. Backup packages and actual restore output were on SSD 990 PRO. Some earlier small fixture tests and the first integration bootstrap used macOS's internal temporary directory; all test fixture roots now honor OUTLANDS_TEST_ROOT and otherwise default to .qa/unit-tests in the checkout. Local QA commands must use the external root explicitly. User directive: never save backups on the internal disk.

**Critical incident, R13 OPEN:** JetsamEvent at 11:44:30 names outlands-full-qa-validation (PID 12071) as the largest process, with 11,484,463,104 accounted bytes. Pre-restart observation: approximately 208 MiB free on the startup volume and 15,616 MiB swap fully occupied. The 11:50:49 panic reports WindowServer watchdog check-in timeout (120 s), compressor segment exhaustion and low swap space. This strongly implicates the implementing agent's unbounded standalone comparison workload in the incident; it is not proof that a user GUI backup alone triggers the same failure. After restart the helper was absent, startup free space was about 36 GiB and swap was empty. No other user's process was signaled.

Foundation streaming hash/copy loops now drain an autorelease pool per chunk to avoid retaining temporary NSData across long synchronous workloads. This is a defensive correction to a suspected mechanism, not a confirmed large-load resolution. Small fixture checks pass; the large comparison was not restarted. No stable-release sign-off. Future large verification requires a disposable machine, bounded memory/CPU, runtime memory and startup-disk monitoring, and abort thresholds; never repeat the unbounded helper on the owner's Mac. Raw crash/system reports and private QA data are excluded from the review archive.


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

First hosted CI run (37198965419): macOS 26/latest passed the full pipeline; macOS 14/15 failed because copied and re-signed Apple /bin/sleep fixtures exited before ownership assertions. Process fixtures now compile a plain C sleeper, reset inherited termination disposition/mask, and assert liveness. Local targeted checks passed; all original ownership assertions remain. Hosted rerun is required before merging.

Second hosted CI run (37199233621): macOS 14 normal Swift/Python suites passed, then standalone memory-probe compilation failed without exposing its diagnostic. The driver now searches both older SwiftPM module layout (debug/) and newer layout (debug/Modules), preserves failed compiler output in disposable QA, and prints only bounded compiler diagnostics on hosted CI. The local bounded regression still passed (4,325,856-byte peak); hosted rerun determines compatibility.

Third hosted CI run (37199354083) exposed the remaining macOS 14 helper-build error: swiftc defaulted to deployment target 14.0 while OutlandsCore requires 14.6. The standalone probe now explicitly targets native architecture/macOS 14.6, matching Package.swift. Normal suites passed on macOS 14; rerun is required for the complete pipeline.

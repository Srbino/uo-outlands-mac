# Handoff for the next coding agent

Status on 2026-10-03: release candidate **0.9.0 beta**, not releasable. This was originally uncommitted local work (parent `37cffc2`); the beta was subsequently merged through PR #1 on 2026-10-04. Read `docs/REVIEW.md` first, then this file.

## Hard rules

- **Commits:** never add `Co-Authored-By`, "Generated with …" or any AI/assistant attribution. The owner is the sole author. Do not commit, push, tag or publish unless the owner asks.
- **Real game is off limits:** `~/Applications/Sikarugir/outlands.app` is the owner's production installation. Only read from it. Do not rebuild, activate, restore over, or close processes of it. Never kill Wine processes globally.
- Test destructive flows only in a disposable prefix (`OUTLANDS_TEST_ROOT`, `OUTLANDS_KEEP_TEST_INSTALL=1`) or a disposable macOS account.
- Do not install Rosetta, accept licences, file GitHub issues or upload logs on the owner's behalf.
- Copy in the app stays English. Keep game artwork limited to the app emblem and the four sidebar icons.

## Verify the baseline first

```console
OUTLANDS_TEST_ROOT="$PWD/.qa/unit-tests" swift test --jobs 2 -Xswiftc -warnings-as-errors  # 57 tests, 7 skipped, 0 failures
python3 -m unittest discover -s tools -p 'test_*.py'
python3 tools/build.py
"dist/Outlands Installer.app/Contents/MacOS/OutlandsInstaller" --self-check
```

## What changed in the last session (UI redesign)

- `Sources/OutlandsInstaller/Style.swift` (new): adaptive `Palette` (Light/Dark), `ActionButtonStyle` (primary teal / secondary / warning amber / danger red), `LinkButtonStyle`, `TileButtonStyle`, `Card`, `Notice`, `Badge`, `PageHeader`, `ActionRow`.
- `Sources/OutlandsInstaller/App.swift`: rewritten views. Game page has three states: first-run requirements checklist, installing step list, installed overview. Backups use a `Grid` table with availability badges. Diagnostics separate failing checks from passing ones. Settings gained System/Light/Dark (`@AppStorage("appearance")`, applied through `NSApp.appearance`). One bottom status bar replaced the per-page message. Failure card has Dismiss.
- `Model.swift`: `MacRequirements` + `refreshRequirements()` (chip, macOS, free space, async Rosetta probe), `lastCheck`, `lastBackup`, `backupStatus` + `refreshBackupStatus()` (runs detached so a disconnected volume does not block the UI).
- Version `0.9.0` + `AppInfo.channel = "beta"` (`Support.swift`). The release workflow needs a numeric `vX.Y.Z` tag that matches `version`.
- Icons: only castle, locked-chest, spyglass, cog, sword-in-stone (emblem source) and AppEmblem remain. `GameGlyph` has 4 cases. `tools/import_game_icons.py` now keeps `viewBox` camel-cased (it used to emit invalid `view-box`).
- Docs updated: `REVIEW.md`, `TESTING.md`, `review/UI_UX.md`, `docs/installer.png`. The review ZIP was regenerated (`python3 tools/prepare_review.py`).

## Work remaining, in priority order

### 1. Launcher start-up failure (R01, release blocker)

Official `Outlands.exe` exits 255 in a clean, retained test prefix. Follow `docs/review/LAUNCHER.md`. Reproduce in isolation, capture exit status and full Wine output with a bounded timeout, and compare a clean environment with the inherited host environment. Acceptance: a launcher window opens, the game downloads, and login, Razor, graphics and audio work after a relaunch. Add a regression check where feasible.

### 2. .NET diagnostic fails on the owner's real install (new, related to R01/R08)

Read-only observation: in the production prefix both `drive_c/windows/Microsoft.NET/Framework{,64}/v4.0.30319/mscorlib.dll` are 752,128 bytes with an `MZ` header. `Wrapper.checks` (`Sources/OutlandsCore/Installer.swift`) requires > 2,000,000 bytes, so Diagnostics shows 5 of 7 passed. Determine whether this is a Wine-Mono stub or a valid older runtime. If the game runs in that prefix, the check is a false negative for legacy installs; activation of restored legacy backups (R08) uses the same checks. Compare with a fresh `FullInstallTests` prefix. Fix the check or its wording; do not modify the real prefix.

### 3. UI verification still missing

- Backup table with real records: run the bundled `dist/Outlands Installer.app`. The debug binary uses a different defaults domain, so its catalog is empty. Check long notes, disconnected disk, and the minimum window size (940×700).
- Keyboard: custom `ButtonStyle`s may not draw a focus ring with Full Keyboard Access. Verify Tab order and visible focus on every page and in the report sheet; add a focus indicator if missing.
- VoiceOver: sidebar selection, requirement rows, step list, badges, status bar.
- Light appearance contrast and Increase Contrast; the oldest supported macOS (14.6).
- Real install run (disposable account): step list, Stop, failure and retry, Rosetta-missing path.
- Screens were checked from the running app via an in-app snapshot (the terminal had no screen-recording permission). Keep such helper code out of commits.

### 4. Release evidence (R02, R03, R09)

Hosted CI matrix for the exact revision, Developer ID signing, notarization, Gatekeeper on a clean Mac, and hardware cases (no Rosetta, external disk unplugged during backup, low disk space, reboot during install). The owner must configure credentials; do not create or store secrets.

### 5. Independent review items (R04–R07, R10–R12)

Use `docs/review/PROMPT.md` and record results in `docs/review/FINDINGS.md`: archive and symlink hardening, metadata fingerprint limits, process ownership races, remaining synchronous filesystem calls on the main thread (`openFolder`, `FileManager.fileExists(staging)` in view bodies, report preparation), privacy redaction, and whether README promises match the evidence.

## Definition of done for each change

Build with `-warnings-as-errors`, all tests green, `--self-check` passes, docs that describe the behaviour updated, and `python3 tools/prepare_review.py` rerun if the review package is to be shared. Report what was verified and what was not. Never turn an unchecked acceptance item into a pass from code reading alone.

## Follow-up status after baseline verification

Read [FINDINGS.md](FINDINGS.md) and the appended [LAUNCHER.md](LAUNCHER.md) investigation before repeating work. Exit 255 was reproduced in inherited/minimal environments. Staging `InstallDir` registration now prevents immediate exit and allowed about 6.8 GB of game downloads, but launcher GUI/login/gameplay remain unverified and R01 stays open. The retained prefix is no longer a pre-download baseline.

The 752 KB DLLs exactly match Wine Mono reference assemblies. Diagnostics now identifies Mono explicitly, and legacy activation no longer demands the new Framework recipe. Both real read-only and clean QA inspections passed. Report preparation uses the last diagnostic snapshot. A missing catalog archive no longer appears verified in the sidebar; relative wording is forced to English.

The startup disk is low, but this checkout and retained test prefixes are on an external SSD with about 1.2 TiB free. Use explicit disposable external paths; do not assume the default temporary/home volume has room. No new full installation was run. All original hard rules still apply.


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

## GitHub beta integration completed — 2026-10-04

PR #1 merged as a8a7a70 after the normal macOS 14/15/26/latest matrix passed for b783667. See evidence/hosted-ci.json and the current ACCEPTANCE.md. Earlier unverified-CI statements describe dated local observations. Full-install/release workflows, signing/notarization, visible game login, full accessibility and hardware interruption acceptance remain open. No stable release/tag was created.

# Current functional acceptance — 2026-10-04

This is local verification on one M4 Mac running macOS 26.5.1, not independent approval or a claim of 100% correctness. All mutation/recovery/process-shutdown tests used disposable fixtures or QA wrappers. Production game files were not changed and production processes were not stopped. Earlier local verification performed no commit, push or publication. The owner subsequently authorized beta integration; stable publication, credentials setup, issue submission and licence acceptance remain outside this work.

| Function | Verdict | Evidence / boundary |
| --- | --- | --- |
| Settings backup selection | Passed | Both Razor layouts, profiles/scripts/macros/configuration; binary/game/Wine exclusions, redirected/custom profiles rejected |
| Actual settings backup | Passed | 15.6 MB archive; verified and restored separately; original game unchanged |
| Settings backup with idle Wine services | Passed | 47 services allowed, unknown/game/launcher writers blocked; actual preview and backup passed |
| Full backup guard | Passed | GUI refused the active production prefix before destination selection; no processes stopped |
| Full QA archive | Passed | 6,972,423,983-byte archive verified; full restoration passed under guard |
| Full restored file comparison | Passed | 15,315 SHA-256 matches, 262 link matches, source unchanged; peak 17.7 MB |
| Selective settings apply / Undo | Passed on fixtures | Selected changes, original preservation, source mutation, failed swap rollback, cancellation, interruption journals and redirected destinations tested; no production apply |
| Import review GUI | Passed within tested scope | Actual archive restored into QA; 1,120 candidates, search, clear-selection/disabled Apply, cancellation; bulk labels explain selection includes hidden files |
| Full recovered-app activation | Passed on fixtures | Keeps current installation; rejects incomplete/redirected structure; production activation not performed |
| Malicious/corrupt archive rejection | Passed on fixtures | Traversal, link chains, duplicate/case paths, special files, understated size, truncation, payload symlinks, private-copy race and cancellation |
| Catalog availability / missing entry | Passed within tested scope | Actual available + missing entries; metadata remembers locations; locate/remove cancellation tested; actual unplugged-disk hardware not tested |
| Backup layout | Passed at tested sizes | 940/960/1263-point windows; compact records and wide table; Light/System inspection |
| Diagnostics / .NET identification | Passed | Production read-only Wine Mono information; Microsoft candidate requires CLR and architecture-specific registry; does not certify gameplay |
| Executable .NET/WPF gate | Passed in retained QA | Exact x86/x64 managed probes executed; production runtime was not executed |
| Process shutdown scope | Passed in retained QA | Target wrapper shut down; production kernel identities unchanged; missing/unreadable Wine prefix now blocks shutdown; unknown-prefix fixture remains alive; adversarial PID races/external engines remain a review boundary |
| Launcher install-directory registration | Passed in retained QA | Real Wine registry query matched expected InstallDir |
| New-prefix Wine smoke | Passed | Pinned cached components reverified/extracted into isolated prefix; Windows command executed |
| Fresh complete installation / first-run launcher | NOT VERIFIED on final revision | Historical pipeline passes do not certify changed GUI/launcher; no new licence acceptance or complete game/login acceptance |
| Problem report draft | Passed within tested scope | Most recent diagnostic snapshot shown; Escape cancelled; redaction/URL tests; no issue transmitted |
| Diagnostics export | Passed | Actual local redacted file saved into external QA; no upload |
| Update checks | Partial | Unit tests cover success/no release/error/rate limit/untrusted URLs; live GitHub response was rate-limited and correctly reported |
| Stop / timeout / locking | Passed on fixtures | Owned subprocess cancellation, bounded failure/timeout, concurrent writer lock, no stale locks |
| Memory regression | Passed under watchdog | >2 GB cumulative checksum reads, full verify/restore/compare; resource guard and cleanup tests; no universal memory guarantee |
| Packaged app | Passed locally | Warnings-as-errors build, extracted resource self-check, strict ad-hoc signature; desktop shortcut updated |
| Keyboard / VoiceOver | Partial / NOT VERIFIED | Escape passed; page shortcuts not reliably observed; full focus order and VoiceOver acceptance open |
| CI / release | Static checks and local guard passed | Hosted matrix has not run for this uncommitted snapshot; Developer ID, notarization and clean-machine Gatekeeper require owner credentials and execution |
| Other macOS / hardware interruptions | NOT VERIFIED | macOS 14.6, external unplug, reboot/power interruption, no-Rosetta and graphics/audio/login acceptance need dedicated hardware/account testing |

## Reproduce bounded memory checks

Run the small fixture suite with an explicit external QA root first:

```console
OUTLANDS_TEST_ROOT="$PWD/.qa/unit-tests" swift test --jobs 2 -Xswiftc -warnings-as-errors
python3 -m unittest discover -s tools -p 'test_*.py'
python3 tools/verify_backup_resources.py --qa-root "$PWD/.qa/bounded-memory"
```

Local resource checks refuse a QA root on the internal home volume. The guarded subprocess is stopped if the monitored footprint reaches 256 MiB, startup disk free space falls below 10 GiB, monitoring fails or the time bound expires. CI uses an explicitly disposable runner workspace. Never run `backup_memory_probe.swift` directly on large data; always use the supervisor. Raw system reports, private archives and QA output are excluded from the source-review ZIP.

Current automated counts: 57 Swift tests, 7 opt-in skips, 50 passed, 0 failures; 11 Python tests passed. Five opt-in runtime cases were separately executed successfully in the preceding validation run. Keep stable release blocked until the unverified installer/gameplay, accessibility and release acceptance items have evidence.

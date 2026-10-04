# Launcher investigation handoff

Status: unresolved stable-release blocker. This note records the earlier local investigation; no new launcher execution is part of preparing the review package.

## Observations

The full installer pipeline completed successfully on a clean retained isolated prefix in 551.4 seconds. The current official launcher then exited with code 255 when run directly with the bundled Wine engine, before a launcher window was observed. Trying a copy of the existing Wine 10 engine in that same investigation prefix also exited 255. The pinned Wine 11 engine was restored in the QA prefix; no downgrade was shipped or applied to the user's active game.

Earlier native Sikarugir launch attempts stalled; a sampled stack waited for Wine servers. The user's real installation had other Wine processes. These observations do not prove a global-process interaction is the cause, and they do not authorize terminating other Wine applications. A launch experiment against a separately restored copy also failed to establish a working visible launcher. Do not report any of these as startup acceptance.

The direct clean-prefix launcher log contained only:

```text
msync: bootstrapped mach port on wine-1fd52cb-msync.
msync: up and running.
```

Exit 255 was recorded by the calling Python process in the earlier interactive session; this short log does not independently establish that exit status or its cause. The archive does not contain the full session transcript, private prefixes or a crash dump. Independently reproduce and capture process exit, logs and launch path.

## Reproduce in isolation

Use an Apple Silicon test Mac or disposable account with Rosetta already installed and at least 20 GB free. Preserve successful full-install output:

```console
OUTLANDS_FULL_INSTALL_TESTS=1 OUTLANDS_KEEP_TEST_INSTALL=1 swift test --filter FullInstallTests
```

Use only the resulting printed test wrapper. First test its normal application launch path. If comparing direct Wine execution, the earlier probe used `Contents/SharedSupport/wine/bin/wine` with the full path to `Outlands.exe`, with working directory set to the game's directory inside the test prefix.

The probe set `WINEPREFIX` to that test wrapper's `Contents/SharedSupport/prefix`, `WINEDEBUG=-all`, `SikarugirAppWine11=1`, `CX_ROOT` to its embedded wine folder, `WINEESYNC=1` and `WINEMSYNC=1`. `DYLD_FALLBACK_LIBRARY_PATH` contained that engine's `lib`, the wrapper's `Contents/Frameworks`, its `GStreamer.framework/Libraries`, and `/usr/lib`. The probe inherited other host environment variables. Therefore a clean-environment comparison is still needed; the original result alone does not distinguish wrapper launch setup, runtime compatibility and host interference.

Record the official launcher hash and download date, selected engine/recipe, environment differences, process exit, whether a real window opens, and crash/runtime output. Never log credentials or the entire process environment. Use a bounded observation period; a still-running process is not proof of a usable launcher. Clean up only the disposable wrapper's own processes.

## Required resolution

Identify a repeatable supported launch path or fix, run it from a retained clean installation, complete the official download/verification, then test login, Razor, graphics, audio and reboot/relaunch. Explain why the fix works and add a regression check where feasible. Keep stable publication blocked until this evidence exists.

## Follow-up investigation on 2026-10-03

Baseline reproduced with bounded probes in the retained QA prefix: inherited environment exited 255 in 6.19 seconds; minimal environment exited 255 in 3.89 seconds. Wine logs and .NET host tracing were captured locally under `.qa/handoff/`. A temporary software-WPF rendering setting also exited 255 in 2.11 seconds and was removed. No rendering workaround was shipped.

The Wine trace showed a failed copy from `Outlands.exe` into a nonexistent nested `Ultima Online Outlands/Outlands.exe` directory. Inspection of the bundled `Patch.Client` metadata/IL established that the launcher looks for `HKLM\Software\Wow6432Node\Ultima Online Outlands\InstallDir`, then resolves its deployment directory. No launcher binary was modified or redistributed as part of the investigation.

Setting that value to `C:\Program Files (x86)\Ultima Online Outlands` in the QA prefix prevented the immediate exit. The launcher remained alive until explicitly bounded at 25 seconds, and again at 120 seconds. Subsequent read-only inspection found 563 game files totaling 6,768,650,772 bytes, including `ClassicUO/ClassicUO.exe`. The folder originally contained only the launcher. This demonstrates game download activity, not completeness or successful gameplay.

`Installer.registerLauncherDirectory` now registers the intended directory in staging after the launcher download and before verification/promotion. The regression test queries the value using Wine in a disposable `.qa` wrapper; it passed in 8.08 seconds. The full-install test also checks this value, but the complete pipeline was not rerun after this change. The production wrapper was read only.

**R01 remains open for acceptance.** The native wrapper launch attempt through the computer-use interface timed out, and the direct Wine process exposed no selectable application window through that interface. A working visible GUI has not been verified. Do not equate timeout with GUI success. Login, Razor, graphics, audio and relaunch remain unverified. The retained QA prefix now contains downloaded files, so it is no longer an untouched pre-download prefix; use a new isolated installation for a fresh first-run acceptance test.

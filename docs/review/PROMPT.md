# Independent reviewer brief

Review the complete current Outlands for Mac implementation as a skeptical reviewer. Read `docs/REVIEW.md` first. The source snapshot includes new files absent from the tracked diff; inspect them all. Do not assume the implementing assistant's descriptions are correct.

The product is a native SwiftUI installer and game manager for Apple Silicon Macs. It installs a Sikarugir Wine wrapper, manages full local backups and separate recovery, provides scoped process shutdown, diagnostics, updates and reviewed GitHub issue drafts. The desired interface is English, professional and simple. Teal game artwork belongs in app identity and navigation; routine action buttons should remain native and restrained.

The official launcher startup failure is a known stable-release blocker. A passing build or installation test does not override it. Review the app as a release candidate, not a finished stable product.

## Required review

1. Inspect correctness, cancellation, concurrent operations, retries, staged installation, disk checks, rollback and crash/reboot recovery. Trace actual code paths across the model, actors and subprocess runner.
2. Challenge archive verification/extraction, symlink and hardlink handling, source mutation, process ownership, permissions, public network trust, output limits and privacy redaction. Distinguish accidental corruption checks from authentication.
3. Evaluate the complete UI/UX using `UI_UX.md`: first use, existing installation, all four tabs, busy/error/empty states, keyboard, accessibility, small windows, long text, destructive confirmations and useful next steps. Review actual rendered screens, not only source or screenshots.
4. Inspect CI/release permissions, immutable revisions, matrix architectures, disk needs, artifact behaviour, signing secret isolation, draft publication, upstream PR dispatch and Dependabot. Static YAML validation is not remote execution proof.
5. Check source/documentation consistency, English copy, icon licences and provenance, migration from shell scripts and whether README promises exceed evidence.
6. Verify meaningful test coverage. Identify missing failure paths, tests that only mirror implementation, and opt-in tests skipped in the default green result.

Use a disposable macOS account for interactive operations that can affect a game. Do not modify the user's active wrapper, kill unrelated Wine processes, submit issues, push commits, publish releases, install Rosetta or accept licences without applicable authorization. The initial review should be read-only except for isolated tests and local review artifacts. Propose fixes; do not silently mix changes into the reviewed baseline.

## Required output

- Findings ordered by severity: critical data loss/security, high functional/release blocker, medium usability/reliability, low polish/documentation.
- For each: ID, category, exact source path and line, reproduction or evidence, expected/actual behaviour, user impact, proposed change, and a concrete verification step.
- Label a suspected risk as unproven when no reproduction exists. Report positive observations separately from findings.
- Report commands actually run, environment, result and skipped checks. Record archive manifest or reviewed commit.
- Give independent verdicts for data safety, UI/UX, CI/release and overall stable publication. State which evidence is still needed.
- Use `FINDINGS.md` as a template. If no new finding is identified, say so without claiming the application is bug-free.

# Releases and update maintenance

## Local build

`python3 tools/build.py` creates an arm64 app and ZIP under `dist/`, runs an app-resource self-check, verifies its ad-hoc signature and writes `SHA256SUMS` plus `build-info.json`. End users do not need Python or Swift.

Ad-hoc signing supports development; it is not Developer ID signing or notarization. Do not describe CI artifacts as notarized releases or tell users to disable Gatekeeper.

## Signed release

Before the first public release, create a protected GitHub environment named **release** with a required maintainer reviewer and the following environment secrets:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 of a Developer ID Application signing certificate and private key exported as P12 |
| `APPLE_CERTIFICATE_PASSWORD` | P12 export password |
| `APPLE_SIGNING_IDENTITY` | Exact Developer ID Application identity |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_APP_PASSWORD` | App-specific password for that account |
| `APPLE_TEAM_ID` | Apple Developer team ID |

Do not put these values in source, issues or logs. The CI helper imports the certificate into a temporary keychain, builds with the hardened runtime, submits to Apple, staples and validates the ticket, and deletes its keychain afterward. Missing credentials fail the workflow; it never silently publishes an unsigned replacement.

1. Finish the hardware checks in [TESTING.md](TESTING.md) and record the actual results.
2. Update `AppInfo.version` in `Sources/OutlandsCore/Support.swift` and `docs/RELEASE_NOTES.md`.
3. Push a matching stable tag such as `v1.0.0`.
4. The tag starts **Signed release candidate** automatically. Approve the protected environment. Manual dispatch for an existing tag is also available.
5. Review the draft release, test its downloaded ZIP on a clean Mac, then publish it manually.

The workflow creates a **draft**. It does not publish automatically. `SHA256SUMS` is generated from the final stapled ZIP. Apple's notarization of the installer does not certify the third-party Wine wrapper it downloads later.

For a local Developer ID build with an existing notarytool credential profile:

```console
python3 tools/build.py --identity "Developer ID Application: Your Name (TEAMID)" --notary-profile outlands-release
```

## Updating runtime components

`Sources/OutlandsCore/recipe.json` is bundled into the app and records source URLs, sizes and hashes. It is never replaced with arbitrary remote code at runtime. The current engine uses the `SikarugirAppWine11` launch flag: a future engine family needs a compatibility review, not just a changed filename.

```console
python3 tools/check_upstream.py
python3 tools/check_upstream.py --write
```

The checker reads official release JSON, sorts version numbers numerically, ignores prerelease/draft releases and unrelated engine families, and pins the `sikarugir` Winetricks branch to an exact commit. SHA-256 release digests are required for binary components; the Winetricks source archive is hashed directly. Metadata verification dates are not gameplay certification dates.

The daily workflow opens or refreshes `automation/upstream-components`. Enable **Allow GitHub Actions to create and approve pull requests** in repository Actions settings if needed; the workflow requests write permissions only for its update job. It assigns the PR to the repository owner, producing a GitHub notification according to their notification settings. An identical pending recipe is not pushed again each day. It does not auto-merge. A same-name asset whose digest changed needs special review.

The workflow explicitly dispatches the build matrix and runtime smoke tests on the candidate branch. GitHub currently puts token-created PR workflow events into an approval-required state; explicit `workflow_dispatch` is supported with `GITHUB_TOKEN` ([GitHub documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)). The workflow therefore needs `actions: write` as well as contents/PR permissions. Review the branch-specific Actions results and complete hardware acceptance before merging. Ship an approved recipe through a new installer version; existing installed wrappers are not silently upgraded.

Dependabot maintains the SHA-pinned Actions dependencies separately. There are currently no external Swift package dependencies.

## Installer update checks

The app requests the public `/releases/latest` endpoint over HTTPS. It accepts stable numeric `vMAJOR.MINOR.PATCH` tags pointing back to this repository. It handles missing releases and rate limiting, and offers the release page when a newer version exists. The user downloads the replacement; no updater daemon or unreviewed in-place binary replacement is installed.

The current `macos-14` runner is scheduled for retirement on 2026-11-02; replace that CI job with a maintained runner before that date. Deployment support for macOS 14.6 is a separate decision. See the [official runner image notice](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).

## Mandatory release gates

The release workflow resolves a real version tag to an immutable commit. Both reusable workflows check out that commit, and signing waits for the complete build matrix, Wine smoke matrix and full isolated installation job. A failure blocks the draft release. The full installation requires at least 20 GB **free**, checked before starting. If the standard runner is insufficient, set repository variable `OUTLANDS_FULL_INSTALL_RUNNER` to a label for a disposable arm64 macOS runner with adequate storage. Do not point it at a personal Mac: it installs Rosetta and runs downloaded components. Missing capacity fails explicitly; the test is not skipped or treated as success.

The independent weekly runtime workflow keeps its full-install option off by default. Full runtime tests still do not certify the official launcher GUI or gameplay; the known startup blocker must be resolved before publishing the draft as stable.

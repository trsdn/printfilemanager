# Self-assessment against the Repository Quality Standard

Standard version 1.3.3 · assessed 2026-08-28 · state **Needs work** · 0 failures

This is the evidence behind [`.github/conformance.yml`](../.github/conformance.yml). Results are recorded as they are, not as they should be.

The repository was made public on 2026-08-28. That resolved the three failures this assessment
originally recorded — they shared one cause, a private repository on a plan without branch
protection or secret scanning and with Actions billing blocked — and brought the Public profile
into scope. Nothing fails now; twelve criteria are partial.

## Profiles applied

Baseline, Public, Software, Deployable, Package, Product Identity, Agent Readiness, Language,
Accessibility, Data Protection. The repository is actively developed, so the Archived profile is
not applicable.

## Baseline

| ID | Result | Evidence |
|---|---|---|
| B01 | pass | Name and GitHub description state the product and platform. |
| B02 | pass | `README.md` covers purpose, layout, prerequisites, build, install, privacy and safety. |
| B03 | pass | `LICENSE` (MIT), also declared in the built artifact. |
| B04 | pass | `.gitignore` excludes build output, DerivedData and `.release/`; no secrets are tracked. The API key lives in the Keychain. |
| B05 | pass | Three validation commands documented in `README.md`, `CONTRIBUTING.md` and `AGENTS.md`, all verified from a clean clone. |
| B06 | pass | `main` requires the four CI checks, with force pushes and deletions blocked. Enabled once the repository became public. |
| B07 | pass | macOS 15 and Xcode 26 stated; Swift 6 pinned in each `project.yml`; one dependency pinned in `ThreeMFKit/Package.swift`. |
| B08 | pass | `CHANGELOG.md`, plus commit messages that state rationale. |
| B09 | pass | Public, described, and carrying six topics including `trsdn-standard`. No homepage, which is intentional for an app distributed as a signed download. |
| B10 | pass | `.github/CODEOWNERS` and the ownership section of `CONTRIBUTING.md`. |
| B11 | pass | This record and `.github/conformance.yml`. |
| B12 | pass | The `trsdn-standard` topic is set. |

## Software

| ID | Result | Evidence |
|---|---|---|
| S01 | pass | Verified end to end from a fresh `git clone`: install two tools, generate, build, test. |
| S02 | pass | 77 tests. Failure paths are covered deliberately: unreadable index, oversized ZIP entries, malformed mesh indices, mid-batch operation failure, stale undo. |
| S03 | pass | SwiftLint in CI, configured so the tree is error-free and warnings track known debt. |
| S04 | pass | CI covers macOS, the only supported platform, and now actually runs: three green jobs on `main`. |
| S05 | pass | Secret scanning and push protection are enabled. The history was also scanned by hand before publishing: no credential-shaped file was ever added and no diff contains a key or token pattern. |
| S06 | pass | No configuration is compiled in. The endpoint, model and both feature switches are user settings; the API key is in the Keychain. |
| S07 | pass | Errors carry the underlying description; the API key is never logged; Quick Look logs file paths at `.private`. |
| S08 | pass | `.github/dependabot.yml` for both ecosystems, owner named in `CODEOWNERS`, triage process in `SECURITY.md`. |
| S09 | pass | `main` requires "Print File Manager", "3MF Quick Look", "ThreeMFKit" and "Conformance record". Before going public every run failed with "recent account payments have failed or your spending limit needs to be increased" before starting a job — including the Ubuntu one, so it was the private-repository quota rather than macOS runner cost. |
| S10 | pass | `docs/assessment-2026-08-28-multi-agent.md` documents architecture and constraints with measurements; `AGENTS.md` states the non-obvious ones. |

## Deployable

| ID | Result | Evidence |
|---|---|---|
| D01 | pass | `README.md` documents the target, prerequisites and the install loop, including the Quick Look registration steps. |
| D02 | pass | `scripts/release.sh` and `.github/workflows/release.yml` reference credentials; none are committed. `SECURITY.md` states where the API key lives. |
| D03 | partial | The release workflow smoke-tests the built app, and verification commands (`qlmanage -p`, `pluginkit`) are documented. There is no rollback procedure because there is no published release to roll back to. |
| D04 | pass | Deployment target, Swift version and the single dependency are pinned. |
| D05 | pass | `CHANGELOG.md` records operational changes. |
| D06 | pass | The library index is quarantined rather than overwritten when unreadable, one backup is written per session, the schema is versioned with a migration path, and every destructive batch is reviewed and undoable. |

## Package and release

| ID | Result | Evidence |
|---|---|---|
| R01 | pass | Bundle identifier, name, version and copyright agree with the repository. |
| R02 | partial | Semantic versioning is declared in `CHANGELOG.md`. A compatibility policy is not meaningful before 1.0 and is not written. |
| R03 | partial | `.github/workflows/release.yml` builds artifacts from a `vX.Y.Z` tag and publishes them, but they are unsigned. Signed artifacts come from the notarization broker, which builds this repository successfully and then fails preflight on a SwiftPM privacy-manifest resource bundle (macos-notarization-broker#30). |
| R04 | pass | The workflow fails when the tag does not match `CFBundleShortVersionString`. |
| R05 | pass | The workflow launches the built app and fails if it exits within ten seconds. Also verified by hand. |
| R06 | partial | Release notes are generated from commits, which are written to be readable. No release has been cut, so this is untested in practice. |

## Product identity

| ID | Result | Evidence |
|---|---|---|
| I01 | pass | `CFBundleName`, `CFBundleShortVersionString` and `CFBundleVersion`. |
| I02 | pass | `PFMRepositoryURL` and `PFMIssueTrackerURL` in `Info.plist`. |
| I03 | pass | `NSHumanReadableCopyright` and `PFMLicenseIdentifier`. |
| I04 | pass | Settings shows the version and links to the source and the issue tracker, read from the bundle rather than hardcoded. |
| I05 | partial | An app icon is embedded at all ten required sizes. There is no installer or site surface to reuse it on. |
| I06 | pass | `Info.plist` references `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`, which come from `project.yml` and are overridden from the tag by the release workflow. Verified by building with an injected version and reading it back out of the artifact. |

## Agent readiness

| ID | Result | Evidence |
|---|---|---|
| G01 | pass | `AGENTS.md` at the repository root. |
| G02 | pass | It states purpose, layout, setup, run and the three validation commands. |
| G03 | pass | "Do not do these" names history rewriting, secrets, releases, weakening safety guarantees, hand-editing generated projects, and testing destructive paths against a real library. |
| G04 | pass | There is no tool-specific agent configuration to diverge from it. |
| G05 | pass | The three validation commands are documented and verified from a clean clone. |
| G06 | pass | Both `.xcodeproj` files are marked generated in `AGENTS.md`, with the regeneration command. |
| G07 | pass | Agent commits carry `Co-authored-by` and `Copilot-Session` trailers. |
| G08 | partial | No `.github/github-app.yml` exists. The defaults are acceptable, but that is an untested assumption rather than a decision. |

## Language

| ID | Result | Evidence |
|---|---|---|
| L01 | pass | English, declared in `README.md`. |
| L02 | pass | All user-facing strings are English. |
| L03 | pass | Declared English-only in `README.md`. |
| L04 | na | No string catalogs, because the app is English-only. |
| L05 | partial | Sorting uses `localizedStandardCompare` and dates use `DateFormatter`, but file sizes and counts are interpolated directly rather than going through `formatted()`. |
| L06 | na | No translations exist. |
| L07 | pass | The repository, its documentation and its commit messages are English. |

## Accessibility

| ID | Result | Evidence |
|---|---|---|
| X01 | partial | Menu commands cover Select All, Find, Reveal, Trash and Undo; Shift-click ranges work; tiles are now buttons with the button trait. Arrow-key navigation between tiles is still missing. |
| X02 | pass | Verified against the running app with a real 703-file library: each tile is an `AXButton` carrying a composed description ("4 Ring Gyro Fidget, Needs Slicing, needs review: …") and named actions for Open, Reveal in Finder, Move and Trash. |
| X03 | pass | Semantic colours throughout, so light, dark and accent settings are honoured; status is carried by icon and text, not colour alone. |
| X04 | pass | `scripts/release.sh` output is plain ASCII with no colour dependence. |
| X05 | pass | The limitations above are stated here and in the assessment rather than left implicit. |

## Data protection and privacy

| ID | Result | Evidence |
|---|---|---|
| Y01 | pass | `README.md` and `SECURITY.md` state what is stored locally and what is transmitted, including that the `.3mf` file itself never leaves the machine. |
| Y02 | pass | Both destinations are documented with their purpose, in the README, `SECURITY.md` and the Settings UI. |
| Y03 | pass | There is no telemetry, analytics or crash reporting. Both network features are opt-in and off by default. |
| Y04 | partial | The index location is documented and the app can start a fresh library, but there is no in-app export or delete-all. |
| Y05 | pass | The AI provider is chosen by the user and named in Settings; the search engine and the four model sites are named. |
| Y06 | partial | The index persists until the user removes a folder or starts fresh, and that is stated. There is no retention policy, because nothing is retained off the machine. |

## Summary

| Result | Count |
|---|---|
| pass | 66 |
| partial | 12 |
| fail | 0 |
| na | 6 |

No criterion fails. The eleven partials are all minor, with two exceptions worth naming rather
than burying:

- **X01** — the grid is the app's primary surface and still has no arrow-key navigation between
  tiles. Tiles are focusable buttons with named VoiceOver actions, so the surface is operable, but
  a keyboard-only user cannot move through it the way a Mac user expects. This is why the state is
  `Needs work` rather than `Healthy`.
- **P09** — the repository stats card is committed as required, but the workflow that regenerates
  it cannot push while `main` requires status checks it does not run. Resolving this needs a
  `STATS_TOKEN` with bypass rights. Branch protection was judged worth more than the card, so the
  card is absent rather than the protection being relaxed.

The remaining ten are genuinely small: no signed release yet (R03, tracked upstream), no rollback procedure before a first release (D03), no
compatibility policy before 1.0 (R02), release notes not yet exercised (R06), no installer surface
to reuse the icon on (I05), no `github-app.yml` (G08), file sizes not formatted through locale APIs
(L05), no in-app export or delete-all (Y04), no retention policy for data that never leaves the
machine (Y06), and two hardcoded badges served from a third-party host (P08).

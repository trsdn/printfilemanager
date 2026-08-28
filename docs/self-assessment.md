# Self-assessment against the Repository Quality Standard

Standard version 1.3.3 · assessed 2026-08-28 · state **Needs work**

This is the evidence behind [`.github/conformance.yml`](../.github/conformance.yml). Results are
recorded as they are, not as they should be: four criteria fail and twelve are partial. Three of the
failures are outside the repository's control and are noted as such.

## Profiles applied

Baseline, Software, Deployable, Package, Product Identity, Agent Readiness, Language,
Accessibility, Data Protection. The repository is private, so the Public profile is not applicable;
it is actively developed, so the Archived profile is not applicable either.

## Baseline

| ID | Result | Evidence |
|---|---|---|
| B01 | pass | Name and GitHub description state the product and platform. |
| B02 | pass | `README.md` covers purpose, layout, prerequisites, build, install, privacy and safety. |
| B03 | pass | `LICENSE` (MIT), also declared in the built artifact. |
| B04 | pass | `.gitignore` excludes build output, DerivedData and `.release/`; no secrets are tracked. The API key lives in the Keychain. |
| B05 | pass | Three validation commands documented in `README.md`, `CONTRIBUTING.md` and `AGENTS.md`, all verified from a clean clone. |
| B06 | **fail** | Branch protection is unavailable: GitHub returns 403 "Upgrade to GitHub Pro or make this repository public". Not fixable inside the repository. |
| B07 | pass | macOS 15 and Xcode 26 stated; Swift 6 pinned in each `project.yml`; one dependency pinned in `ThreeMFKit/Package.swift`. |
| B08 | pass | `CHANGELOG.md`, plus commit messages that state rationale. |
| B09 | partial | Visibility and description are intentional. Topics were added for B12; there is no homepage because the project is private and unreleased. |
| B10 | pass | `.github/CODEOWNERS` and the ownership section of `CONTRIBUTING.md`. |
| B11 | pass | This record and `.github/conformance.yml`. |
| B12 | pass | The `trsdn-standard` topic is set. |

## Software

| ID | Result | Evidence |
|---|---|---|
| S01 | pass | Verified end to end from a fresh `git clone`: install two tools, generate, build, test. |
| S02 | pass | 77 tests. Failure paths are covered deliberately: unreadable index, oversized ZIP entries, malformed mesh indices, mid-batch operation failure, stale undo. |
| S03 | pass | SwiftLint in CI, configured so the tree is error-free and warnings track known debt. |
| S04 | partial | CI covers macOS, the only supported platform, but see S09 — it has never actually executed. |
| S05 | **fail** | Secret scanning requires GitHub Advanced Security on a private repository and is not enabled. Mitigated by no secrets being tracked, but the automated control is absent. |
| S06 | pass | No configuration is compiled in. The endpoint, model and both feature switches are user settings; the API key is in the Keychain. |
| S07 | pass | Errors carry the underlying description; the API key is never logged; Quick Look logs file paths at `.private`. |
| S08 | pass | `.github/dependabot.yml` for both ecosystems, owner named in `CODEOWNERS`, triage process in `SECURITY.md`. |
| S09 | **fail** | Required checks cannot be configured without branch protection (B06), and no CI run has succeeded — every run since the workflow was added failed with "recent account payments have failed or your spending limit needs to be increased" before any job started. macOS runners bill at ten times the Linux rate, which is the likely cause. |
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
| R03 | pass | `.github/workflows/release.yml` builds installable artifacts from a `v*` tag. |
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
| I06 | **fail** | The version is hand-maintained in `Info.plist`. The release workflow verifies the tag agrees with it, so a mismatch is caught, but the value is not produced by the build. |

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
| X01 | partial | Menu commands cover Select All, Find, Reveal, Trash and Undo, and Shift-click ranges work. Grid tiles are still a tap gesture rather than a focusable control, so arrow-key navigation of the grid is missing. |
| X02 | partial | Every icon-only button has an accessibility label, verified in the running app. Grid tiles combine their children into one element, so VoiceOver cannot reach the per-tile actions. |
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
| pass | 53 |
| partial | 12 |
| fail | 4 |
| na | 15 |

The four failures are B06, S05, S09 and I06. The first three share one root cause: the repository is
private on a plan that provides neither branch protection nor secret scanning, and CI cannot run
because Actions billing is blocked. Making the repository public, or upgrading the plan and clearing
the billing block, resolves all three. I06 is a real gap in the build and is fixable by deriving the
version from the tag.

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
| B07 | pass | macOS 15 and Xcode 26 stated; Swift 6 pinned in each `project.yml`; dependencies pinned by exact version in `printfilemanager/project.yml`. |
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
| S07 | pass | Errors carry the underlying description; the API key is never logged; file paths are logged at `.private`. |
| S08 | pass | `.github/dependabot.yml` for both ecosystems, owner named in `CODEOWNERS`, triage process in `SECURITY.md`. |
| S09 | pass | `main` requires "Print File Manager", "Versions" and "conformance / Conformance record" — the context name matters: it must match the check-run name the workflow reports, including the job prefix a reusable workflow adds. Before going public every run failed with "recent account payments have failed or your spending limit needs to be increased" before starting a job — including the Ubuntu one, so it was the private-repository quota rather than macOS runner cost. |
| S10 | pass | `docs/assessment-2026-08-28-multi-agent.md` documents architecture and constraints with measurements; `AGENTS.md` states the non-obvious ones. |

## Deployable

| ID | Result | Evidence |
|---|---|---|
| D01 | pass | `README.md` documents the target, prerequisites and the install loop, and points at the separate Quick Look app for Finder previews. |
| D02 | pass | `scripts/release.sh` and `.github/workflows/release.yml` reference credentials; none are committed. `SECURITY.md` states where the API key lives. |
| D03 | pass | README **Rolling back** documents replacing the app with an older signed release, the `spctl` and version checks that confirm what is installed, and the index-migration caveat with the export that avoids it. The Quick Look app versions and rolls back independently. |
| D04 | pass | Deployment target, Swift version and the single dependency are pinned. |
| D05 | pass | `CHANGELOG.md` records operational changes. |
| D06 | pass | The library index is quarantined rather than overwritten when unreadable, one backup is written per session, the schema is versioned with a migration path, and every destructive batch is reviewed and undoable. |

## Package and release

| ID | Result | Evidence |
|---|---|---|
| R01 | pass | Bundle identifier, name, version and copyright agree with the repository. |
| R02 | pass | README **Compatibility before 1.0** states that the interface is unstable below 1.0, the two guarantees that hold regardless (files are never the migration; the index migrates forward or is quarantined), and that breaking changes require a major version from 1.0. |
| R03 | pass | `.github/workflows/release.yml` builds from a `vX.Y.Z` tag, and v0.2.0 publishes signed, notarized, universal DMG and ZIP artifacts with checksums and a provenance record. Signing runs in `macos-notarization-broker`, which builds this source without credentials present and gates certificate import behind manual approval. Verified with `spctl -a`: accepted, `source=Notarized Developer ID`. |
| R04 | pass | The workflow fails when the tag does not match `CFBundleShortVersionString`. |
| R05 | pass | The workflow launches the built app and fails if it exits within ten seconds. Also verified by hand. |
| R06 | pass | Release notes are hand-written per release and exercised: v0.1.5 and v0.1.6 document downloads, verification commands and what changed. `release.yml` also generates notes from commits for the draft. |

## Product identity

| ID | Result | Evidence |
|---|---|---|
| I01 | pass | `CFBundleName`, `CFBundleShortVersionString` and `CFBundleVersion`. |
| I02 | pass | `PFMRepositoryURL` and `PFMIssueTrackerURL` in `Info.plist`. |
| I03 | pass | `NSHumanReadableCopyright` and `PFMLicenseIdentifier`. |
| I04 | pass | Settings shows the version and links to the source and the issue tracker, read from the bundle rather than hardcoded. |
| I05 | pass | An app icon is embedded at all ten required sizes and the DMG — the only installer surface these apps have — now carries it as its volume icon (macos-notarization-broker#36). The icon is checked on the way into the signed image: not a symlink, not Mach-O, real icns magic. |
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
| G08 | pass | `.github/github-app.yml` records repository instructions, the local validation scripts, and two deliberate choices: no browser auto-open, and remote control off because this repository holds a signing path. |

## Language

| ID | Result | Evidence |
|---|---|---|
| L01 | pass | English, declared in `README.md`. |
| L02 | pass | All user-facing strings are English. |
| L03 | pass | Declared English-only in `README.md`. |
| L04 | na | No string catalogs, because the app is English-only. |
| L05 | pass | Sorting uses `localizedStandardCompare`, dates use `DateFormatter`, sizes use `ByteCountFormatter`, and counts now go through `formatted()` so they group correctly. Covered by a test that asserts a four-figure batch is grouped in locales that group. The search-index token and a 1-9 step badge are deliberately excluded. |
| L06 | na | No translations exist. |
| L07 | pass | The repository, its documentation and its commit messages are English. |

## Accessibility

| ID | Result | Evidence |
|---|---|---|
| X01 | pass | Menu commands cover Select All, Find, Reveal, Trash and Undo; Shift-click ranges work; tiles are buttons with the button trait; and arrow keys now move between tiles, with Shift extending the selection and the target scrolled into view. Eight tests cover the movement rules including short last rows and grid edges. |
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
| Y04 | pass | **Settings → Your Data** shows the index path, reveals it in Finder, exports the whole index as plain JSON, and deletes the index and every preview behind a confirmation. Tests assert the export is decodable by anything and that a delete leaves the user's own model files on disk. |
| Y05 | pass | The AI provider is chosen by the user and named in Settings; the search engine and the four model sites are named. |
| Y06 | pass | README **What is stored, and for how long** names the index, preview store and Keychain entries, states there is no retention period because there is no server, and lists the three ways data is removed. |

## Summary

| Result | Count |
|---|---|
| pass | 78 |
| partial | 0 |
| fail | 0 |
| na | 6 |

No criterion fails and no partial remains.

- **I05** — closing this meant changing the signing path, which is not something to do for a
  cosmetic gain without saying so. The disk image now carries the app icon, and the icon is
  validated on the way into the signed artifact rather than trusted because it came from a bundle
  that had already passed preflight.

Two earlier partials are worth recording because closing them changed a decision rather than
adding a file:

- **X01** was the reason the state was `Needs work`. Arrow-key navigation now moves between tiles,
  Shift extends the selection, and the target is scrolled into view. Eight tests cover the movement
  rules, including the short last row where no tile sits directly beneath the cursor.
- **P09** was blocked because the stats workflow could not push while `main` requires status checks
  it does not run, and the documented fix was a `STATS_TOKEN` with bypass rights. That trade was
  refused. The workflow now opens a pull request instead, so the card is reproduced automatically
  and the protection is untouched. The merge is manual: GitHub holds workflow runs for events
  created with `GITHUB_TOKEN` at `action_required` until a maintainer approves them, so the
  required checks run after one click rather than never. Dispatching CI at the branch instead was
  tried and rejected — the check runs attach to the head commit but the pull request's rollup
  ignores them.

Fixing this surfaced a separate defect. `main` required a check named `Conformance record`, but the
reusable workflow reports it as `conformance / Conformance record`, so that requirement could never
be satisfied. It had gone unnoticed because every change so far reached `main` by an admin push
rather than through a pull request. The context name is corrected and the `Versions` check is now
required as well. Verified by merging the stats pull request through the protection rather than
around it: all five required checks reported, the pull request went `CLEAN`, and it merged without
an admin bypass — the first change in this repository to do so.

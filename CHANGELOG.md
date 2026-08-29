# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.3] — 2026-08-29

### Fixed

- **The library disappeared when the app moved into the App Sandbox.** `Application Support`
  resolves to the sandbox container from that point on, and macOS only migrates existing data into
  a new container for paths keyed by bundle identifier. This app used a human-readable folder name,
  so nothing was migrated and it started against an empty index. Nothing was deleted — the library
  simply became invisible — but from the user's side an update appeared to have destroyed 703
  files, three scanned folders and every tag, note and print record.

  The app now looks for a pre-sandbox library at the real home directory (not the container, which
  is what `NSHomeDirectory()` returns inside a sandbox) and adopts it on first launch, copying
  rather than moving so the original stays put. A library that already has content is never
  overwritten, and an empty index written by a previous first launch does not count as content —
  which is exactly the case that would otherwise have stranded the data forever.

  If the old library exists but cannot be read, which is what the sandbox does to a path outside
  the container, the app says so and where the data is, instead of reporting an empty library.

  Twelve tests cover the decision, three of them against a real filesystem laid out exactly as the
  failure looked.

- **Folders carried over from before the sandbox can be re-authorised.** Those roots have no
  security-scoped bookmark, because there was nothing to bookmark when they were added, so every
  file under them reads as missing — on the library this was found with, 261 of 703. A folder the
  app cannot read now offers **Grant Access…** instead of Rescan, opening the panel at that folder
  so it takes two clicks. Rescanning a folder that cannot be read only re-confirms that it cannot
  be read, which is why that button is replaced rather than accompanied.

## [0.2.1] — 2026-08-28

### Changed

- **3MF Quick Look now ships from its own repository:**
  [trsdn/threemf-quicklook](https://github.com/trsdn/threemf-quicklook). Wanting Finder previews for
  `.3mf` files should not require installing a library manager. It versions and releases
  independently; v1.0.0 is signed and notarized.
- **3MF parsing moved to [ThreeMFKit](https://github.com/trsdn/ThreeMFKit)** as a published package,
  pinned here by exact version. It was a directory in this repository consumed by two Xcode projects
  that therefore had to sit next to each other on disk. SwiftPM cannot depend on a subdirectory, so
  splitting the previewer out required splitting the package out first.

### Removed

- `Quicklook/` and `ThreeMFKit/`, along with the CI jobs, release steps and `--quick` flag that
  existed only to build them. History for both is preserved in their new repositories.

## [0.2.0] — 2026-08-28

### Added

- Arrow keys move between tiles in the library grid, Shift extends the selection, and the target is
  scrolled into view. The grid is the app's main surface and was previously only reachable by
  clicking or tabbing.
- **Settings → Your Data**: the index path, Reveal in Finder, Export Library as plain JSON, and
  Delete All Data behind a confirmation. Deleting removes the index and every stored preview and
  never touches your own model files.
- `scripts/badges.py`, which renders the licence and platform badges from `LICENSE` and
  `MACOSX_DEPLOYMENT_TARGET` into committed SVGs, with `--check` failing on drift. The README no
  longer loads badge images from a third-party host, which also stops that host observing readers.
- `.github/github-app.yml` recording repository instructions and two deliberate choices: no browser
  auto-open, and remote control off because this repository holds a signing path.
- README sections for rolling back to an earlier signed release, what compatibility means before
  1.0, and what is stored on the machine and how to remove it.
- The disk image now carries the app icon as its volume icon
  (macos-notarization-broker#36).

### Changed

- Counts in the interface go through `formatted()`, so they group correctly outside English
  locales. The search-index token and the 1-9 step badge are deliberately excluded.
- The repository stats workflow opens a pull request instead of pushing. It could not push while
  `main` requires status checks it does not run, and the documented alternative was a token with
  bypass rights; branch protection was worth more than the convenience.

## [0.1.6] — 2026-08-28

### Changed

- Both apps ship as universal binaries. They declared `arm64` only, so the published artifacts
  could not run on an Intel Mac even though both require macOS 15, which Apple still supports on
  Intel hardware from 2018-2019 onward. Artifacts are now named `-macOS-universal`.

## [0.1.5] — 2026-08-28

### Added

- Signed and notarized artifacts. Both the application and the Quick Look extension are published
  as DMG and ZIP, signed with a Developer ID, built with the hardened runtime, and notarized with
  the ticket stapled, alongside checksums and a provenance record naming the broker run and the
  source commit.

- `scripts/check-broker-profile.py`, run by `scripts/ci-local.sh` against each freshly built
  bundle. It mirrors the notarization broker's identity comparison — identifier, executable,
  package type, minimum system version and display name, including the broker's fallback from
  `CFBundleDisplayName` to `CFBundleName` — so a mismatch surfaces during a local run instead of
  after a tag has been cut.

### Fixed

- The Quick Look app advertised itself as `ThreeMFQuickLook` rather than `3MF Quick Look`, because
  it carried no `CFBundleDisplayName` and `CFBundleName` resolved to `$(PRODUCT_NAME)`. The
  notarization broker rejected it, and the name was wrong in Finder besides.

### Changed

- The release workflow now publishes a **draft**. Its artifacts are unsigned and cannot open on
  another Mac, so publishing them immediately handed users a download that could not work. The
  draft proves the tag builds and launches; the signed artifacts replace it before anyone sees it.
- The README no longer claims that GitHub Actions cannot run or that artifacts are unsigned;
  neither has been true since the repository became public and the broker path started working.

## [0.1.4] — 2026-08-28

### Added

- `scripts/check-versions.sh`, run by CI and by `scripts/ci-local.sh`, which fails when the two
  Xcode projects declare different versions, when a version is not full `X.Y.Z` semver, or when an
  `Info.plist` hardcodes a version instead of referencing the build setting.

### Fixed

- The Quick Look app and both of its extensions were still stamped `0.1`, because only the
  application project had been moved to a build-setting-driven version. The notarization broker
  rejected the bundle for a version mismatch, so Quick Look could not be signed.

## [0.1.3] — 2026-08-28

### Fixed

- Archiving failed under the script sandbox because the static core target still emitted and
  copied an Objective-C interface header it has no use for. Disabled, along with installing the
  library into the archive.

## [0.1.2] — 2026-08-28

### Fixed

- The app bundle embedded ZIPFoundation and PrintFileManagerCore as frameworks, which are
  versioned bundles containing symlinks, and the notarization broker rejects any archive holding
  one. `ThreeMFKit` is now a static product and `PrintFileManagerCore` a static library, so the app
  ships as a single binary with nothing embedded.

## [0.1.1] — 2026-08-28

### Fixed

- Replaced `isolated deinit`, which needs an experimental compiler flag on some Xcode versions and
  made the project unbuildable on the notarization runner. Teardown now happens in a small store
  type whose ordinary `deinit` releases the FSEvents streams.

## [0.1.0] — 2026-08-28

First tagged release.

### Added

- App Sandbox with security-scoped bookmarks, so folder access survives a relaunch.
- Undo for Auto Sort batches (⌘Z) with a result report listing what moved, was skipped, or failed.
- Remove, reveal and rescan actions for scanned folders.
- Shift-click range selection, Select All, and menu commands for Reveal in Finder and Move to Trash.
- Onboarding screen stating that indexing is local and network features are off by default.
- `scripts/release.sh` and a release workflow that sign, notarize and smoke-test distributable
  builds.
- `AGENTS.md` describing layout, validation commands and forbidden operations.
- An app-layer test target covering persistence safety, selection, privacy gating and undo.
- `scripts/ci-local.sh`, which runs the CI pipeline locally because hosted Actions are blocked.
- Onboarding in `macos-notarization-broker` as the `printfilemanager` and `threemfquicklook`
  profiles, so distribution builds are signed without Apple credentials touching this repository.

### Changed

- Preview images moved out of the library index into a content-addressed store. On a real
  installation the index dropped from 109 MB to 3 MB and a save from a full rewrite to 31 ms.
- Search ignores filler words, so "PLA files for Bambu P1S" matches instead of returning nothing.
- Search results and sidebar counts are cached and the search field is debounced. At 10,000 files
  sidebar counts went from 367 ms to 93 ms.
- Quick Look preview ranking now prefers the plate hero image and excludes object-picking masks.
- The `.3mf` type is imported rather than exported, and the extensions also register for
  `public.zip-archive`, so previews still work when a slicer owns the type.
- Shared 3MF parsing extracted into the `ThreeMFKit` Swift package.
- `ContentView` split from 2,060 lines into focused files.
- The "Indexing Errors" collection is now called "Unreadable Files".

### Fixed

- An unreadable library index is quarantined and writes are blocked, instead of the next edit
  silently overwriting it with an empty library.
- Inspector edits to Project and Source fields are no longer discarded when the selection changes.
- Recovery from a blocked library is reachable from the UI; previously nothing called it.
- Batch file operations no longer abort on the first failure, leaving the index out of step.
- Decompressed ZIP entries are size-capped, so a crafted `.3mf` cannot exhaust memory.
- Triangle indices from a `.3mf` are range-checked instead of trapping on overflow.
- Quick Look extensions log file paths privately rather than publicly.
- `FolderWatcher` no longer leaks FSEvents streams.

### Security

- The repository is public, which enabled branch protection requiring the four CI checks, secret
  scanning with push protection, private vulnerability reporting and Dependabot security updates.

- AI enrichment and web source lookup are both opt-in and default to off; neither can issue a
  request without explicit configuration.
- AI endpoints must use HTTPS, except for local servers.
- Untrusted `.3mf` metadata is delimited and length-bounded before reaching an LLM prompt.

## [0.1] — 2026-05-03

Initial internal version: folder indexing, metadata extraction, search, tagging, AI enrichment,
source lookup and Auto Sort, plus the Quick Look preview and thumbnail extensions.

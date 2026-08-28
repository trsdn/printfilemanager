# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.1.0] — 2026-08-28

First tagged release.

## [0.1] — 2026-05-03

Initial internal version: folder indexing, metadata extraction, search, tagging, AI enrichment,
source lookup and Auto Sort, plus the Quick Look preview and thumbnail extensions.

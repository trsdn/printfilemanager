# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **The test suite wrote to the user's own library.** `PrintFileManagerAppTests` runs the real app
  as its test host; the host builds its view model and loads a library before any test does, and
  built without entitlements it is not sandboxed, so Application Support resolved to
  `~/Library/Application Support/Print File Manager` — the real, pre-sandbox library. A test run
  read it, migrated it from schema 1 to 2 and wrote it back. Nothing was lost, because that
  migration moves preview images into the content-addressed store rather than discarding them and
  all 641 were verified still readable afterwards, but nothing about the arrangement guaranteed
  that, and the next run would have replaced the only pre-migration backup. A process hosting tests
  is now given a throwaway directory, for the index, the previews and the search for a pre-sandbox
  library alike, and cannot opt back in.

- **A good backup could be replaced by a worse one.** The `.bak` beside the index is written once
  per process and unconditionally replaced whatever was there, so one bad session stood between a
  good backup and none. It is now only replaced by an index that has not forgotten any of its
  records. Deliberately not a size rule: moving previews out of the index took a real library from
  114 MB to 3 MB without dropping one of its 703 records, and a size rule would freeze the backup
  at the first migration.

- **The pre-sandbox library migration could destroy a real library.** Whether the container already
  held data was decided by the index's byte size against a 4 KB ceiling. An empty index is about
  84 bytes and one record about 530, so a library of up to six real files sat under the ceiling and
  was deleted and overwritten by the older one. A security-scoped bookmark is about 900 bytes, so
  the mirror image also held: an empty library with four authorised folders cleared the ceiling and
  suppressed a migration that was due. Content is now decided by decoding the index and asking
  whether it holds records, and an index that cannot be decoded is never replaced.

- **The migration was described as happening once, and nothing enforced it.** The legacy folder is
  copied rather than moved, so the decision was re-derived on every launch. A user who chose "Start
  Fresh" or deleted their library would find the old one restored the next time they opened the
  app. The outcome is now recorded, and a settled decision is never revisited.

- **The migration could leave the user with no library at all.** It removed the destination index
  and then copied over it, so a denial, a full disk or the source disappearing ended with nothing
  in place. Readability had been established by opening the source and reading a single byte, which
  says nothing about the remaining hundred megabytes. The copy is now staged beside the
  destination, decoded to prove it survived, and only then swapped in — previews first, index last,
  because an index that reports content is what stops the migration from ever being retried.

- **"Grant Access…" left the folder it claimed to replace.** `addRoot` builds a root with a fresh
  identifier, and `upsert` matches on identifier or URL, so choosing a parent folder — which the
  panel offers by default when the original has moved — appended a second root instead of replacing
  the first. The following scan then indexed the same files under both, and `PrintFileRecord` is
  `Identifiable`, so the grid received every file twice with duplicate identifiers. The root is now
  relocated in place, keeping its identity, its name and its records, and a record whose identity a
  scan re-attaches can no longer also survive in its old place.

- **A folder that came back stayed marked unavailable**, still offering "Grant Access…" for
  something the app could already read. Availability is now updated in both directions, and a
  folder that cannot be read is no longer offered a rescan that could only re-confirm it.

- **Launch could beachball with nothing on screen.** The migration ran from the view model's
  initializer, which `@StateObject` evaluates before the window exists. It now runs as async work
  before the index is read, with the user told what is happening.

- **A tile could still overflow the narrowest grid column.** `.clipped()` affects drawing, not
  layout, so four badges beside three fixed buttons demanded more than the 176pt column. The badge
  group is now explicitly compressible.

- **The endpoint accepted any URL scheme**, including `file:` and `ftp:`, which reached
  `URLSession` and failed obscurely. Restricted to http and https; plain http stays allowed.

### Changed

- **The endpoint transport note now says what macOS will actually do.** Measured from a sandboxed
  build: App Transport Security allows plain http to a private address, an unqualified hostname or
  a `.local` name, and refuses it to anything else with `NSURLErrorDomain -1022` — including a
  private DNS name such as `models.lan`. The note said such requests were "readable in transit",
  describing a request that is never sent. It now names the refusal and the two ways out.

- **The enrichment benchmark's discipline metric was rewritten.** It reduced every value to its
  first token and matched it as a substring, so a fabricated `sourceURL` was compared as the string
  `https` and went undetected in 17 of 40 real records. See `docs/enrichment-benchmark.md`; the
  metric is now checked itself, offline, on every CI run.

## [0.2.6] — 2026-08-29

### Fixed

- **Opening a file in Bambu Studio crashed the app.** `NSWorkspace.open(_:withApplicationAt:
  configuration:completionHandler:)` invokes its handler on `com.apple.launchservices.open-queue`,
  but the closure is inferred as isolated to this main-actor type. Swift 6 checks that on entry,
  the check fails, and the process traps — `EXC_BREAKPOINT` in `_dispatch_assert_queue_fail`,
  before the body ever runs. Wrapping the body in `Task { @MainActor in }` did not help, because
  the trap happens before the body.

  Replaced with the `async` form, which has no foreign callback to be isolated wrongly: the await
  resumes on the main actor, where updating the status message is simply correct. The error is now
  reported with its underlying reason rather than a generic string.

- **The grid fell apart after resizing.** Tiles had no fixed height, because the title was
  `lineLimit(2)` without reserved space — a one-line title made a shorter tile than a two-line one,
  every row took the height of its tallest tile, and the rest floated at different offsets inside
  it. Titles now reserve both lines.

  Tiles could also grow wider than their grid column: the badges and the three action buttons
  shared one row, so a file with several badges pushed the row's minimum width past the column and
  the tile overflowed into its neighbour. Badges now sit in their own clipping group.

## [0.2.5] — 2026-08-29

### Added

- `scripts/bench-enrichment.py` and `docs/enrichment-benchmark.md`: the AI enrichment prompt
  measured against real library records instead of assumed. The result contradicted the obvious
  modernisation — replacing the prose JSON schema with `response_format: json_schema` scored 0/12
  on schema conformance, because the endpoint ignores it and the model then invents its own keys.
  Fence-stripping turned out to be load-bearing too: Claude fences every response. The prompt needed
  no change; the configured model is where the time goes — `claude-haiku-4.5` measured fastest with
  the richest output over 40 real records.

  The first run of that benchmark picked its candidates by grepping the model list for
  `mini|flash|small|fast`, which matches old naming and so tested a 2024 model while treating
  `gpt-5.4-mini` as current. Corrected, and recorded in the document so the next person picks
  deliberately.

### Changed

- **Plain `http` endpoints are allowed again, anywhere.** The previous rule refused `http` unless
  the host was loopback, which blocked the setup this app is built for: a self-hosted model server
  on your own network. Such a server cannot have a certificate, because no authority issues one for
  `192.168.2.177`. The endpoint field simply rejected it and AI enrichment could never run.

  The endpoint is yours to choose and nothing refuses it now. Where plain `http` goes to a host that
  is reachable from the internet, Settings shows a one-line note saying requests — and the API key,
  if there is one — are readable in transit. A note, not a gate.

  Nine tests pin that nothing is blocked, including the boundaries where a sloppy prefix match
  would wrongly treat a public address as local: `172.15`/`172.32` either side of `172.16/12`,
  `192.169` beside `192.168/16`, and `localhost.evil.com`.

## [0.2.4] — 2026-08-29

### Fixed

- **A folder with no access was reported as available.** `SecurityScopedAccessCoordinator` treated
  a root without a security-scoped bookmark as resolvable, returning the plain URL. That is right
  for a non-sandboxed build and wrong for a library carried into a sandbox — and the two are
  indistinguishable at that point, so it now asks the folder instead of assuming. The visible
  effect was a sidebar showing healthy folders with file counts while every file under them read
  as missing, and the **Grant Access…** button added in 0.2.3 never appearing, because nothing was
  ever marked unavailable.

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

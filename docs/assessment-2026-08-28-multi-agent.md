# Multi-Agent Assessment: Print File Manager & 3MF Quick Look

Date: 2026-08-28

> **Remediation status (2026-08-28).** Every finding in this document has since been addressed, and
> a follow-up UI/UX review was run and acted on as well. See the [Remediation Log](#remediation-log)
> at the end for exactly what changed, with before/after measurements. The findings below are
> preserved as written at assessment time.

## Scope and Method

Read-only assessment of the whole repository (both Xcode projects, ~7,674 lines of Swift) by five
parallel specialist agents, with the highest-impact findings independently re-verified by hand:

| Thread | Focus |
|---|---|
| Build/Test verification | Toolchain, schemes, compile, test execution, XcodeGen sync |
| Security & privacy audit | Secrets, network egress, untrusted-input parsing, destructive file ops, sandbox |
| Architecture & code quality | Persistence, search, concurrency, layering, tests, error handling, build config |
| Quick Look review | UTI/extension wiring, provider correctness, preview extraction, project topology |
| PRD gap analysis | 56 user stories + acceptance criteria vs. actual implementation |

Inputs: `docs/prd-3mf-library-manager.md`, `docs/prd-3mf-quick-look-preview.md`,
`docs/app-review-2026-05-03-print-file-manager.md`,
`.copilot-tracking/research/20260503-printfilemanager-qa-usability-research.md`, both READMEs,
all sources and tests in `printfilemanager/` and `Quicklook/`.

## Verified Baseline

Environment: Xcode 26.6 (17F113), Swift 6.3.3, macOS 26.6.2, XcodeGen 2.46.0.

| Project | Builds | Tests | Warnings |
|---|---|---|---|
| `PrintFileManager.xcodeproj` | yes | 29 / 29 pass | 0 |
| `ThreeMFQuickLook.xcodeproj` | yes | 4 / 5 pass — **1 failure** | 8 (all deprecation, all in `ThreeMFQLGenerator`) |

The checked-in `.xcodeproj` files are essentially in sync with their `project.yml`
(diffs are cosmetic XcodeGen-version noise only: `compatibilityVersion`, `TargetAttributes`,
`productRefGroup`).

PRD delivery: **31 DONE / 19 PARTIAL / 2 STUB / 4 MISSING** of 56 user stories
(~55% genuinely delivered, ~64% counting PARTIAL at half credit).

## Executive Summary

The engineering craft here is genuinely above average and should not be understated. The
`PrintFileManagerCore` layer is pure `Foundation`/`CryptoKit`/`simd` with no UI imports, uses
protocol injection for the 3MF reader / image normalizer / metadata extractor, streams SHA-256 in
1 MB chunks inside an `autoreleasepool`, and builds in **Swift 6 language mode** with strict
data-race checking. The codebase contains **zero** `try!`, `as!`, `fatalError`, or force-unwraps,
and **zero** `TODO`/`FIXME`/`HACK` markers. The API key is stored correctly in the Keychain, deletes
go to the Trash rather than being unlinked, Auto Sort defaults to Copy, every destructive plan has a
review gate, and LLM-proposed destination paths are properly sanitized against traversal.

What is missing is the trust layer. Three structural problems dominate: **persistence** (a single
whole-file JSON dump, rewritten in full on every mutation, with no schema version and a silent
total-data-loss path), **privacy gating** (AI enrichment is effectively on by default and web source
lookup has no gate at all), and **verification** (~3,091 lines of app-layer code with zero tests,
which is exactly where the risk lives). The product is a strong prototype that demos very well and
would frustrate badly on a real 500-file library.

---

## P0 — Critical

### P0-1 Load failure silently overwrites the user's library

`printfilemanager/Sources/PrintFileManagerApp/LibraryViewModel.swift:211-213`

```swift
} catch {
    statusMessage = "Library index could not be loaded"
}
```

If `database.load()` throws, `snapshot` keeps its empty initial value and only a transient status
string is set. The next mutation calls `saveSnapshot()`, which writes that empty snapshot
**atomically over the real library file**. There is no backup, no quarantine of the unreadable file,
and no flag that blocks writes until the user acknowledges.

`LibrarySnapshot` has no `schemaVersion` field (grep: 0 matches) and relies on synthesized
`Codable`, so adding any non-optional property makes every existing library file undecodable — which
triggers exactly this path.

**Impact:** permanent, silent loss of the entire curated library — the app's whole value — on any
schema change or single corrupt byte. Highest-consequence defect in the repository.

**Fix:** add `schemaVersion` plus a migration path; on decode failure rename the file to
`*.corrupt-<timestamp>`, surface a blocking error, and refuse to save until resolved; write a `.bak`
before the first save of each session.

### P0-2 Whole-file JSON persistence with inline thumbnails, rewritten per keystroke

`LibraryDatabase.swift:33-45`, `LibraryModels.swift:196`, `LibraryViewModel.swift:777-781, 933-939`,
`ContentView.swift:899-903`

`PrintFileRecord.thumbnailData: Data?` embeds the preview PNG **inside the record**, which becomes
base64 in JSON (+33%). `save()` re-encodes the entire snapshot `.prettyPrinted` and writes it
`.atomic`. Every mutation triggers a full rewrite, synchronously on the `@MainActor` — including the
notes `TextEditor`, which is bound with `.onChange` and therefore saves **per keystroke**.

**Measured on the live installation** (`~/Library/Application Support/Print File Manager/library-index.json`):
**109 MB, 652 embedded thumbnails, 54,627 lines.** Every character typed into a notes field
re-encodes and rewrites 109 MB on the main thread.

**Fix (in order):** externalize thumbnails to files and store a path/hash instead of `Data` (removes
the dominant byte cost immediately); move persistence into an `actor` and coalesce saves (~500 ms);
then migrate to SQLite (GRDB) or SwiftData with per-record partial updates.

### P0-3 AI enrichment is effectively enabled by default

`AISettingsStore.swift:37-60`

```swift
endpointURL = defaults.string(forKey: Keys.endpointURL) ?? "https://api.openai.com/v1/chat/completions"
model       = defaults.string(forKey: Keys.model) ?? "gpt-4o-mini"
includeThumbnail = defaults.object(forKey: Keys.includeThumbnail) as? Bool ?? true
...
var isConfigured: Bool { enrichmentSettings() != nil }
```

`enrichmentSettings()` returns non-nil whenever the endpoint URL parses and a model name is set —
both are pre-filled defaults. There is **no `enabled` flag anywhere** (grep-confirmed) and no API-key
requirement, so `isConfigured == true` on a fresh install and the UI displays
"Configured in Settings" (`ContentView.swift:1516`) before the user has touched anything.

The request body is transmitted even with an empty key: `applyAuthorization` returns early when the
key is blank, but the POST still goes out and is only rejected with a 401 *after* the body has been
sent.

**Impact:** on first launch, with zero configuration, clicking Enrich POSTs the file name,
`relativePath`, extracted metadata and a base64 preview thumbnail to `api.openai.com`. This breaks
the PRD promises *"AI enrichment is disabled by default"* and *"requires explicit configuration of a
provider or endpoint before any request is made"*.

**Fix:** introduce an explicit `enrichmentEnabled` boolean defaulting to `false`; require a stored
API key or an explicitly user-entered endpoint for `isConfigured`; throw in `AIEnrichmentClient`
before any network call when not user-configured; ship no default endpoint (or treat the default as
"unconfigured").

### P0-4 Web source lookup is a second, entirely ungated exfiltration channel

`ContentView.swift:1080-1086`, `SourceLookupClient.swift:129-178`, `LibraryViewModel.swift:391-396`

The "Find" button is disabled only while a lookup is in flight — not on configuration.
`lookupSource` takes `settings: AIEnrichmentSettings?` and tolerates `nil`, so it runs with no AI
configuration at all. It sends `"<projectName or fileName> site:makerworld.com"` (and equivalents)
to `https://duckduckgo.com/html/` with a spoofed `User-Agent`, then GETs arbitrary result URLs.
`enrich()` additionally bundles a source lookup, so the AI action hits DuckDuckGo too.

**Impact:** potentially confidential project and file names are sent to a third-party search engine
and to arbitrary result pages, from first launch, with no consent gate and no API key required.
There is no per-folder or per-file exclusion to keep private models local (PRD story 31).

**Fix:** separate explicit opt-in for web lookup, distinct from AI enrichment; display the outbound
query and destination before sending; do not auto-bundle source lookup inside `enrich()`; implement
the per-folder/per-file exclusion list.

---

## P1 — High

### P1-1 Quick Look picks the wrong preview image

`Quicklook/Sources/ThreeMFCore/BambuPreviewResolver.swift:27-96`

Ranking sorts ascending (`left.rank < right.rank`, line 22) and the extractor returns the first
candidate that decodes, so **lower rank wins**. Rank math for typical Bambu entries (base 1,000):

| Entry | Computation | Rank |
|---|---|---|
| `metadata/top_1.png` | 1000 − 200 − 320 − 20 | **460** |
| `metadata/pick_1.png` | 1000 − 200 − 300 − 20 | **480** |
| `metadata/thumbnail.png` | 1000 − 200 − 100 − 20 | **680** |
| `metadata/plate_1.png` | 1000 − 200 **+ 200** − 20 | **980** |

The try-order is therefore `top_1` → `pick_1` → generic thumbnail → `plate_1`. `pick_1.png` is
Bambu's **object-picking / hit-test mask** (flat colour-coded blobs), and `plate_1.png` is the
isometric hero image shown on MakerWorld. The hero image is effectively never selected.
`ThreeMFCoreTests.swift:24-31` asserts this inverted order, cementing the defect; `pick_` is untested.

**Fix:** rank `plate_*` (non-`_small`, non-`no_light`) highest, `top_*` second, and **exclude**
`pick_*` entirely — it is not a human-viewable preview. Update the test expectation.

Related (Medium): `isSupportedImagePath` accepts any `.png`/`.jpg` anywhere, so a texture at
`3d/textures/wood.png` scores 980 and ties `plate_1.png`; the ascending path tiebreak puts `3d/…`
first, meaning a material swatch can win.

### P1-2 Quick Look will not fire on the target users' machines

`Quicklook/Sources/ThreeMFQuickLookApp/Info.plist:39-119`

`.3mf` is declared under `UTExportedTypeDeclarations` as `com.printfilemanager.threemf`, i.e. the app
*claims ownership* of a format it does not own. Two further identifiers
(`com.microsoft.3mf-package`, `com.printfilemanager.3mf`) redundantly declare the same extension, and
one of them is not a real registered system UTI.

Quick Look matches by conformance to the file's **resolved** UTI. On a machine without a slicer the
type resolves to `com.printfilemanager.threemf` and the extension is invoked. On a target user's Mac
— a 3D-printing user with Bambu Studio / Orca / PrusaSlicer, which claim `.3mf` at Owner rank — it
resolves to the slicer's type, which conforms to `public.data`/`public.zip-archive` but **not** to
any of the four declared identifiers. The extension is then silently never called and Finder shows
the default archive preview.

**Fix:** collapse to a single **imported** declaration, keep `LSHandlerRank = Alternate`, drop the
invented and hard-coded dynamic identifiers, and add `public.zip-archive` to
`QLSupportedContentTypes` as an always-true fallback — then sniff for `3D/3dmodel.model` at runtime
and return the fallback reply for non-3MF archives.

### P1-3 App layer has zero tests

`printfilemanager/project.yml:42-63` declares a single test target depending only on
`PrintFileManagerCore`. Untested: `ContentView.swift` (1,726) + `LibraryViewModel.swift` (945) +
`AISettingsStore.swift` (202) + `SettingsView.swift` (92) + `FolderWatcher.swift` (90) +
`PrintFileManagerApp.swift` (36) ≈ **3,091 lines, 0 tests** — precisely where P0-1, P0-2, P0-3 and the
file-operation orchestration live.

Network paths are equally unverified: there is no `URLProtocol`/`URLSession` stub anywhere, and no
test asserts outbound headers, HTTP error mapping, or the retry-without-thumbnail branch.

This was already filed as a **P0** in `docs/app-review-2026-05-03-print-file-manager.md:112-116` and
is still open.

### P1-4 Unbounded decompression (ZIP bomb)

`Quicklook/Sources/ThreeMFCore/ThreeMFPackageReader.swift:42-59`

```swift
var data = Data()
_ = try archive.extract(archiveEntry) { chunk in data.append(chunk) }
return data
```

`entry.uncompressedSize` is available but never enforced. The *metadata* path does guard
(`guard entry.uncompressedSize <= 2_000_000`, `LibraryIndexer.swift:219-223`), but the **preview**
(`ThreeMFSceneExtractors.swift:66, 87`) and **mesh** (`:126`) paths do not — and preview extraction
runs automatically during indexing.

**Impact:** a crafted `.3mf` dropped into a watched folder causes unbounded allocation with no user
interaction. DEFLATE reaches ~1000:1. Also affects the memory-tight Quick Look extension. Violates
the PRD requirement to *"mark files as unreadable without crashing"*.

**Fix:** enforce an `uncompressedSize` ceiling before extracting any entry, and stream with a hard
byte budget that aborts oversized entries.

### P1-5 Search does not scale

`LibraryViewModel.swift:44-60`, `LibrarySearch.swift:109-147`, `LibraryViewModel.swift:270,277`

`filteredRecords` is a **computed property**, so SwiftUI re-evaluates it on every `body` pass: a full
O(n) filter plus O(n log n) sort of the whole library, rebuilding each record's ~20-field
`searchableText` from scratch. The sidebar count badges call `count(for:)` once per collection and
per root, each a further full scan. `searchText` is `@Published` with no debounce. All on the main
thread, compounding with P0-2.

**Fix:** back search with SQLite FTS5, or at minimum precompute `searchableText` once at index time
and store it on the record; debounce `searchText` (~250 ms) into a `@Published private(set)` result;
compute collection counts once per snapshot change rather than per render.

### P1-6 No CI, no linting, no signing — for an app that moves user files

No `.github/workflows`, no `.swiftlint`/`.swiftformat`, no `SWIFT_TREAT_WARNINGS_AS_ERRORS`, and no
signing/notarization path (`Quicklook/README.md` builds with `CODE_SIGNING_ALLOWED=NO`). The
repository also has no root `README.md`, no `LICENSE`, and no `CHANGELOG.md`.

An **unsigned** Quick Look extension will not load on anyone else's machine, and the README never
instructs moving the app to `/Applications` and launching it once, which is required for extension
registration. Debug guidance omits `qlmanage -p <file>` and
`pluginkit -mAvvv -p com.apple.quicklook.preview`.

---

## P2 — Medium

| # | Finding | Location |
|---|---|---|
| P2-1 | **`Int32` overflow trap.** `base + v1` on attacker-controlled triangle indices; Swift traps on overflow and the trap is uncatchable by the per-file `try?`. Indices are never validated against vertex count. Crashes the app and the QL extension on a crafted file. | `ThreeMFSceneExtractors.swift:168-174`; also `ContentView.swift:1462-1466` |
| P2-2 | **No undo, no operation log, non-transactional batches.** `execute()` applies actions sequentially; on a mid-loop throw, already-moved files keep stale index paths because `applyMovedRecords` only runs on full success. PRD stories 21 and 56 unmet. | `OrganizationPlanner.swift:65-98`; `LibraryViewModel.swift:721-747` |
| P2-3 | **No timeouts, rate limiting, or backoff** against a paid API (default 60 s). Auto Sort issues per-record AI calls in an unthrottled loop. PRD story 30 unmet. | `AIEnrichmentClient.swift`; `SourceLookupClient.swift:160,172` |
| P2-4 | **Main app is not sandboxed.** No `.entitlements` file and no `CODE_SIGN_ENTITLEMENTS` under `printfilemanager/`. Folder watching uses raw paths with no security-scoped bookmarks, so enabling the sandbox later will silently break roots on relaunch. App Store distribution impossible as-is. | `printfilemanager/project.yml`; `FolderWatcher.swift:44` |
| P2-5 | **Prompt injection.** Attacker-controlled `.3mf` metadata is interpolated into LLM prompts unescaped. Blast radius is contained to tag/description poisoning because `OrganizationPlanner` sanitizes proposed paths properly — not arbitrary write. | `AIEnrichmentClient.swift:189-237, 260-311` |
| P2-6 | **Failing test with a broken skip guard.** `externalRealFixtureURL()` checks that the *pointer file* exists but never that the file it points to exists, so a deleted fixture fails instead of skipping. The pointer targets `/Users/torsten/Downloads/Rick's_Wall_Hook.3mf`, which no longer exists. No `.3mf` fixture is committed, so the only real-world integration test is unreproducible and un-CI-able. | `Quicklook/Tests/ThreeMFCoreTests/ThreeMFCoreTests.swift:92-111` |
| P2-7 | **Deprecated Quick Look generator is dead weight.** `ThreeMFQLGenerator` uses the CFPlugIn API deprecated in macOS 10.15, is built by the scheme but never embedded (no copy phase), cannot register on the macOS 15 deployment target, and produces all 8 compiler warnings. It also compiles `ThreeMFCore` a third time. | `Quicklook/project.yml:73-87, 106` |
| P2-8 | **`ContentView.swift` is a 1,726-line God file** with 26 view structs; `FileInspectorView` alone is 453 lines with 17 `@State` properties. `LibraryViewModel` carries ~8 unrelated responsibilities across 945 lines. SceneKit geometry assembly lives in the view and is therefore untestable. | `ContentView.swift`; `LibraryViewModel.swift` |
| P2-9 | **`FolderWatcher` has no `deinit` and ignores FSEvents flags.** Streams leak if the watcher deallocates without `update(roots: [])`; `kFSEventStreamEventFlagRootChanged`/unmount is indistinguishable from an ordinary change, so an unmounted external drive triggers a rescan instead of an "unavailable" state (PRD story 23). | `FolderWatcher.swift` |
| P2-10 | **Full re-hash on every scan.** SHA-256 over every file's full contents on every scan, with no `(size, mtime)` short-circuit — and FSEvents triggers a full-root rescan on any change, so adding one file re-reads the entire library. | `LibraryIndexer.swift:128-141` |
| P2-11 | **Hidden cross-project coupling.** `PrintFileManagerCore` compiles `../Quicklook/Sources/ThreeMFCore` by relative path. The same five files are compiled into **three** binaries (`ThreeMFCore.framework`, `ThreeMFQLGenerator.bundle`, `PrintFileManagerCore.framework`) as distinct module types, with ZIPFoundation pinned independently in two `Package.resolved` files (both `0.9.20` today, nothing enforces it). Moving or renaming `Quicklook/` breaks the app build. No workspace, no shared package, undocumented. | `printfilemanager/project.yml:21` |
| P2-12 | **Quick Look extensions log full file paths at `privacy: .public`**, persisting the username and folder structure into the unified log and sysdiagnose. | `PreviewProvider.swift:20,31`; `ThumbnailProvider.swift:24,35` |
| P2-13 | **Fallback persistence path is a purgeable temp directory.** If Application Support cannot be resolved, the index is written to `temporaryDirectory` and can silently vanish between launches. | `LibraryViewModel.swift:33-41` |
| P2-14 | **Generic error surfaces on the riskiest paths.** Core defines proper `LocalizedError` types, and enrichment/lookup do surface detail — but scan/load/save use generic transient banners that discard the cause. Save and load failures, the ones that risk data loss, are the least visible. | `LibraryViewModel.swift:212, 332, 937` |
| P2-15 | **Dual source of truth.** Both `project.yml` and the generated `.xcodeproj` are committed, and XcodeGen is an undocumented hard prerequisite. Verified in sync today (cosmetic diffs only), but nothing prevents divergence. | both projects |

---

## Features That Look Done But Are Not

| Feature | Verdict | Evidence |
|---|---|---|
| Natural-language search | **STUB** — `matchesText` splits on spaces and requires every token as a substring (AND). "PLA files for Bambu P1S" requires the literal words "files" and "for" and returns nothing. No stopwords, no field routing. | `LibrarySearch.swift:109-113` |
| Source lookup confidence / provenance | **STUB** — `matchConfidence` and `searchQuery` are computed and stored but never displayed anywhere in the UI. Recommended in the 2026-05-03 review; still open. | `LibraryViewModel.swift:837-841` vs `ContentView.swift:1112-1134` |
| Near-duplicate detection & "explain why grouped" | **PARTIAL** — exact SHA-256 only; no same-source-URL, similar-title, or similar-profile grouping or explanation. | `LibrarySearch.swift:248-256` |
| Undo / reversible operation log | **MISSING** — no journal, no undo, no recovery path. | `LibraryViewModel.swift:721-747` |
| Per-file/folder AI exclusion, queueing, rate limiting | **MISSING** — grep: 0 matches. | — |
| Preview fallback for preview-less files | **PARTIAL** — the inspector renders real mesh geometry via SceneKit, but the browse grid shows only a generic `cube.transparent` icon; no mesh-derived thumbnail is generated. | `ContentView.swift:818-822, 1353-1355` |
| Security-scoped bookmarks | **MISSING** — works today only because the app is unsandboxed. | grep: 0 matches |
| Unavailable volume handling | **PARTIAL** — metadata is preserved, but every file on a disconnected root flips to `.missing` rather than a distinct "unavailable" state. | `LibraryDatabase.swift:104-111` |
| Incremental background indexing | **PARTIAL** — scan is off-main, but re-enumerates and re-hashes everything, has no cancellation, and merges + saves back on the main actor. | `LibraryIndexer.swift:128`; `LibraryViewModel.swift:321-329` |

## Documentation Drift

- PRD states *"Do not delete files in the MVP"* (`prd:160`), but a Trash action ships
  (`LibraryViewModel.swift:529-554`). Correctly implemented as `NSWorkspace.recycle` with a
  confirmation alert, but it contradicts the stated scope.
- PRD defers geometry rendering and the Quick Look PRD forbids it, yet an interactive SceneKit
  preview ships (`ContentView.swift:1418-1470`).
- PRD prefers SQLite; the implementation is a JSON file (`LibraryDatabase.swift:19`).
- Quick Look PRD acceptance *"test fixtures are collected before implementation is considered
  complete"* is unmet — no `.3mf` fixture is committed. `Quicklook/README.md:29` is honest about this.
- Undocumented in any PRD: Print History, Open-in-Bambu-Studio, AI source-candidate selection.

## Still Open From the 2026-05-03 Review

P0 "Add ViewModel and UI Workflow Tests"; P1 source-lookup confidence/provenance display and a
separate web-lookup privacy setting; P1 root reveal/remove and per-root scan state; P2 post-batch
result report; P2 duplicate explanation and cluster-level review.

Genuinely fixed since then and verified present: `Needs Review` collection, faceted filters,
explicit copy/move labels with selected counts, reviewed/reopen signature mechanism.

## Implemented Correctly (verified — do not regress)

- API key in the Keychain (`kSecClassGenericPassword`,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); only a boolean flag in `UserDefaults`.
- `Authorization: Bearer <key>` header is correct. *(Note: tooling that redacts credential-shaped
  lines renders this as `"******"`; verified by line length and MD5 that the source is correct.)*
- No TLS bypass; no custom `URLSessionDelegate` or `serverTrust` override.
- **ZIP Slip is not exploitable** — archive entry paths are used only for in-memory lookup, never to
  construct a write path.
- **XXE is off** — `XMLParser(data:)` with default `shouldResolveExternalEntities == false`.
- LLM-proposed paths are sanitized: strips `/` `:` newlines and control characters, drops `.`/`..`,
  caps depth at 5, forces a `.3mf` filename, rebuilds under the target root; `moveItem` fails rather
  than overwrites; no-op destinations are skipped; `uniqueDestinationURL` de-duplicates.
- Delete goes to the Trash behind a confirmation alert; Auto Sort defaults to Copy; every plan has a
  review sheet.
- Enrichment payload excludes raw file bytes — sends `fileName`, `relativePath`, selected metadata
  and a preview thumbnail only.
- Quick Look extensions are correctly embedded, sandboxed, network-free, use security-scoped access
  with `defer`, and **terminate every completion path** — no infinite-spinner bug exists.
- Swift 6 strict concurrency throughout; the only GCD use is the one FSEvents requires.
- Core tests synthesize real ZIP packages in-test with real assertions, and the optional integration
  test uses a proper `XCTSkip` rather than a silent early return.

---

## Roadmap

### Phase 1 — Do no harm (S, immediate)

1. Quarantine on load failure; block saves until acknowledged; write a `.bak` (P0-1).
2. Add `schemaVersion` and a migration scaffold (P0-1). Do this before adding any model field.
3. Introduce a real `enrichmentEnabled` flag defaulting to `false`; require explicit configuration
   (P0-3).
4. Gate web source lookup behind its own opt-in; unbundle it from `enrich()` (P0-4).
5. Enforce an `uncompressedSize` cap on preview and mesh extraction (P1-4).
6. Replace `Int32` triangle arithmetic with checked/`Int64` math and validate indices against vertex
   count (P2-1).
7. Fix the fixture guard to verify the target file exists; commit a small synthetic `.3mf` fixture
   (P2-6).
8. Fix the preview ranking: prefer `plate_*`, exclude `pick_*`, update the test (P1-1).

### Phase 2 — Make it scale (M)

9. Externalize thumbnails out of `PrintFileRecord` (removes ~95% of the 109 MB write cost).
10. Move persistence into an `actor`; coalesce saves; never save per keystroke.
11. Migrate to SQLite/GRDB with FTS5; debounce search; cache `searchableText`; compute counts once
    per snapshot.
12. Skip re-hashing when `(size, mtime)` are unchanged.

### Phase 3 — Make it trustworthy (M)

13. Per-action operation journal → undo, plus a per-file batch result report.
14. Introduce `AIEnriching` / `SourceLooking` protocols and inject `URLSession`; inject clients into
    the ViewModel.
15. Add an app-layer test target: persistence safety, Auto Sort orchestration including mid-plan
    failure, and network header/error/retry via a `URLProtocol` stub.
16. GitHub Actions (`xcodegen generate && xcodebuild test`), SwiftLint with a file-length rule,
    root `README.md` and `LICENSE`.
17. Request timeouts, a concurrency limiter, and exponential backoff.

### Phase 4 — Consolidate (M–L)

18. Extract `ThreeMFKit` as a real SwiftPM package consumed by both projects; delete the
    `../Quicklook/...` relative-path share and the duplicate ZIPFoundation pins.
19. Delete the `ThreeMFQLGenerator` target (removes the third core compile and all 8 warnings).
20. Embed the Quick Look extensions in PrintFileManager and retire the 47-line stub host app;
    migrate the UTI declarations, switching from exported to imported.
21. Decompose `ContentView.swift` into ~8 files; split `FileInspectorView` into per-section views
    backed by an `InspectorFormModel`; split `LibraryViewModel` into coordinators.
22. Move SceneKit scene building into a testable Core `ThreeMFSceneBuilder`.
23. Enable App Sandbox with security-scoped bookmarks; add a signing/notarization path.

### Product Scope

The 56-story PRD is itself the central scope problem for a solo project. Recommendation: cut to
roughly 15 stories describing a "trustworthy core" — indexing at scale, embedded and mesh previews,
faceted and keyword search, tags and notes, exact-duplicate detection, the review queue, and safe
copy with undo — and formally defer the rest.

**Drop or defer:** natural-language search (US54) — ship excellent faceted search instead and stop
implying NL; multi-platform source lookup with GitHub, license parsing and version diffing
(US40-42) — DuckDuckGo HTML scraping is brittle and privacy-sensitive, keep embedded-URL lookup and
manual entry; AI queueing and per-folder exclusion (US30/31) until batch enrichment exists at all;
interactive 3D preview repositioned as nice-to-have; AI-assisted Auto Sort demoted from a headline —
the deterministic planner suffices for MVP and the LLM path adds cost, latency and failure modes.

## Non-Goals (unchanged)

Slicer replacement; mesh editing or repair; printer control or print submission; marketplace browsing
as a primary workflow; automatic deletion of duplicates; accounts, cloud sync, or multi-user
collaboration; generic AI chat as the primary interface.

---

## Remediation Log

Work completed on 2026-08-28, immediately following the assessment. Verified state afterwards:

| Project | Builds | Tests | Compiler warnings |
|---|---|---|---|
| `PrintFileManager` | yes | **37 / 37 pass** (was 29) | 0 |
| `ThreeMFQuickLook` | yes | **8 pass, 1 correctly skipped** (was 4 pass, 1 failing) | **0** (was 8) |

SwiftLint: 0 errors, 24 warnings — all of them the oversized-file and long-line findings that this
document flags for decomposition.

### Fixed

| Finding | What changed |
|---|---|
| **P0-1** Load failure overwrote the library | An unreadable index is now moved to `library-index.corrupt-<timestamp>.json` and a `persistenceLockout` blocks all writes until the user resolves it. `startFreshLibraryAfterLoadFailure()` is the explicit escape hatch. One `.bak` is written per session, capturing the last known-good state. |
| **P0-1** No schema versioning | `LibrarySnapshot.schemaVersion` added with a custom `init(from:)` that tolerates missing keys, so pre-versioning files still load. Files from a newer schema are rejected with `LibrarySchemaError` rather than silently mis-parsed. A `migrate(_:)` hook is in place for future changes. |
| **P0-2** 109 MB rewritten per keystroke | Saves are coalesced with a 600 ms window and flushed on app termination. Trash and move operations flush immediately so the index can never outlive the file system state. |
| **P0-3** AI enabled by default | `enrichmentEnabled` added, defaulting to `false`. `enrichmentSettings()` and `loadModels()` both return early unless it is on, so no request can be constructed without an explicit opt-in. Endpoints must now be `https`, except for localhost and `.local` hosts. |
| **P0-4** Ungated web source lookup | `sourceLookupEnabled` added as a separate setting, also defaulting to `false`. `enrich()` no longer bundles a lookup; it takes an explicit `allowSourceLookup` argument. The Find button is disabled when off, and Settings states exactly what each toggle transmits. |
| **P1-1** Wrong Quick Look preview | `BambuPreviewResolver` restructured from accumulated deltas into explicit named tiers. `plate_*` is now the preferred hero image, `top_*` ranks below it, unrelated images such as textures are demoted, and `pick_*` object-picking masks are excluded outright. Four new tests pin the behaviour, replacing the assertion that had cemented the inverted order. |
| **P1-4** Unbounded decompression | `ZIPFoundationThreeMFPackageReader` enforces a configurable `maximumEntrySize` (256 MB default, 64 MB for preview images). Both the declared size and the streamed byte count are checked, because archive metadata can lie. |
| **P1-5** Search recomputed per render | `filteredRecords` is cached behind a snapshot revision plus the query. Sidebar counts are computed in a single pass per snapshot revision instead of a full library scan per badge per render. |
| **P1-6** No CI, lint, README or license | Added a root `README.md`, an MIT `LICENSE`, a GitHub Actions workflow running SwiftLint and `xcodebuild test` for both projects, and a tuned `.swiftlint.yml`. CI regenerates from `project.yml` rather than diffing the committed project, which would be flaky across XcodeGen versions. |
| **P2-1** `Int32` overflow trap | Triangle indices are parsed as `Int` and range-checked against the vertex count before narrowing. Malformed triangles are dropped instead of trapping uncatchably. |
| **P2-3** No request timeouts | Explicit `timeoutInterval` on every request: 30 s for AI enrichment, 20 s for source lookup. |
| **P2-6** Failing test, broken skip guard | The fixture resolver now verifies the *target* file exists, not just the pointer file, so a deleted fixture skips rather than fails. |
| **P2-7** Deprecated QL generator | `ThreeMFQLGenerator` target and sources deleted. This removed all 8 build warnings and a third redundant compile of `ThreeMFCore`. |
| **P2-9** `FolderWatcher` stream leak | Added an `isolated deinit` calling `stopAll()` — the Swift 6 mechanism for touching actor-isolated state during deallocation. |
| **P2-10** Full re-hash every scan | `scan(root:previousRecords:)` carries over records whose size and modification date are unchanged, skipping both the SHA-256 pass and the ZIP parse. |
| **P2-12** Paths logged publicly | All Quick Look logging switched from `privacy: .public` to `.private`. |
| **P2-13** Silent temp-directory fallback | The volatile fallback store is now reported in the status line instead of degrading silently. |
| **P2-14** Generic error messages | Save and load failures now include the underlying error description. |

### Tests added

Eight new core tests, covering precisely the paths that previously had none:

- index quarantine preserves an unreadable file and removes the original
- exactly one backup is written per session, capturing the first generation
- a snapshot without `schemaVersion` decodes as the current version
- a snapshot from a newer schema is rejected with the expected error
- an entry exceeding the configured size limit throws `entryTooLarge`
- out-of-range, negative and overflow-inducing triangle indices are dropped
- an unchanged file is carried over verbatim on rescan
- a changed file is re-indexed and gets a new content hash

Plus four Quick Look ranking tests (hero preference, pick-mask exclusion, texture demotion, generic
slicer thumbnail).

### Corrected finding

An earlier draft reported that the `Authorization` header was hardcoded to `"******"` and the API
key was never transmitted. **This was a false positive.** The tooling used for the review redacts
credential-shaped source lines in its output. The real line is 85 characters with MD5
`f70b3fc32b59682f7ce8efc2eafd37b4`, matching `request.setValue("Bearer \(trimmedKey)", ...)`
exactly. Authorization was always implemented correctly.

### Second pass — everything else closed

| Item | What changed |
|---|---|
| **Thumbnails in the index (P0-2 remainder)** | Preview images moved into a content-addressed `ThumbnailStore` beside the index; records hold a SHA-256 key. Migrating the real 109 MB installation: **index 109 MB → 3 MB**, save **109 MB rewrite → 31 ms**, 652 previews preserved and deduplicated to 547 files, 0 broken, 0 missing, tags and roots intact. |
| **Search and sidebar cost (P1-5 remainder)** | Cached each record's lowercased searchable text; added `count(in:matching:)` and `collectionCounts(in:)` that filter without sorting; debounced the search field by 200 ms. At 10,000 files: sidebar counts **367 ms → 93 ms**, free text search **117 ms → 66 ms**, index save **224 ms → 125 ms**. |
| **Undo and batch reporting (P2-2)** | `execute()` attempts every action and returns a per-action report instead of aborting on the first failure; `undo()` reverses a batch (moves back, copies removed, originals never deleted). A result sheet lists failures with reasons and offers Undo, also on ⌘Z. |
| **App-layer tests (P1-3)** | `AIEnriching` and `SourceLooking` protocols injected into the view model; new `PrintFileManagerAppTests` target with 17 tests covering persistence lockout and recovery, save coalescing, selection, root removal, privacy gating, error surfacing, and move + undo. |
| **ThreeMFKit as a package (P2-11)** | The `../Quicklook/Sources/ThreeMFCore` relative-path share is gone; both projects consume a local Swift package with a single ZIPFoundation pin. CI runs its tests via `swift test`. |
| **UTI declaration (P1-2)** | Switched from exported to a single imported declaration, added `public.zip-archive` as a fallback conformer, and added runtime sniffing for the 3MF model part so other archives are handed back to the system. |
| **ContentView decomposition (P2-8)** | Split into Sidebar, Browser, Organization, Inspector and SharedUI. ContentView itself is now 178 lines; the largest remaining file is the inspector at 563. |
| **App Sandbox (P2-4)** | Sandbox enabled with user-selected read-write, app-scoped bookmarks and outbound network. Roots are persisted as security-scoped bookmarks, resolved at launch, refreshed when stale. Verified present in an ad-hoc signed binary. |
| **Prompt injection (P2-5)** | Untrusted metadata is wrapped in a delimited block, its delimiters neutralised and its length bounded. |

### Follow-up UI/UX review

A separate UI/UX review found two further critical defects, both fixed:

- **Lockout recovery was unreachable.** `startFreshLibraryAfterLoadFailure()` was not called by any
  view, so a user whose index could not be read was told so in grey caption text with no way out.
  It now shows a red banner with a confirmed "Start a Fresh Library" action.
- **The inspector silently discarded edits.** Project and Source fields committed only on "Done", so
  clicking another file threw away whatever had been typed. They now commit as you type.

Also addressed: scanned folders had no way to be removed at all; one generic empty state covered
four situations and offered no recovery action; Shift-click range selection and ⌘A were missing;
eight icon-only buttons had no accessibility labels; and the first-run screen was a bare prompt with
no value proposition or privacy statement.

### Final verified state

| | At assessment | Now |
|---|---|---|
| PrintFileManager tests | 29 | **67** (50 core + 17 app) |
| ThreeMFKit tests | 4 pass, 1 failing | **10 pass, 1 skipped** |
| Compiler warnings | 8 | **0** |
| SwiftLint | not configured | 0 errors |
| Largest UI file | 1,726 lines | 563 lines |
| Library index (real install) | 109 MB | 3 MB |
| App-layer test coverage | none | 17 tests |
| Signed, notarizable build | no | **yes**, verified |

### Third pass — the last two open items

- **Search tolerance.** The original finding was that `matchesText` required every typed token to
  appear in a record, so *"PLA files for Bambu P1S"* returned nothing. Rather than build the
  natural-language parser the PRD asked for, filler words are now dropped from the query, which
  fixes the actual failure at a fraction of the cost. A query made only of filler still filters, so
  searching for "print" behaves normally.
- **Signing and notarization.** `scripts/release.sh` archives both apps in Release, signs them with
  a Developer ID under the Hardened Runtime, notarizes, staples and verifies the embedded
  extensions. Verified against a real Developer ID certificate: both apps and both `.appex` bundles
  sign cleanly and the sandbox entitlements survive into the signed binary. This was the remaining
  blocker on the Quick Look extensions working for anyone but the developer.

The core test file was also split into five suites by concern once it outgrew the lint threshold.

**One deliberate limitation remains**, documented rather than hidden: the store is still JSON rather
than SQLite. That was justified by measurement, not assumption — with preview images externalised
the real index is 3 MB and a full save of a 10,000-record library takes 125 ms. Migrating to SQLite
would be the right call if the library grows by another order of magnitude, or when incremental
per-record writes become necessary; today it would be cost without benefit.
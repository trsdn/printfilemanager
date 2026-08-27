<!-- markdownlint-disable-file -->

# Task Research Notes: PrintFileManager QA/usability review

## Research Executed

### File Analysis

- `/Volumes/big/dev/printfilemanager/printfilemanager/README.md`
  - Declares current scope: local folder roots, recursive `.3mf` discovery, FSEvents watching, managed folder copy organization, search, smart collections, sorting, manual/generated tags, optional AI enrichment, delete-to-trash, and managed organization that preserves originals for copy mode.
- `/Volumes/big/dev/printfilemanager/printfilemanager/project.yml`
  - XcodeGen project targets Swift 6/macOS 15; app target depends on `PrintFileManagerCore`; tests only cover `PrintFileManagerCoreTests`.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerApp/PrintFileManagerApp.swift`
  - App defines a single main SwiftUI window, injects `LibraryViewModel` and `AISettingsStore`, loads the library on task, exposes Library menu commands for Add Folder and Rescan All, and provides Settings.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerApp/ContentView.swift`
  - Primary workflow surface uses `NavigationSplitView` with sidebar collections/folders, grid browser, and file inspector. UI controls exist for add folder, rescan, search, sort, select, open, Bambu Studio open, auto sort copy/move, trash, tags, AI enrichment, source lookup, project/source fields, notes, print history, preview mode, and raw metadata.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerApp/LibraryViewModel.swift`
  - Implements folder panels, managed folder setup, scan/rescan, smart collection/root/record selection, tag updates, notes, AI enrichment plus source lookup, source lookup alone, domain/source field editing, print history, default/Bambu open, delete-to-trash, organization planning, and organization execution.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerApp/SettingsView.swift`
  - Settings UI covers endpoint URL, API key, thumbnail inclusion, model loading, model selection, and enabled model toggles.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerApp/AISettingsStore.swift`
  - Persists endpoint/model/include-thumbnail/offered-model state in `UserDefaults`; stores non-empty API key in Keychain; builds optional `AIEnrichmentSettings` only when endpoint URL and selected model are valid.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerApp/FolderWatcher.swift`
  - Uses FSEvents for available watched roots with 800 ms debounce before rescanning the changed root.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerCore/LibraryModels.swift`
  - Defines roots, print records, generated tags, source info, print details/history, smart collections, organization actions/plans, sort options, and `LibraryQuery`.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerCore/LibrarySearch.swift`
  - Search filters by root, smart collection, selected tags, and full-text fields, then sorts by name/date/indexed date/file size/preview status.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerCore/LibraryDatabase.swift`
  - JSON-backed library index under Application Support; scan merge preserves user tags, accepted/generated tags, notes, project/source domain fields, print details, and print history while marking absent files as missing.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerCore/LibraryIndexer.swift`
  - Recursively indexes regular `.3mf` files, extracts preview/metadata/domain fields, hashes files, suggests local tags, marks metadata failures as indexing failures, and reports missing/unavailable roots through merge.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerCore/OrganizationPlanner.swift`
  - Plans copy/move actions to a managed folder using fallback category/project/file structure or sanitized AI-suggested relative paths; skips same-path records and executes copy/move on disk.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerCore/AIEnrichmentClient.swift`
  - Supports OpenAI-compatible models and chat completion endpoints, optional thumbnail payloads, retry without thumbnail on HTTP error, AI enrichment parsing, organization suggestion prompts, and AI-assisted source candidate choice.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Sources/PrintFileManagerCore/SourceLookupClient.swift`
  - Performs source lookup via existing source URL or DuckDuckGo HTML search, parses likely model source URLs and page metadata, and computes source version status.
- `/Volumes/big/dev/printfilemanager/printfilemanager/Tests/PrintFileManagerCoreTests/PrintFileManagerCoreTests.swift`
  - Contains 26 unit tests covering core indexing/metadata/preview extraction, local tag suppression, database merge preservation, search/root filtering/duplicate collection, AI URL/request/parsing helpers, source lookup parsing/version status, default smart collection sorts, plate/mesh extractors, and organization planner copy/move/re-sort cases.

### Code Search Results

- `selectedTags|allTags|prepareMove|prepareCopy|requestDelete|updateNotes|addPrintHistory|lookupSource|enrich\(`
  - Found `LibraryQuery.selectedTags` and `LibrarySearch.matchesTags`, but `LibraryViewModel.filteredRecords` always passes `selectedTags: []`; no UI binding uses `allTags`. Tag creation exists, but tag browsing/filtering is not exposed.
- `Button\(|TextField\(|Picker\(|Toggle\(|contextMenu|keyboardShortcut|CommandMenu`
  - Verified workflow controls: toolbar add/rescan/open/Bambu/move/delete, sidebar smart collections/folders/auto sort target/copy/move, search/sort controls, tile context menu, inspector edit sections, preview mode picker, Library menu shortcuts, and Settings form.
- `func test[A-Za-z0-9_]+`
  - Found 26 tests, all in core test target; no app/UI/ViewModel/Settings/FolderWatcher tests found.
- `func (addFolderFromPanel|setManagedFolderFromPanel|rescanAllRoots|scan|select|enrich|lookupSource|prepareOrganizationPlan|executeOrganizationPlan|openInDefaultApp|openInBambuStudio|moveDeleteCandidateToTrash|updateNotes|addPrintHistoryEntry|removePrintHistoryEntry)`
  - Verified that requested user workflows map to `LibraryViewModel` methods except a distinct user-facing “re-sort” command; re-sort is represented by moving managed-folder files to newly planned destinations through the same auto sort move path.
- `TODO|FIXME|re-sort|resort|Auto Sort|Move|Copy|Trash|Settings`
  - No source `TODO`/`FIXME` relevant to requested workflows. Search confirmed user-facing labels for Auto Sort Copy/Move, trash confirmation, and Settings.
- Editor diagnostics
  - `get_errors` returned no errors for `/Volumes/big/dev/printfilemanager/printfilemanager`.
- Symbol usage trace: `selectedTags`, `prepareOrganizationPlan`
  - VS Code usage provider was unavailable for Swift in this workspace; direct search/read evidence was used instead.

### External Research

- #githubRepo:"Not applicable"
  - No external repository research used; review is based on local source, tests, project metadata, and diagnostics.
- #fetch:Not applicable
  - No web fetch required; user requested a local read-only QA/usability review.

### Project Conventions

- Standards referenced: No `.github/instructions/` or `copilot/` convention files found in workspace. Local README/project.yml define Swift 6, macOS 15, XcodeGen, Xcode build/test commands, and current product scope.
- Instructions followed: Source and configuration files in `/Volumes/big/dev/printfilemanager/printfilemanager` were not edited. Only this research note under `.copilot-tracking/research/` was created/updated, as required by Task Researcher mode.
- UI review lens referenced: local `macos-ui-review` skill checklist emphasized macOS navigation, platform controls, context menus, keyboard navigation, accessibility, and workflow responsiveness.

## Key Discoveries

### Project Structure

The workspace contains a focused macOS SwiftUI app in `/printfilemanager` and a related Quick Look project in `/Quicklook`. The requested review scope is `/printfilemanager`, whose app target is split into `PrintFileManagerApp` for SwiftUI/state/settings and `PrintFileManagerCore` for indexing, search, persistence, AI/source lookup, and organization planning. The only test target is `PrintFileManagerCoreTests`, so automated coverage is deliberately lower at the app workflow layer than at the pure core layer.

### Implementation Patterns

- User workflows are state-driven through a single `LibraryViewModel` injected into SwiftUI views.
- Persistence is local JSON via `LibraryDatabase.applicationSupport()` at `Application Support/Print File Manager/library-index.json`.
- Scans are asynchronous and detached from the main actor, then merged back into the current snapshot.
- Search is recomputed from the current snapshot and query state rather than stored as a separate index.
- Smart collections are fixed enum cases with default sort behavior.
- Organization is review-before-execute: UI opens an `OrganizationPlanSheet`, shows up to 80 planned actions, then executes copy or move.
- AI is optional: enrichment controls are disabled unless endpoint/model settings are valid, while source lookup can run with or without AI settings.
- Copy mode preserves originals; move mode updates records immediately and then triggers managed-folder rescan.
- Destructive delete is confirmed and uses macOS Trash through `NSWorkspace.recycle`.

### Complete Examples

```swift
// Source: Sources/PrintFileManagerApp/LibraryViewModel.swift
var filteredRecords: [PrintFileRecord] {
    search.records(
        in: snapshot,
        matching: LibraryQuery(
            text: searchText,
            smartCollection: selectedCollection,
            rootID: selectedRootID,
            selectedTags: [],
            sortOption: sortOption,
            sortAscending: sortAscending
        )
    )
}

func prepareMovePlan(for record: PrintFileRecord, settings: AIEnrichmentSettings? = nil) {
    prepareOrganizationPlan(records: [record], kind: .move, settings: settings)
}

func executeOrganizationPlan(_ plan: OrganizationPlan) {
    isOrganizing = true
    let isMovePlan = plan.actions.contains { $0.kind == .move }
    statusMessage = isMovePlan ? "Moving files into managed library" : "Copying files into managed library"
    // Executes off-main-thread, applies moved records, then scans managed root.
}
```

### API and Schema Documentation

- `SmartCollection`: all, recentlyAdded, latestEdited, untagged, missingPreview, indexingErrors, duplicateCandidates.
- `SortOption`: name, modifiedDate, indexedDate, fileSize, previewStatus.
- `PrintFileRecord`: carries file identity/path/hash/status, thumbnail, project/domain fields, source info, print details, print history, user tags, generated tags, notes, and raw metadata.
- `OrganizationActionKind`: copy or move.
- `AIEnrichmentSettings`: endpoint URL, API key, model, includeThumbnail.
- `SourceVersionStatus`: current, possibleUpdateAvailable, unknown.

### Configuration Examples

```yaml
name: PrintFileManager
options:
  bundleIdPrefix: com.printfilemanager
  deploymentTarget:
    macOS: "15.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "15.0"
targets:
  PrintFileManager:
    type: application
    platform: macOS
  PrintFileManagerCoreTests:
    type: bundle.unit-test
    platform: macOS
```

### Technical Requirements

- Manual QA must use real `.3mf` files with at least: valid Bambu/MakerWorld preview plates, no preview, malformed/unreadable package, duplicate content, missing/deleted file after scan, nested folder path, and a file already inside the managed folder.
- AI/source tests should cover both configured OpenAI-compatible endpoint behavior and unconfigured/local deterministic source lookup failure states.
- Destructive workflows require disposable test directories because copy/move/trash operations mutate filesystem state.
- App workflow coverage needs UI automation or ViewModel tests because current test target does not exercise SwiftUI controls, panel flows, async status state, or settings persistence.

## Recommended Approach

Use a workflow-first QA pass: verify each implemented end-to-end path manually on disposable folders, then add automated tests at the lowest layer that can make failures deterministic. Core behavior already has meaningful unit coverage; the largest risk is the untested app workflow layer where SwiftUI controls, selection state, asynchronous ViewModel updates, settings persistence, and destructive file operations meet real user expectations.

Single recommended testing direction: keep existing core unit tests, add focused `LibraryViewModel` tests with an injectable temporary database and small fixture `.3mf` packages, then add a thin XCUITest smoke suite for critical UI journeys: add folder, search/select/edit metadata, auto sort plan review, trash confirmation, and settings model loading failure/success states. Avoid building broad snapshot/UI tests first; the workflows depend more on state transitions and filesystem effects than visual rendering.

## Implementation Guidance

- **Objectives**: Validate add folder, scan, search, smart collections, selection, tags, AI enrichment, source lookup, auto sort copy/move/re-sort, open in apps, trash, notes, print history, and settings from user workflow perspective.
- **Key Tasks**: Run manual checklist with disposable fixtures; add ViewModel tests for stateful workflows; add UI smoke tests for panels/dialogs/selection; add filesystem tests for trash/open/managed re-sort with test doubles where system APIs prevent deterministic assertions.
- **Dependencies**: Temporary library index/database injection, fixture `.3mf` packages, optional local OpenAI-compatible endpoint mock, deterministic source lookup/mocked URL loading, disposable managed folder, Bambu Studio presence/absence handling.
- **Success Criteria**: Manual QA confirms each user-visible workflow; automated tests fail when a workflow control stops updating state/persistence/filesystem as expected; usability defects below are triaged before broader feature expansion.
# App Review: Print File Manager

Date: 2026-05-03

## Review Goal

Review the application from a user-first perspective for local 3MF print-file management. The target user has many downloaded or self-configured `.3mf` files and wants to find the right file again by model, source, printer, material, print profile, version, and readiness without manually opening every file in a slicer.

## Review Inputs

- Existing PRD: `docs/prd-3mf-library-manager.md`
- App code under `printfilemanager/Sources`
- Core tests under `printfilemanager/Tests`
- Additional read-only reviews from code inventory, product/UX, and QA/usability perspectives

## Implementation Update: 2026-05-04

- Added a first-class `Needs Review` smart collection.
- Added faceted filters for printability, tags, materials, printers, source platforms, and source version status.
- Made selected bulk actions clearer with visible selected counts and explicit copy/move labels.
- Improved organization plan wording so copy keeps originals clear and move/re-sort changing locations is explicit.
- Added core regression tests for the new filter behavior and `Needs Review` logic.
- Added explicit per-file review reasons in the grid and inspector.
- Added reviewed/reopen state based on a review signature, so current review items can be dismissed and new issues reappear automatically.

## Current User-Facing Functions

### Library and Scanning

- Add Finder folders as library roots.
- Set a managed library target folder.
- Recursively scan `.3mf` files.
- Watch roots with file-system events.
- Rescan one folder or all roots.
- Show root counts and filter the library by scanned folder.
- Persist the library index under Application Support.
- Preserve user tags and notes across rescans.

### Search and Browsing

- Browse files in a visual grid.
- Search across file name, relative path, project name, category, printability, source info, notes, tags, print details, print history, and raw metadata.
- Sort by name, modified date, indexed date, file size, and preview status.
- Use smart collections for all files, recently added, latest edited, untagged, missing preview, indexing errors, and duplicate candidates.

### Preview and Inspection

- Show thumbnail previews from embedded package images.
- Show Bambu/MakerWorld plate previews where available.
- Show a basic 3D SceneKit preview where mesh extraction succeeds.
- Display project/category/variant/printability metadata.
- Display print details such as plates, objects, build items, materials, colors, slicer, printer, nozzle, layer height, time, and filament when available.
- Display raw package metadata behind a disclosure control.

### Tagging and Notes

- Add and remove user tags.
- Accept or reject suggested tags.
- Suppress broad metadata tags such as `3mf`, `bambu`, `makerworld`, and `multi-plate`.
- Add notes that are included in search.
- Add/remove print-history entries with printer, material, result, and notes.

### AI Enrichment and Source Lookup

- Configure an OpenAI-compatible endpoint, model, optional API key, and thumbnail inclusion.
- Load available models from the configured endpoint.
- Enrich individual files with AI description, tags, category, variant, printability, materials, workflow notes, and source hints.
- Allow blank API keys for local endpoints.
- Fallback from thumbnail payloads to text-only payloads when a provider rejects the thumbnail form.
- Find source pages from embedded URLs or web search.
- Display source URL, title, description, updated/checked date, and version status where available.

### Organization and File Operations

- Open a file in the default app.
- Open a file in Bambu Studio when installed, with default-app fallback.
- Move files to macOS Trash after confirmation.
- Auto Sort Copy and Auto Sort Move selected files into a managed folder.
- Use AI-assisted organization with a relative target path and rationale.
- Pass existing managed-library folders to AI so matching folders are reused.
- Re-sort files that are already inside the managed folder.
- Skip no-op organization results where the file is already at the proposed target path.
- Review planned copy/move actions before execution.

## Core User Journeys

1. Add a Downloads folder, scan it, and see all 3MF files with previews and searchable metadata.
2. Search for a configured file by model name, printer, material, slicer, tag, source, or note.
3. Inspect a file to answer: What is this? Is it print-ready? Which printer/material/profile does it target? Where did it come from?
4. Enrich a file with AI when local metadata is incomplete.
5. Find the source page and check whether a newer source version may exist.
6. Select one or more files and review an AI-assisted Auto Sort plan before copying or moving.
7. Re-run Auto Sort on already-managed files to clean up an older or poor folder structure.
8. Mark important context manually through tags, notes, and print-history entries.
9. Identify duplicate candidates and avoid deleting useful variants accidentally.
10. Recover from bad files, missing roots, or failed operations without losing metadata.

## Findings

### P0: Make Print Readiness More Explicit

The app extracts printer/material/profile hints, but the UI does not yet make readiness the central concept. A user needs a simple answer: ready to print, needs metadata, generic/unconfigured, duplicate candidate, source update available, or unreadable.

Recommendation: add a normalized readiness/status field and make it visible in the grid, inspector, and saved views.

### P0: Make Copy, Move, and Re-Sort Safer to Understand

Auto Sort Copy, Auto Sort Move, toolbar Move, tile Move, and context-menu actions are functional but easy to misunderstand. This matters because Move changes the source path.

Recommendation: show selected count next to bulk actions, use explicit labels such as `Copy into Managed Library`, `Move into Managed Library`, and `Re-sort Managed Files`, and make the plan summary explain whether originals remain.

### P0: Add ViewModel and UI Workflow Tests

Core tests are strong, but no tests exercise the app-level workflows: selection, notes, tags, print history, source lookup state, async status messages, delete candidate flow, or organization plan execution through the view model.

Recommendation: add `LibraryViewModel` tests with a temporary database and fixture files, then add a thin XCUITest smoke suite.

### P1: Expose Tag and Metadata Filters

Implemented in the first follow-up slice. The app now exposes filters for printability, tags, materials, printers, source platforms, and source version status.

Remaining recommendation: add persisted filter presets only if repeated workflows make them useful.

### P1: Separate Review Queues From Raw Smart Collections

Implemented in follow-up slices. The app now has a `Needs Review` smart collection for missing source, missing printer/material, possible update, unreadable/missing files, duplicate candidates, missing previews, and pending generated tags. Files show explicit review reasons in the grid/inspector and can be marked reviewed or reopened.

Remaining recommendation: add duplicate-cluster-level review, not only file-level review.

### P1: Make Source Lookup Privacy and Confidence Clearer

Source lookup is useful, but web search can disclose model names to a search provider. Current UI says `Find`, but not what will be queried or how confident the match is.

Recommendation: show search query, matched host, confidence, and last checked date; add a setting to disable web source lookup separately from local AI enrichment.

### P1: Improve Root and Scan Management

Roots can be added and rescanned, but there is no visible remove-root or reveal-root action. Concurrent scans share one Boolean status.

Recommendation: add root context actions and per-root scan state.

### P2: Improve Batch Execution Reporting

Organization execution is sequential. A mid-batch failure can leave partial results with only a global status message.

Recommendation: record a per-action result report and show success, skipped, failed, and recovery guidance after execution.

### P2: Improve Duplicate Explanation

Duplicate candidates currently rely on content hashes. That is safe for exact duplicates but does not explain similar variants.

Recommendation: keep exact-hash duplicates for MVP safety, but add explanation text and later expand to source/title/profile similarity.

## Manual Test Checklist

Use a disposable test library containing: a Bambu/MakerWorld 3MF with plates, a no-preview 3MF, a malformed 3MF, duplicate-content files, nested folders, a missing-after-scan file, and a file already inside the managed folder.

### Folder and Scan

- Add a folder from empty state.
- Verify nested discovery and root count.
- Rescan one root.
- Rescan all roots.
- Add/remove a file in Finder and verify watcher behavior.
- Temporarily make a root unavailable and verify metadata is not silently deleted.

### Search and Smart Views

- Search by file name, project name, folder path, tag, note, source URL, printer, material, and print-history text.
- Verify each smart collection count and default sort.
- Verify sort order for name, modified date, indexed date, file size, and preview status.

### Selection and Bulk Actions

- Single-select a tile.
- Command-click multi-select.
- Switch sidebar views and verify selection clears.
- Verify Auto Sort uses only selected visible files.
- Verify selected count is understandable.

### Preview and Inspector

- Verify thumbnail, plate preview, 3D preview, fallback preview, and malformed package behavior.
- Verify print details display printer/material/profile hints where present.
- Verify raw metadata remains behind disclosure.

### Tags, Notes, and Print History

- Add/remove tags.
- Accept/reject AI/local suggestions.
- Confirm broad tags are suppressed.
- Add notes and verify persistence/search.
- Add/remove print-history entries and verify search.

### AI and Source

- Verify unconfigured AI disables Enrich.
- Load local models with a blank API key.
- Enrich with thumbnail enabled and disabled.
- Verify provider error messages are visible.
- Find source from an embedded URL.
- Find source through search when no URL is embedded.
- Verify source description, URL, version status, confidence, and checked time.

### Organization

- Set a managed folder.
- Auto Sort Copy one file and multiple files.
- Auto Sort Move one file and multiple files.
- Re-sort a file already inside the managed folder.
- Verify same-path suggestions are skipped.
- Verify existing folder names are reused and near-variants are not created.
- Cancel a plan and confirm no file operation happened.
- Execute a plan and verify filesystem plus library index.

### File Operations and Settings

- Open in default app.
- Open in Bambu Studio and verify fallback if missing.
- Move to Trash, cancel, and confirm.
- Verify Settings persistence for endpoint, model, thumbnail toggle, and API key behavior.

## Automated Coverage Summary

Covered today by core tests:

- Indexing and metadata extraction.
- Preview extraction and mesh extraction.
- Database merge preserving user annotations.
- Search, smart collection sorting, and root filtering.
- AI endpoint normalization and payload parsing.
- AI tag suppression.
- AI organization parsing and existing-folder context.
- Source lookup parsing and version-status detection.
- Organization copy/move/re-sort/no-op behavior.

Known coverage gaps:

- `LibraryViewModel` workflow tests.
- SwiftUI or XCUITest smoke coverage.
- FolderWatcher/FSEvents behavior.
- Keychain persistence edge cases.
- Source lookup network failure and privacy-setting behavior.
- Per-root scan state and unavailable volume recovery.
- Large-library performance.

## Recommended Next Implementation Slices

1. Add `LibraryViewModel` tests for core user workflows.
2. Add source lookup confidence/provenance display and privacy setting.
3. Add root management actions: reveal, remove, rescan, unavailable recovery.
4. Add post-organization result reports.
5. Add duplicate-cluster-level review and explanation.
6. Add thin macOS UI smoke tests for scan, filter, select, inspect, and plan-review workflows.

## Non-Goals For Now

- Slicer replacement.
- Mesh editing or repair.
- Printer control or print submission.
- Marketplace browsing/downloading as a primary workflow.
- Automatic deletion of duplicates.
- Account system, cloud sync, or multi-user collaboration.
- Generic AI chat as the primary interface.

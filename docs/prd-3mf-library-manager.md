# PRD: Local 3MF Library Manager for macOS

## Executive Summary

- Problem Statement: Users with large collections of downloaded `.3mf` print files cannot reliably search, identify, tag, sort, or keep them organized from Finder alone. File names are often inconsistent, embedded project data is hidden, and manually opening or sorting each file is too slow.
- Proposed Solution: Build a local macOS application that lets the user add or watch Finder folders, indexes `.3mf` files into an internal database, extracts available project metadata and preview images, generates missing previews where possible, and provides search, tagging, smart collections, and optional AI-assisted enrichment through a user-configured AI-compatible API.
- Success Criteria: A user can point the app at one or more existing 3MF folders and, without manually opening files one by one, find relevant models by name, metadata, tags, visual preview, and generated descriptions; identify duplicates or near-duplicates; and organize files through safe, reviewable actions.

## Problem Statement

3D printing users often accumulate many `.3mf` files from MakerWorld, Bambu Studio, Printables, GitHub, private projects, and ad hoc downloads. These files are valuable because they may contain print settings, plate layouts, material choices, support settings, and project-specific metadata. Throwing them away is undesirable, but managing them manually becomes painful once the collection grows.

The current Finder-based workflow has several problems:

- File names are inconsistent, generic, duplicated, truncated, or source-specific.
- Important project information is inside the `.3mf` package and not visible in Finder.
- Preview images may exist but are not consistently available as Finder thumbnails.
- Similar models are hard to distinguish without opening each file in Bambu Studio or another slicer.
- Manual folder sorting does not scale for hundreds or thousands of files.
- Users need both fast search and confidence that files, settings, and original packages are not destroyed.

The core user problem is: "I have many 3MF files that I want to keep, but I need the computer to help me understand, tag, search, and organize them."

## Solution

Create a native macOS library manager for `.3mf` files. The app allows the user to select one or more Finder folders as library roots. The app watches those folders, indexes discovered `.3mf` files, stores extracted metadata in an internal local database, and presents a searchable, visual catalog.

The application provides:

- Folder onboarding for one-time scans and continuously watched folders.
- A local database of indexed files, extracted metadata, thumbnails, generated descriptions, tags, and organization state.
- 3MF metadata extraction for project information, plate names, embedded thumbnails, print settings where available, file names, source hints, and package structure.
- Preview generation using embedded preview images first, then a fallback renderer or placeholder strategy where no usable preview exists.
- Search across file names, folders, extracted metadata, generated captions, user tags, AI-suggested tags, and notes.
- Manual and suggested tagging.
- Smart collections for common organization patterns such as printer, material, source, project type, modification date, duplicate candidates, missing preview, missing tags, or recently downloaded files.
- Safe organization actions such as move, copy, rename, tag, or assign to collection, with preview and undo where feasible.
- Optional AI-assisted enrichment through a user-configured OpenAI-compatible or otherwise AI-compatible API endpoint.

The product should treat original `.3mf` files as valuable source artifacts. The default behavior must be non-destructive: index, annotate, and suggest first; modify or move files only after explicit user confirmation.

## User Stories

1. As a 3D-printing user, I want to add a Finder folder to the app, so that my existing `.3mf` collection can be indexed without moving files first.
2. As a 3D-printing user, I want the app to watch selected folders, so that new downloads appear in the library automatically.
3. As a user with many downloads, I want the app to find `.3mf` files recursively, so that nested folder structures are included.
4. As a user with private print files, I want indexing to happen locally by default, so that my files are not uploaded without my explicit decision.
5. As a user organizing files, I want to see a visual grid of `.3mf` files, so that I can recognize models faster than by file name alone.
6. As a user comparing similar models, I want large previews and metadata side by side, so that I can decide which file to keep or move.
7. As a user with inconsistent file names, I want search to include extracted project names and plate names, so that I can find files even when the Finder name is poor.
8. As a user with Bambu Studio projects, I want the app to index available print settings, so that I can search by printer, filament, nozzle, plate, or process hints where those values exist.
9. As a user with many model types, I want to add my own tags, so that I can organize files by my own mental categories.
10. As a user who does not want to tag everything manually, I want suggested tags, so that the app can do most of the repetitive classification work.
11. As a user reviewing AI suggestions, I want to accept, reject, or edit suggested tags, so that the final library stays trustworthy.
12. As a user searching for a model, I want full-text search across file names, folder names, extracted metadata, notes, captions, and tags, so that search works even when I remember only a fragment.
13. As a user looking for visual content, I want generated captions or descriptions from previews where enabled, so that I can search for concepts such as "cable holder", "drawer insert", or "phone stand".
14. As a user with preview-less files, I want the app to generate or derive a useful preview when possible, so that visually browsing the library remains useful.
15. As a user with files from different sources, I want source detection hints, so that I can tell whether something likely came from MakerWorld, Printables, GitHub, my own slicer export, or an unknown source.
16. As a user who wants to clean up downloads, I want duplicate and near-duplicate candidates, so that I can reduce clutter without accidentally deleting valuable files.
17. As a user who cares about preserving settings, I want duplicate detection to distinguish identical files from similar models with different print settings, so that I do not lose important variants.
18. As a user organizing a folder, I want smart collections for untagged files, missing previews, recently added files, and probable duplicates, so that I can focus cleanup work where it matters.
19. As a user who wants automatic sorting, I want the app to propose target folders or collections, so that I can approve organization in batches.
20. As a cautious user, I want to preview all move, rename, and copy operations before they happen, so that the app does not silently destroy my folder structure.
21. As a cautious user, I want undo or a reversible operation log for organization actions, so that mistakes can be corrected.
22. As a user with a large library, I want indexing to run incrementally in the background, so that the app remains usable during scans.
23. As a user with external drives or network folders, I want the app to handle temporarily unavailable roots gracefully, so that the database does not lose metadata when a volume is disconnected.
24. As a user with malformed files, I want the app to mark files as unreadable without crashing, so that one bad package does not block the whole library.
25. As a user managing storage, I want file size and last modified date indexed, so that I can find unusually large or old files.
26. As a user who sometimes knows what a file is, I want to add notes, so that personal context remains searchable.
27. As a user who wants privacy control, I want AI enrichment to be disabled by default, so that no data leaves my Mac unless I opt in.
28. As a user enabling AI enrichment, I want to choose the provider and endpoint, so that I can use a local model, OpenAI-compatible service, Azure OpenAI, or another compatible API.
29. As a user enabling AI enrichment, I want to know what is sent to the model, so that I can make an informed privacy decision.
30. As a user with limited API budget, I want AI enrichment to be queued, rate-limited, and optional per folder or file, so that I can control cost.
31. As a user with sensitive designs, I want to exclude folders or files from AI enrichment, so that private models remain fully local.
32. As a user maintaining the library, I want clear status indicators for indexed, pending, failed, enriched, and stale files, so that I can trust the catalog.
33. As a user who edits files outside the app, I want changed files to be re-indexed, so that the database stays current.
34. As a user who moves files in Finder, I want the app to detect moved or missing files where possible, so that metadata is not duplicated unnecessarily.
35. As a developer, I want parsing, indexing, preview generation, search, and AI enrichment separated into testable modules, so that behavior can be validated without relying on the macOS UI.
36. As a user with configured print projects, I want to know which printer, material, nozzle, layer height, slicer, and profile hints are inside a `.3mf`, so that I can find the right print-ready file without reopening many candidates.
37. As a user, I want to distinguish original downloaded source files from my tuned print-ready variants, so that I do not overwrite or delete the wrong artifact.
38. As a user, I want to search for files by printer, material, print profile, plate count, source, source version, and readiness, so that I can answer "can I print this now?" quickly.
39. As a user, I want a clear readiness status such as ready, needs metadata, needs review, duplicate candidate, unreadable, or source update available, so that I know where to focus cleanup work.
40. As a user with files from MakerWorld, Printables, Thingiverse, Cults, GitHub, and local exports, I want source lookup to find and display the likely original URL, model description, author, license, and version status where possible.
41. As a user, I want source lookup to show confidence and provenance, so that I can judge whether the matched source page is trustworthy.
42. As a user, I want to check whether a source page appears newer than my local file, so that I can decide whether to download an updated model.
43. As a user, I want automatic organization to consider the existing managed-library folder structure, so that it reuses good folders instead of creating small naming variants.
44. As a user, I want to re-run AI Auto Sort on files that are already in the managed folder, so that older or poorly sorted files can be moved into a better structure.
45. As a user, I want the app to skip files that are already at the proposed target path, so that re-sorting does not create duplicate `2` files.
46. As a user, I want a first-class review queue for files that need attention, such as missing source, missing printer/material, unreadable package, duplicate candidate, or possible source update.
47. As a user, I want duplicate detection to explain why files are grouped, such as exact hash match, same source URL, similar title, or similar print profile, so that I can decide safely.
48. As a user, I want to filter by tags directly, not only by typing tag names into search, so that tagging becomes a fast browsing workflow.
49. As a user, I want visible selected count and bulk action context, so that I know exactly which files Auto Sort, AI enrichment, or other batch actions will affect.
50. As a user, I want Copy and Move actions to be visually and verbally distinct, so that I understand whether originals will remain in place.
51. As a user, I want per-root scan progress and root management, so that I can rescan, reveal, remove, or recover a folder without guessing what the app is doing.
52. As a user, I want source lookup and AI enrichment to explain network activity, so that I understand what query or metadata may leave my Mac.
53. As a user, I want AI suggestions to include a reason and confidence where possible, so that the app feels intelligent but still reviewable.
54. As a user, I want natural-language search such as "PLA files for Bambu P1S" or "PETG files with unknown source", so that I do not need to remember the exact metadata field names.
55. As a user, I want to mark a file or duplicate cluster as reviewed, so that the app stops surfacing it as unfinished work.
56. As a user, I want failed batch operations to produce a clear result report, so that I can recover from partial moves or copies.

## Acceptance Criteria

- The user can add at least one Finder folder as a library root.
- The app can recursively discover `.3mf` files in selected library roots.
- The app can watch selected folders and detect newly added, modified, removed, or renamed `.3mf` files.
- The app stores indexed file records in a local internal database.
- The app indexes at minimum: canonical file path, file name, file size, modification date, file hash or stable identity, indexing status, preview status, user tags, generated tags, notes, and extracted project metadata where available.
- The app extracts embedded preview images from supported Bambu/MakerWorld-style `.3mf` files.
- The app generates a thumbnail record for files with supported embedded previews.
- Files without usable embedded previews receive a clear fallback preview state and remain searchable.
- The app provides full-text search across file names, folder paths, extracted metadata, tags, notes, and generated descriptions.
- The app supports manual tag creation, editing, assignment, and removal.
- The app supports AI-suggested tags and descriptions when AI enrichment is enabled.
- AI enrichment is disabled by default.
- AI enrichment requires explicit configuration of a provider or endpoint before any request is made.
- The app shows or documents what data will be sent to the AI provider before enrichment is enabled.
- The default AI enrichment payload must avoid uploading the full `.3mf` file; it should use extracted preview images, file names, and selected metadata unless the user explicitly opts into broader payloads in a later release.
- The app can display a grid or list of indexed files with thumbnail, name, tags, status, and key metadata.
- The app can display a detail view for a selected file with preview, metadata, tags, notes, source path, and indexing/enrichment state.
- The app provides smart collections for at least: recently added, untagged, missing preview, indexing errors, and duplicate candidates.
- The app exposes common filters for printer, material, profile/readiness, source platform, source version status, tags, and review status once those fields are indexed.
- The app displays normalized print details where available, including printer, material, color, slicer, nozzle, layer height, plate count, and print-time hints.
- The app can show source lookup results, including source URL, title/description, author/license where available, lookup confidence, check time, and version/update status.
- The app can propose organization actions such as move, copy, rename, or collection assignment.
- Destructive or file-moving actions require a review step before execution.
- Organization actions must preserve original `.3mf` files unless the user explicitly confirms otherwise.
- AI-assisted organization must receive the existing managed-library folder structure and should reuse matching folders instead of creating near-duplicates.
- Auto Sort must support re-sorting files that are already inside the managed folder.
- Auto Sort must skip exact no-op destinations instead of creating duplicate file names.
- Copy and Move workflows must clearly communicate whether the original file remains in place.
- The app records organization actions sufficiently to support an undo path or clear manual recovery instructions.
- The app handles unavailable folders or volumes without deleting indexed metadata automatically.
- Malformed or unreadable `.3mf` files are marked with an error state and do not crash indexing.
- A first usable version can handle at least 1,000 `.3mf` files in a library without blocking basic browsing and search.
- Core indexing and search operations are covered by automated tests.

## Implementation Decisions

- Build this as a native macOS application that complements the Quick Look preview feature rather than replacing it.
- Treat the app as the system of record for organization metadata, while treating original `.3mf` files as read-only by default.
- Use a local database for the library index. SQLite is the preferred default because it is local, durable, queryable, and well suited for full-text search.
- Model folders as library roots with scan mode, watch mode, last scan status, availability state, and user preferences.
- Model files as indexed assets with stable identity, current path, metadata extraction state, preview state, enrichment state, and organization state.
- Keep user annotations separate from extracted file metadata so that re-indexing does not overwrite user work.
- Implement a 3MF container reader that can inspect `.3mf` packages safely and read-only.
- Implement source-specific extractors for Bambu/MakerWorld metadata first, while leaving room for additional 3MF variants later.
- Reuse or share preview extraction logic with the Quick Look preview work where practical.
- Implement a thumbnail cache so that browsing does not repeatedly parse large archives.
- Implement incremental indexing with a background queue and cancellation support.
- Implement file watching using macOS file system events or an equivalent system API appropriate for watched folders.
- Implement search using local database full-text search, with structured filters for tags, status, dates, source folders, and metadata fields.
- Implement AI enrichment as an optional provider abstraction with a narrow interface: given selected local metadata and one or more preview images, return candidate tags, a short description, confidence, and optional structured attributes.
- Implement AI-assisted organization as a planner input, not an executor: AI may propose a relative path and rationale, while local code validates paths, reuses existing managed folders, resolves collisions, and requires user approval.
- Implement source lookup as a separate enrichment capability that can use existing embedded URLs, deterministic web search, page metadata extraction, and optional AI candidate selection.
- Normalize print profile fields into stable display/search fields where possible: printer, material, color, nozzle, layer height, slicer, plate count, and printability/readiness.
- Store AI-generated fields separately from user-approved fields.
- Require user confirmation before AI suggestions become accepted tags unless the user later enables an explicit auto-accept policy.
- Do not upload full `.3mf` packages for enrichment in the MVP.
- Do not modify `.3mf` package contents in the MVP.
- Do not delete files in the MVP; cleanup workflows should focus on identify, move, copy, tag, or mark as duplicate candidate.

Suggested high-level modules:

- Library Root Manager: adds, removes, scans, and watches user-selected folders.
- Indexing Pipeline: coordinates discovery, metadata extraction, preview extraction, thumbnail caching, and status updates.
- 3MF Metadata Extractor: reads package structure and extracts project information without modifying files.
- Preview Resolver: finds embedded previews and generates thumbnail assets or fallback states.
- Library Database: stores file records, metadata, tags, annotations, statuses, and action history.
- Search Service: provides full-text and faceted search over local indexed content.
- Tagging Service: manages user tags, generated tags, approval state, and bulk assignment.
- AI Enrichment Provider: calls user-configured AI-compatible APIs and normalizes returned descriptions and tags.
- Organization Planner: proposes move, copy, rename, and collection actions without executing them silently.
- Action Executor: performs confirmed file operations and records enough information for undo or recovery.
- macOS UI: provides folder onboarding, library grid/list, detail view, smart collections, search, filter controls, and review screens.

## Testing Decisions

Good tests should validate observable behavior: given a folder tree and a set of `.3mf` fixtures, the app discovers the expected files, extracts expected metadata, generates expected preview states, indexes searchable fields, and proposes organization actions without modifying files until confirmation. Tests should avoid coupling to private UI implementation details.

Modules explicitly in scope for automated tests:

- Library root scanning and recursive discovery.
- File identity and change detection.
- 3MF container reading.
- Bambu/MakerWorld metadata extraction.
- Preview resolution and fallback behavior.
- Database persistence and migration behavior.
- Full-text search and faceted filters.
- Tag creation, assignment, generated tag approval, and tag removal.
- AI enrichment provider contract using mocked provider responses.
- Source lookup parser and version-status behavior using mocked search and page responses.
- Organization planning and confirmed action execution.
- Re-sort behavior for files already inside the managed folder.
- View model behavior for selection, tag editing, notes, print history, source lookup, AI enrichment state, and organization status.
- Thin macOS UI smoke tests for add folder, search/select/edit, plan review, settings, and trash confirmation.

Test inputs should include:

- A supported Bambu/MakerWorld `.3mf` with embedded preview and metadata.
- A `.3mf` with multiple plates or project-level metadata.
- A valid `.3mf` without a supported preview.
- A malformed or unreadable `.3mf`.
- Duplicate files with identical hashes.
- Similar files with different print settings.
- Files in nested folders.
- Files on a simulated temporarily unavailable root where possible.
- A library large enough to validate incremental indexing and search performance assumptions.

Manual test coverage should include:

- Adding and removing library roots from the macOS UI.
- Watching a folder while files are added, changed, renamed, moved, or deleted in Finder.
- Reviewing and applying proposed organization actions.
- Enabling, using, and disabling AI enrichment.
- Verifying that no network request happens before AI enrichment is explicitly enabled.

## Out of Scope

- Editing `.3mf` package contents.
- Slicing models.
- Sending jobs to printers.
- Printer fleet management.
- Marketplace browsing or downloading models from external platforms.
- Automatic deletion of duplicate files.
- Cloud sync across Macs.
- Multi-user collaboration.
- App Store distribution decisions.
- Full generic support for every possible 3MF producer in the first release.
- 3D geometry rendering as the primary preview path unless a later technical spike proves it is necessary and tractable.
- Training a custom AI model.

## Risks and Rollout

Key risks:

- 3MF package structures vary by producer and version, especially outside Bambu/MakerWorld files.
- Some files may not contain useful metadata or preview images.
- AI-generated tags may be wrong, overly generic, or inconsistent without a review workflow.
- Uploading previews or metadata to an external AI provider creates privacy and trust concerns.
- Large libraries can make naive indexing, hashing, thumbnail generation, or UI rendering too slow.
- File watching can be unreliable across external drives, network mounts, cloud-synced folders, or moved directory trees.
- Duplicate detection must avoid treating different print-setting variants as safely disposable duplicates.
- Organization actions can damage user trust if moves, renames, or copies are hard to review or reverse.

Suggested rollout:

1. Build a local-only prototype that scans one selected folder and indexes filenames, paths, file size, modification dates, and extracted previews.
2. Add the local database, persistent library roots, incremental re-scan, and core search.
3. Add metadata extraction for Bambu/MakerWorld-style `.3mf` files.
4. Add manual tags, notes, smart collections, and duplicate candidate detection.
5. Add folder watching and background indexing.
6. Add safe organization proposals with review before file operations.
7. Add optional AI enrichment behind explicit configuration and consent.
8. Validate on a real library of at least 1,000 `.3mf` files before expanding scope.

## Security and Privacy

The application handles local model files that may contain copyrighted, proprietary, personal, or customer-specific designs. The default posture must be local-first and non-destructive.

Security and privacy requirements:

- Indexing, parsing, thumbnail extraction, tagging, and search run locally by default.
- No telemetry is collected in the MVP unless the user explicitly opts into a future diagnostics feature.
- AI enrichment is disabled by default.
- The user must explicitly configure and enable any AI provider before network calls occur.
- The app must clearly describe what will be sent to the AI provider, such as preview image, file name, selected metadata, or user notes.
- The MVP should not upload full `.3mf` packages for AI enrichment.
- The user can exclude folders or individual files from AI enrichment.
- API keys or credentials must be stored in the macOS Keychain or an equivalent secure local credential store.
- `.3mf` files must be treated as untrusted archives. The parser must avoid path traversal, arbitrary file writes, excessive memory use, and crashes from malformed packages.
- File operations must be explicit, reviewable, and recoverable where feasible.

## Further Notes

This product is broader than a Finder Quick Look extension. Quick Look helps answer "What is this file?" for a single selected file. The library manager helps answer "What do I have, how do I find it again, and how should I organize it?" across an entire collection.

The first version should optimize for trust: preserve files, make indexing transparent, keep AI optional, show confidence and source of generated metadata, and make organization actions reviewable before anything happens to the user's folder structure.

Open product decisions for later refinement:

- Whether the first UI should be grid-first, table-first, or split-view-first.
- Whether generated previews beyond embedded images require a true 3D render pipeline or a simpler placeholder strategy for the MVP.
- Whether AI enrichment should use only vision/captioning, text-only metadata, or both.
- Whether automatic sorting should physically move files or primarily use virtual collections in the first release.
- Which folder naming and rename templates should be offered for organization workflows.
- How prominent the review queue should be in the first screen.
- Whether source lookup should require explicit per-run confirmation or be controlled by a global privacy setting.
- Whether duplicate clusters should be exact-hash-only in the MVP or include source/geometry/profile similarity.
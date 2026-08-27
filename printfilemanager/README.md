# Print File Manager

Print File Manager is a native macOS app for building a local catalog of `.3mf` print files. It can add Finder folders as library roots, recursively index `.3mf` packages, extract Bambu/MakerWorld-style preview images, store searchable metadata, and manage user tags without modifying source files.

## Build

```bash
cd printfilemanager
xcodegen generate
xcodebuild -scheme PrintFileManager -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

## Test

```bash
cd printfilemanager
xcodebuild -scheme PrintFileManager -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

## Current Scope

- Local folder roots, recursive `.3mf` discovery, and FSEvents-based folder watching.
- Managed folder target for normalized, categorized library organization.
- Reviewable organize plans before files are copied or moved into the managed folder.
- AI-assisted Auto Sort that can reuse existing managed-folder structure and re-sort files already inside the managed folder.
- Local JSON-backed library index under Application Support.
- Preview extraction through the shared 3MF preview core.
- Plate preview navigation for Bambu/MakerWorld-style `Metadata/plate_*.png` images.
- Basic 3MF mesh extraction with a native SceneKit inspector preview.
- Metadata hints from package entries and 3MF XML metadata, including project, source, material, slicer, printer, nozzle, layer, and plate hints where present.
- Search, smart collections with counts, sorting, manual tags, generated local tag suggestions, and a `Needs Review` queue with explicit review reasons.
- Reviewed/reopen state for current review items; new or changed review issues reappear automatically.
- Faceted filters for printability, tags, material, printer, source platform, and source version status.
- Optional OpenAI-compatible AI enrichment configured in Application Settings. The app sends selected metadata and, if enabled, the preview image to the configured endpoint. API keys are stored in Keychain, and blank keys are supported for local endpoints.
- Source lookup for model pages and descriptions from embedded URLs or searched source pages, with best-effort version/update status.
- Editable source fields, project fields, notes, tags, and print-history entries.
- Confirmed delete action that moves selected files to the macOS Trash and removes them from the local index.
- No automatic unreviewed file moves, deletes, cloud sync, or telemetry yet.

See `../docs/app-review-2026-05-03-print-file-manager.md` for the current product/UX review and test checklist.
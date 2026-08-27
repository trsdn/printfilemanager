# PRD: macOS Finder Preview for Bambu/MakerWorld 3MF Files

## Executive Summary

- Problem Statement: `.3mf` files from Bambu Studio or MakerWorld are hard to identify in Finder because macOS does not show a useful preview or thumbnail by default. Users must open files in a slicer just to confirm whether a file is the right print file.
- Proposed Solution: Build a small standalone macOS app that ships Quick Look preview and Finder thumbnail extensions for `.3mf` files. The MVP extracts embedded preview images from Bambu/MakerWorld-style 3MF packages and shows them in Finder and Quick Look.
- Success Criteria: A user can select a `.3mf` file in Finder and, within about one second, visually confirm whether it is the intended file without opening Bambu Studio, a slicer, or a separate review tool.

## Problem Statement

Users who collect, download, or manage multiple Bambu/MakerWorld `.3mf` files cannot reliably recognize files from Finder alone. File names are often similar, shortened, or not descriptive enough. The current workflow requires opening each candidate file in Bambu Studio or another slicer, which is slow and interrupts file organization.

The core user problem is simple: "Is this the right file?" The Finder should answer that question directly through thumbnails and Quick Look.

## Solution

Create a lightweight standalone macOS application whose main purpose is to register Quick Look support for `.3mf` files. The app provides:

- Finder thumbnails for `.3mf` files.
- Quick Look previews when the user presses Space in Finder.
- Preview generation by reading embedded preview images from Bambu/MakerWorld `.3mf` files.
- A safe fallback to a standard icon and filename when no usable preview image exists.
- Fully local processing with no network calls and no telemetry.

The first release does not edit `.3mf` files, does not slice models, does not connect to printers, and does not render 3D geometry.

## User Stories

1. As a 3D-printing user, I want Finder to show a thumbnail for `.3mf` files, so that I can recognize print files without opening them.
2. As a 3D-printing user, I want Quick Look to show a larger preview image, so that I can confirm whether I selected the right file.
3. As a MakerWorld user, I want downloaded Bambu-style `.3mf` files to display their embedded preview image, so that Finder reflects what I saw when choosing the model.
4. As a user organizing print files, I want previews to appear quickly, so that browsing folders remains fluid.
5. As a user comparing similar files, I want thumbnails to be visually distinct, so that I do not accidentally print the wrong file.
6. As a user with many files, I want thumbnail generation to be reliable in normal Finder views, so that grid and column layouts remain useful.
7. As a user opening Quick Look, I want the preview to focus on the model or plate image, so that the file identity is immediately clear.
8. As a user with malformed or unsupported `.3mf` files, I want the Finder experience to degrade gracefully, so that the system does not show broken previews or confusing errors.
9. As a privacy-conscious user, I want all preview generation to happen locally, so that private print files are not uploaded or analyzed by external services.
10. As a developer testing the feature, I want representative Bambu/MakerWorld fixture files, so that compatibility can be validated against real-world packages.
11. As a developer maintaining the feature, I want the 3MF parsing and preview resolution logic separated from Quick Look integration, so that most behavior can be tested without Finder.
12. As a first-release user, I want the tool to work as a local developer build, so that the MVP can be validated before packaging or distribution decisions are made.

## Acceptance Criteria

- `.3mf` files receive useful Finder thumbnails when they contain a supported embedded preview image.
- Pressing Space on a supported `.3mf` file opens a Quick Look preview that displays the extracted image.
- Preview generation targets perceived response time under one second for normal Bambu/MakerWorld files.
- Unsupported, malformed, or preview-less `.3mf` files fall back to a standard icon plus filename instead of failing noisily.
- The first release supports Bambu Studio / MakerWorld-style `.3mf` packages as the primary compatibility target.
- The app works as a standalone local macOS developer build.
- The implementation does not modify `.3mf` files.
- The implementation performs no network requests.
- The implementation collects no telemetry.
- Test fixtures are collected or created before implementation is considered complete.
- Core parsing and preview selection behavior is covered by automated tests.

## Implementation Decisions

- Build the feature as a small standalone macOS app whose main value is shipping Quick Look extensions.
- Provide both a Quick Look preview provider and a Finder thumbnail provider.
- Treat `.3mf` files as local archive packages and inspect them read-only.
- Implement a dedicated 3MF container reader that can safely open candidate files and enumerate package entries.
- Implement a Bambu/MakerWorld preview resolver that identifies embedded preview images in supported packages.
- Implement an image normalization step that prepares extracted preview images for thumbnail and Quick Look display.
- Keep Quick Look integration thin; it should call into tested core modules rather than contain parsing logic.
- Use a simple fallback path when no supported preview image is available.
- Do not implement interactive 3D rendering in the MVP.
- Do not implement metadata display in the MVP.
- Do not implement file editing, slicing, printer communication, cost calculation, or cloud integration in the MVP.
- Target the current local macOS development environment for the first release rather than committing to a broad OS compatibility matrix upfront.

## Testing Decisions

Good tests should validate observable behavior: given a `.3mf` package with specific contents, the system either returns the expected preview image candidate or returns the expected fallback result. Tests should avoid depending on private implementation details of archive traversal or Quick Look runtime behavior.

Modules explicitly in scope for automated tests:

- 3MF container reader.
- Bambu/MakerWorld preview resolver.
- Image normalization.
- Fallback behavior.

Test inputs should include:

- Real Bambu/MakerWorld `.3mf` examples collected as fixtures where licensing and privacy allow.
- A supported `.3mf` with an embedded preview image.
- A valid `.3mf` without a supported preview image.
- A malformed or unreadable `.3mf`.
- A large but normal `.3mf` file to validate performance expectations.

Quick Look integration should receive at least a manual or smoke-test checklist in the MVP, because Finder and Quick Look behavior depends on macOS runtime registration.

## Out of Scope

- Editing or saving `.3mf` files.
- Slicing functionality.
- Printer control.
- Cloud or MakerWorld integration.
- Material cost calculation.
- Interactive 3D navigation.
- Geometry rendering as a fallback.
- Full metadata extraction or Finder preview-pane metadata.
- App Store packaging for the first release.
- Broad compatibility guarantees for non-Bambu generic 3MF files.

## Risks and Rollout

Key risks:

- Bambu/MakerWorld `.3mf` package structure may vary across versions or file sources.
- Some `.3mf` files may not contain embedded preview images.
- Quick Look extension registration and caching can make local testing confusing.
- Large files may make naive archive handling too slow for Finder thumbnail generation.
- Fixture files may contain copyrighted or private model data, so test data needs careful selection.

Suggested rollout:

1. Prototype extraction against a small set of real Bambu/MakerWorld files.
2. Build and test the core parser/resolver modules independent of Quick Look.
3. Add Quick Look preview support.
4. Add Finder thumbnail support.
5. Validate Finder behavior manually on the current macOS development machine.
6. Decide later whether to package as signed app, notarized app, or App Store product.

## Security and Privacy

The feature processes only local files selected or indexed by Finder. It must not upload files, call external services, or collect telemetry. The parser must treat `.3mf` files as untrusted input, avoid writing extracted contents to arbitrary paths, and fail safely on malformed archives.

Because `.3mf` files may contain proprietary model data, fixture collection must avoid checking private or copyrighted customer files into a public repository.

## Further Notes

The product deliberately optimizes for file identification, not full model review. The MVP should be considered successful if a user can quickly tell whether a `.3mf` file is the correct Bambu/MakerWorld print file directly from Finder.

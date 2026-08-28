# Agent instructions

Read this before changing anything in this repository.

## What this repository is

**Print File Manager**, a macOS app that indexes a user's collection of `.3mf` 3D-printing files
and lets them search, tag, inspect and reorganise it.

Two things that used to live here no longer do:
[ThreeMFKit](https://github.com/trsdn/ThreeMFKit) holds 3MF reading and preview extraction and is
consumed here as a published package pinned to an exact version, and
[3MF Quick Look](https://github.com/trsdn/threemf-quicklook) holds the Finder extensions. A change
about parsing a `.3mf`, or about Finder previews, belongs in one of those repositories.

The blast radius is the user's own files. The app moves, copies and trashes real `.3mf` files that
are often irreplaceable, and it maintains a library index that carries the user's tags, notes and
print history. A change that corrupts the index or misplaces a file destroys work that cannot be
recovered from the files themselves.

## What this repository is not

It is not a slicer and does not replace Bambu Studio, OrcaSlicer or PrusaSlicer. It does not edit,
repair or render meshes as a product feature, does not talk to printers, and is not a marketplace
client. Mesh geometry is parsed only far enough to draw a preview.

## Layout

| Path | Purpose |
|---|---|
| `printfilemanager/Sources/PrintFileManagerCore/` | Domain logic: indexing, persistence, search, organization, network clients. No UI imports. |
| `printfilemanager/Sources/PrintFileManagerApp/` | SwiftUI layer. `LibraryViewModel` owns app state; views are grouped by area. |
| `printfilemanager/Tests/` | `PrintFileManagerCoreTests` (core) and `PrintFileManagerAppTests` (view model). |
| `docs/` | Product requirements and dated review documents. |
| `scripts/release.sh` | Signs, notarizes and verifies distributable builds. |

- **Generated, never hand-edit:** `printfilemanager/PrintFileManager.xcodeproj`, produced by
  `xcodegen generate` from the `project.yml` beside it. Edit `project.yml`, regenerate, commit both.
- **Machine-owned:** `.github/conformance.yml` is hand-written, but the badge it renders is not.

## Setup

```sh
brew install xcodegen swiftlint
```

Requires macOS 15 or later and Xcode 26 or later. The Swift language mode is 6, pinned in each
`project.yml`. `isolated deinit` is used, which needs Swift 6.1 or newer.

## Run

```sh
cd printfilemanager && xcodegen generate
open PrintFileManager.xcodeproj     # then run the PrintFileManager scheme
```

## Validate before proposing a change

All three must pass:

```sh
cd printfilemanager && xcodegen generate && xcodebuild test \
  -scheme PrintFileManager -destination 'platform=macOS'     # core + app-layer tests
swiftlint lint                                               # exits non-zero on errors only
```

`swift test` catches regressions in preview extraction and ZIP handling. `xcodebuild test` covers
the domain logic and the view model, including the persistence-safety and undo paths. `swiftlint`
is tuned so the current tree produces no errors; its warnings track files that are queued for
decomposition, so a new warning is a signal rather than noise.

## Conventions

- `PrintFileManagerCore` must not import SwiftUI or AppKit. Anything that needs them belongs in the
  app layer.
- Network access goes through the `AIEnriching` and `SourceLooking` protocols so it can be stubbed
  in tests. Do not call `URLSession` directly from the view model.
- Both network features are opt-in and default to off. Any new outbound call needs its own explicit
  gate and must be documented in the README's privacy section.
- Destructive file operations are planned first, reviewed by the user, then executed, and every
  batch produces an undoable report. Preserve that shape.
- Comments explain why, not what. Most code should not need one.

## Do not do these

- Do not rewrite history, force push, or delete branches.
- Do not commit secrets, tokens, credentials, or personal data. The AI API key belongs in the
  Keychain and nowhere else.
- Do not publish a release, create or move tags, or change repository settings. Releases are cut by
  the maintainer with `scripts/release.sh`, which needs a Developer ID certificate and notarization
  credentials that are not in this repository.
- Do not weaken the safety guarantees to make a test or a metric pass: the persistence lockout, the
  Auto Sort review step, Copy-by-default, trash-instead-of-delete, and the untrusted-input size and
  index bounds all exist because a specific failure was found.
- Do not hand-edit the `.xcodeproj` files. Change `project.yml` and run `xcodegen generate`.
- Do not point the app at a real library while testing destructive paths. Use a disposable copy.
- Do not add dependencies without a stated reason in the pull request; the current surface is one
  third-party package (ZIPFoundation) and that is deliberate.

## Attribution

Agent-authored commits carry a `Co-authored-by` trailer identifying the agent and a
`Copilot-Session` trailer linking back to the session that produced them. Every change is expected
to arrive as a reviewable commit with its rationale in the message, not as an unexplained diff.

# Print File Manager

Local macOS tooling for large collections of `.3mf` 3D-printing files: a library manager that
indexes, searches and organizes them, plus a Quick Look plug-in that previews them in Finder.

Everything runs locally. Nothing is sent anywhere unless you explicitly turn it on.

## Repository layout

| Path | What it is |
|---|---|
| `printfilemanager/` | The **Print File Manager** app — indexing, search, tagging, previews, Auto Sort |
| `Quicklook/` | **3MF Quick Look** — Finder preview and thumbnail extensions plus their host app |
| `ThreeMFKit/` | Shared Swift package: 3MF package reading and preview extraction |
| `docs/` | Product requirements and dated review documents |

Both Xcode projects depend on `ThreeMFKit` as a local Swift package at `../ThreeMFKit`, so the
three folders must stay siblings.

## Requirements

- macOS 15 or later
- Xcode 26 or later (Swift 6 language mode)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

Each project's `.xcodeproj` is generated from its `project.yml` and is also committed. After
changing `project.yml`, regenerate and commit the result:

```bash
cd printfilemanager && xcodegen generate
cd ../Quicklook  && xcodegen generate
```

## Build and test

```bash
# Shared package
cd ThreeMFKit && swift test && cd ..

# Library manager
xcodebuild -project printfilemanager/PrintFileManager.xcodeproj \
           -scheme PrintFileManager -destination 'platform=macOS' test

# Quick Look extensions
xcodebuild -project Quicklook/ThreeMFQuickLook.xcodeproj \
           -scheme ThreeMFQuickLook -destination 'platform=macOS' test
```

## Installing the Quick Look extensions

Quick Look extensions only register once their host app has been installed and launched:

1. Build the `ThreeMFQuickLook` scheme in Release.
2. Move `ThreeMFQuickLook.app` to `/Applications`.
3. Launch it once.
4. Refresh the Quick Look registry: `qlmanage -r && qlmanage -r cache`.

Verify and debug with:

```bash
qlmanage -p some-model.3mf                          # render a preview
pluginkit -mAvvv -p com.apple.quicklook.preview     # confirm registration
```

Note that other applications — Bambu Studio, OrcaSlicer, PrusaSlicer — also claim the `.3mf` type,
and one of them will usually own it. The extensions therefore also register for `public.zip-archive`
so they are still offered in that case, and check at runtime that the archive really contains a 3MF
model part; any other archive is handed straight back to the system.

Extensions must be code-signed to load on a machine other than the one that built them. Signing and
notarization are not yet configured.

## Privacy

Both network features are **off by default** and are enabled independently in Settings:

- **AI enrichment** — sends the file name, its folder path, extracted metadata and, optionally, the
  preview image to an endpoint you configure. The endpoint must use `https` unless it is a local
  server. API keys are stored in the Keychain, never in preferences.
- **Web source lookup** — sends the project or file name to a web search engine and fetches the
  matching page from MakerWorld, Printables, Thingiverse or Cults.

The full `.3mf` file is never uploaded.

## Safety model

The original files are treated as valuable source artifacts:

- Auto Sort defaults to **Copy**; Move is a separate, explicit action.
- Every move, copy and rename is shown in a review sheet before anything touches the disk.
- Deletes go to the Trash, behind a confirmation.
- Destination paths proposed by an AI model are sanitized before use.
- Every batch produces a result report and can be undone with Cmd-Z: moves go back, copies are
  removed from the managed library, and originals are never deleted.
- If the library index cannot be read, it is preserved under a `.corrupt-<timestamp>` name and
  writes are blocked rather than overwriting it.
- The app runs in the App Sandbox. It can only reach folders you explicitly choose, and it keeps
  that access across launches with security-scoped bookmarks.

## Documentation

- `docs/prd-3mf-library-manager.md` — library manager requirements
- `docs/prd-3mf-quick-look-preview.md` — Quick Look requirements
- `docs/app-review-2026-05-03-print-file-manager.md` — earlier product review
- `docs/assessment-2026-08-28-multi-agent.md` — current technical assessment and roadmap

## License

MIT — see [LICENSE](LICENSE).

# ThreeMFQuickLook

Standalone macOS Quick Look app for Bambu Studio / MakerWorld `.3mf` files.

The first release follows the PRD in `../docs/prd-3mf-quick-look-preview.md`: it extracts embedded preview images from `.3mf` packages and exposes them through Finder thumbnails and Quick Look previews. It does not edit files, slice models, connect to printers, call network services, or collect telemetry.

## Build

```sh
cd Quicklook
xcodegen generate
xcodebuild -scheme ThreeMFQuickLook -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

## Test

```sh
cd Quicklook
xcodebuild -scheme ThreeMFQuickLook -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

## Local Finder Validation

1. Build and run the `ThreeMFQuickLook` app once from Xcode.
2. Open Finder on a folder containing Bambu/MakerWorld `.3mf` files.
3. Use icon view for thumbnails or press Space for Quick Look.
4. If Finder caches old behavior, restart Quick Look with `qlmanage -r` and `qlmanage -r cache`.

Representative real `.3mf` fixtures still need to be collected separately. Avoid committing private or copyrighted model files unless their license allows it.

# Contributing

## Ownership

This repository is maintained by [@trsdn](https://github.com/trsdn). It is a personal project, so
there is no review rota and no response commitment. Issues and pull requests are welcome but may
sit.

## Before you start

Read [`AGENTS.md`](AGENTS.md). It describes the layout, which paths are generated, the validation
commands, and the operations that are off limits. It is written for automated agents but is the
fastest orientation for a human too.

## Setup

```sh
brew install xcodegen swiftlint
```

Requires macOS 15 or later and Xcode 26 or later.

## Validate before opening a pull request

All three must pass:

```sh
cd printfilemanager && xcodegen generate && xcodebuild test \
  -scheme PrintFileManager -destination 'platform=macOS'
swiftlint lint
```

`swiftlint` exits non-zero only on errors. Its warnings track files that are queued for
decomposition, so do not add new ones without saying why.

## Conventions

- `PrintFileManagerCore` must not import SwiftUI or AppKit.
- The `.xcodeproj` files are generated. Edit the `project.yml` beside them, run
  `xcodegen generate`, and commit both.
- New outbound network calls need their own explicit opt-in and a line in the README's privacy
  section. Nothing may reach the network by default.
- Changes to destructive file operations need a test that covers the failure case, not just the
  happy path.
- Commit messages explain why the change was needed, not just what changed. Reviewers read the
  message before the diff.

## Changelog

User-facing and operational changes go in [`CHANGELOG.md`](CHANGELOG.md) under `Unreleased`.

## Dependency updates

Dependabot proposes GitHub Actions updates weekly. It does not update the app's Swift packages:
they are declared in `printfilemanager/project.yml`, and the former `/ThreeMFKit` package directory
now lives in [trsdn/ThreeMFKit](https://github.com/trsdn/ThreeMFKit).

The maintainer, [@trsdn](https://github.com/trsdn), reviews ThreeMFKit and ZIPFoundation releases and
security advisories weekly and before a release. This is a manual responsibility, not an automated
Swift Dependabot check.

For an app dependency update, review the upstream changes, update `project.yml` as needed, and keep
ThreeMFKit's `exactVersion` constraint. Run `xcodegen generate` in `printfilemanager`, resolve the
packages and run `scripts/ci-local.sh`. Include the regenerated project and any changed
`Package.resolved` in the same reviewed change. Do not replace the exact pin with a version range
or move parsing code back into this repository. Changes to parsing belong in ThreeMFKit; Finder
extension changes belong in `trsdn/threemf-quicklook`.

## Releases

Releases are cut by the maintainer. Tagging `vX.Y` runs the release workflow, which signs,
notarizes and smoke-tests the artifacts. Contributors should not create or move tags.

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

## Releases

Releases are cut by the maintainer. Tagging `vX.Y` runs the release workflow, which signs,
notarizes and smoke-tests the artifacts. Contributors should not create or move tags.

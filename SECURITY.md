# Security

## Scope and status

This is a personal macOS project maintained by a single person. It is not a commercial product and
there is no service level attached to a report, but security issues are taken seriously because the
app has write access to files a user cannot replace.

## Reporting

Report suspected vulnerabilities privately through
[GitHub security advisories](https://github.com/trsdn/printfilemanager/security/advisories/new)
rather than a public issue. Include what you did, what happened, and what you expected.

## What the threat model assumes

A `.3mf` file is **untrusted input**. It is a ZIP archive that users routinely download from
MakerWorld, Printables, Thingiverse and elsewhere, and it may be crafted. The parsing paths treat it
accordingly:

- Decompressed entry sizes are capped, checking both the declared size and the streamed byte count,
  because archive metadata can lie.
- Mesh triangle indices are range-checked against the vertex count and parsed in a width that
  cannot trap on overflow.
- Archive entry paths are used only for in-memory lookup, never to construct a write path.
- XML is parsed with external entity resolution left off.
- Metadata read from a file is delimited and length-bounded before it reaches an LLM prompt, so it
  cannot pose as instructions.
- Destination paths proposed by an AI model are sanitised before use: separators, traversal
  segments and control characters are stripped, depth is capped, and the result is rebuilt under
  the managed folder.

## Handling of credentials

The AI provider API key is stored in the Keychain as a generic password with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it does not sync. Only a boolean flag
recording that a key exists is kept in preferences. The key is never logged, never written to the
library index, and never included in an error message.

## Network behaviour

Both outbound features are off until explicitly enabled, and each has its own switch:

| Feature | Destination | What is sent |
|---|---|---|
| AI enrichment | The endpoint the user configures | File name, folder path, extracted metadata, and optionally the preview image |
| Web source lookup | DuckDuckGo, then the matched model page | The project or file name |

The `.3mf` file itself is never uploaded. AI endpoints must use HTTPS unless they are on localhost.
Requests carry explicit timeouts.

## File safety

The app can move, copy and trash the user's files. The guarantees it maintains:

- Auto Sort defaults to Copy; Move is a separate, explicit action.
- Every plan is shown for review before anything touches the disk, and every executed batch is
  undoable.
- Deletion goes to the Trash, never an unlink.
- If the library index cannot be read, it is preserved under a `.corrupt-<timestamp>` name and all
  writes are blocked until the user decides what to do.

## Known limitations

- The app is sandboxed, but distribution builds are signed and notarized manually by the
  maintainer; there is no published release yet.
- The library index is stored unencrypted in Application Support. It contains file paths and any
  AI-generated descriptions, which should be considered sensitive at rest.
- Web source lookup discloses project names to a search engine when the user enables it. That is
  inherent to the feature and is stated in the UI.

import CoreServices
import Foundation
import PrintFileManagerCore

@MainActor
final class FolderWatcher {
    /// Holds the live FSEvents streams.
    ///
    /// The streams live in their own reference type so that tearing them down does not need to
    /// touch MainActor-isolated state from `deinit`. Doing that would require an isolated
    /// `deinit`, which is still gated behind an experimental flag on some Xcode versions and made
    /// the project unbuildable on a release runner.
    private final class StreamStore: @unchecked Sendable {
        private var streams: [UUID: FSEventStreamRef] = [:]

        func insert(_ stream: FSEventStreamRef, for id: UUID) {
            streams[id] = stream
        }

        func removeAll() {
            for stream in streams.values {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
            streams.removeAll()
        }

        deinit {
            // Without this, a watcher released without an explicit `update(roots: [])` leaks its
            // FSEvents streams and the retained callback boxes.
            removeAll()
        }
    }

    private let store = StreamStore()

    func update(roots: [LibraryRoot], onChange: @escaping @MainActor (LibraryRoot) -> Void) {
        stopAll()

        for root in roots where root.isWatched && root.isAvailable {
            start(root: root, onChange: onChange)
        }
    }

    func stopAll() {
        store.removeAll()
    }

    private func start(root: LibraryRoot, onChange: @escaping @MainActor (LibraryRoot) -> Void) {
        let box = FolderWatchBox(root: root, onChange: onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<FolderWatchBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil,
            folderWatcherCallback,
            &context,
            [root.url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        store.insert(stream, for: root.id)
    }
}

private final class FolderWatchBox {
    private let root: LibraryRoot
    private let onChange: @MainActor (LibraryRoot) -> Void
    private let lock = NSLock()
    private var debounceTask: Task<Void, Never>?

    init(root: LibraryRoot, onChange: @escaping @MainActor (LibraryRoot) -> Void) {
        self.root = root
        self.onChange = onChange
    }

    func scheduleChange() {
        lock.lock()
        debounceTask?.cancel()
        debounceTask = Task { [root, onChange] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onChange(root)
            }
        }
        lock.unlock()
    }

    deinit {
        debounceTask?.cancel()
    }
}

private let folderWatcherCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    let box = Unmanaged<FolderWatchBox>.fromOpaque(info).takeUnretainedValue()
    box.scheduleChange()
}

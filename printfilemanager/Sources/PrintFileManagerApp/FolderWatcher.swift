import CoreServices
import Foundation
import PrintFileManagerCore

@MainActor
final class FolderWatcher {
    private var streams: [UUID: FSEventStreamRef] = [:]

    func update(roots: [LibraryRoot], onChange: @escaping @MainActor (LibraryRoot) -> Void) {
        stopAll()

        for root in roots where root.isWatched && root.isAvailable {
            start(root: root, onChange: onChange)
        }
    }

    func stopAll() {
        for stream in streams.values {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
    }

    /// Isolated so the teardown can touch the MainActor-isolated stream table. Without this, a
    /// watcher released without an explicit `update(roots: [])` leaks its FSEvents streams and the
    /// retained callback boxes.
    isolated deinit {
        stopAll()
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
        streams[root.id] = stream
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

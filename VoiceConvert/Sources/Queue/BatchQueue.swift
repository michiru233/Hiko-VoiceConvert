import Foundation

public enum QueueItemState: Equatable, Sendable {
    case waiting
    case converting
    case succeeded
    case failed(String)
    case cancelled
}

public struct QueueItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let inputURL: URL
    public var outputURL: URL?
    public var progress: Double
    public var state: QueueItemState

    public init(inputURL: URL) {
        id = UUID()
        self.inputURL = inputURL
        outputURL = nil
        progress = 0
        state = .waiting
    }
}

public struct QueueSummary: Equatable, Sendable {
    public let total: Int
    public let succeeded: Int
    public let failed: Int
    public let cancelled: Int

    public init(total: Int, succeeded: Int, failed: Int, cancelled: Int) {
        self.total = total
        self.succeeded = succeeded
        self.failed = failed
        self.cancelled = cancelled
    }
}

@MainActor
public final class BatchQueue {
    public private(set) var items: [QueueItem] = []
    public private(set) var isRunning = false
    public private(set) var isPaused = false
    public private(set) var summary = QueueSummary(total: 0, succeeded: 0, failed: 0, cancelled: 0)

    private let engine: ConversionEngine
    private let cancellationState = CancellationBox()
    private let pauseState = CancellationBox()
    private var inputRoots: [String: URL] = [:]

    public init(engine: ConversionEngine = ConversionEngine()) {
        self.engine = engine
    }

    public func enqueue(_ urls: [URL]) {
        guard !isRunning else { return }
        let scanned = AudioInputScanner().scan(urls)
        let existing = Set(items.map { $0.inputURL.standardizedFileURL.path })
        for input in scanned where !existing.contains(input.standardizedFileURL.path) {
            items.append(QueueItem(inputURL: input))
            if let root = urls.first(where: { url in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
                let rootPath = url.standardizedFileURL.path.hasSuffix("/") ? url.standardizedFileURL.path : url.standardizedFileURL.path + "/"
                return input.standardizedFileURL.path.hasPrefix(rootPath)
            }) {
                inputRoots[input.standardizedFileURL.path] = root.standardizedFileURL
            }
        }
        updateSummary()
    }

    public func clear() {
        guard !isRunning else { return }
        items.removeAll()
        inputRoots.removeAll()
        updateSummary()
    }

    public func pause() {
        pauseState.set()
        isPaused = true
    }

    public func resume() {
        pauseState.reset()
        isPaused = false
    }

    public func cancel() {
        cancellationState.set()
    }

    public func run(
        config: ConversionConfig,
        relativeRoots: [URL: URL]? = nil,
        confirmDelete: @escaping @Sendable () async -> Bool = { true }
    ) async {
        guard !isRunning, !items.isEmpty else { return }
        isRunning = true
        cancellationState.reset()
        pauseState.reset()

        let outputRoot = (config.outputDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/音声库")).standardizedFileURL
        var reserved = Set<String>()
        var plans: [(index: Int, input: URL, output: URL)] = []
        for index in items.indices where items[index].state == .waiting || {
            if case .failed = items[index].state { return true }
            return false
        }() {
            let input = items[index].inputURL
            let relativeRoot = relativeRoots?[input] ?? inputRoots[input.standardizedFileURL.path] ?? input.deletingLastPathComponent()
            do {
                let proposed = try OutputPathResolver.resolve(input: input, root: outputRoot, relativeRoot: relativeRoot)
                let output = OutputPathResolver.uniqueURL(proposed, reserved: &reserved)
                items[index].outputURL = output
                plans.append((index, input, output))
            } catch {
                items[index].state = .failed(error.localizedDescription)
            }
        }
        updateSummary()

        let deleteSources: Bool
        if config.deleteSourceOnSuccess && !plans.isEmpty {
            deleteSources = await confirmDelete()
        } else {
            deleteSources = false
        }
        let limit = max(1, min(8, config.concurrency))
        let semaphore = AsyncSemaphore(value: limit)
        let engine = self.engine
        let cancellationState = self.cancellationState
        let pauseState = self.pauseState
        let queue = self

        await withTaskGroup(of: Void.self) { group in
            for plan in plans {
                group.addTask { [engine, cancellationState, pauseState, queue] in
                    guard await semaphore.wait(untilCancelled: cancellationState) else {
                        await MainActor.run { queue.setState(index: plan.index, state: .cancelled) }
                        return
                    }
                    while pauseState.isSet && !cancellationState.isSet {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    guard !cancellationState.isSet else {
                        await semaphore.signal()
                        await MainActor.run { queue.setState(index: plan.index, state: .cancelled) }
                        return
                    }
                    await MainActor.run { queue.setState(index: plan.index, state: .converting) }
                    do {
                        _ = try engine.convert(
                            inputURL: plan.input,
                            outputURL: plan.output,
                            config: config,
                            progress: { value in
                                Task { @MainActor in queue.setProgress(index: plan.index, value: value) }
                            },
                            isCancelled: { cancellationState.isSet }
                        )
                        if deleteSources {
                            try FileManager.default.removeItem(at: plan.input)
                        }
                        await semaphore.signal()
                        await MainActor.run { queue.setState(index: plan.index, state: .succeeded) }
                    } catch let error as ConversionError {
                        await semaphore.signal()
                        await MainActor.run { queue.setState(index: plan.index, state: error == .cancelled ? .cancelled : .failed(error.localizedDescription)) }
                    } catch {
                        await semaphore.signal()
                        await MainActor.run { queue.setState(index: plan.index, state: .failed(error.localizedDescription)) }
                    }
                }
            }
            await group.waitForAll()
        }

        isRunning = false
        isPaused = false
        updateSummary()
    }

    private func setProgress(index: Int, value: Double) {
        guard items.indices.contains(index) else { return }
        items[index].progress = min(1, max(0, value))
    }

    private func setState(index: Int, state: QueueItemState) {
        guard items.indices.contains(index) else { return }
        items[index].state = state
        if state == .succeeded { items[index].progress = 1 }
        updateSummary()
    }

    private func updateSummary() {
        summary = QueueSummary(
            total: items.count,
            succeeded: items.filter { $0.state == .succeeded }.count,
            failed: items.filter { if case .failed = $0.state { return true }; return false }.count,
            cancelled: items.filter { $0.state == .cancelled }.count
        )
    }
}

private final class CancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }
}

private actor AsyncSemaphore {
    private var permits: Int

    init(value: Int) { permits = max(1, value) }

    func wait(untilCancelled cancellation: CancellationBox) async -> Bool {
        while permits == 0 {
            if cancellation.isSet || Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if cancellation.isSet || Task.isCancelled { return false }
        permits -= 1
        return true
    }

    func signal() {
        permits += 1
    }
}

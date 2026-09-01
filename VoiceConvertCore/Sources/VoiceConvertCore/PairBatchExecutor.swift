import Foundation

public enum PairExecutionResult: Equatable, Sendable {
    case succeeded
    case failed(String)
    case cancelled
}

public typealias PairAudioExecutor = @Sendable (
    _ inputURL: URL,
    _ outputURL: URL,
    _ progress: @escaping @Sendable (Double) -> Void,
    _ isCancelled: @escaping @Sendable () -> Bool,
    _ overwrite: Bool
) async -> PairExecutionResult

public struct PairBatchExecutor: Sendable {
    private let converter: VttToLrcConverter

    public init(converter: VttToLrcConverter = VttToLrcConverter()) {
        self.converter = converter
    }

    public func execute(
        plan: PairBatchPlan,
        audioExecutor: @escaping PairAudioExecutor,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        confirmOverwrite: @escaping @Sendable () async -> Bool = { false },
        keepSpeakers: Bool = false,
        mode: SubtitleConversionMode = .lenient,
        progress: @escaping @Sendable (UUID, Double) -> Void = { _, _ in }
    ) async -> PairBatchPlan {
        await execute(
            plan: plan,
            audioExecutor: audioExecutor,
            isCancelled: isCancelled,
            confirmOverwrite: confirmOverwrite,
            keepSpeakers: keepSpeakers,
            mode: mode,
            retryOnly: false,
            progress: progress
        )
    }

    public func retry(
        plan: PairBatchPlan,
        audioExecutor: @escaping PairAudioExecutor,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        confirmOverwrite: @escaping @Sendable () async -> Bool = { false },
        keepSpeakers: Bool = false,
        mode: SubtitleConversionMode = .lenient,
        progress: @escaping @Sendable (UUID, Double) -> Void = { _, _ in }
    ) async -> PairBatchPlan {
        await execute(
            plan: plan,
            audioExecutor: audioExecutor,
            isCancelled: isCancelled,
            confirmOverwrite: confirmOverwrite,
            keepSpeakers: keepSpeakers,
            mode: mode,
            retryOnly: true,
            progress: progress
        )
    }

    private func execute(
        plan originalPlan: PairBatchPlan,
        audioExecutor: @escaping PairAudioExecutor,
        isCancelled: @escaping @Sendable () -> Bool,
        confirmOverwrite: @escaping @Sendable () async -> Bool,
        keepSpeakers: Bool,
        mode: SubtitleConversionMode,
        retryOnly: Bool,
        progress: @escaping @Sendable (UUID, Double) -> Void
    ) async -> PairBatchPlan {
        var plan = originalPlan
        var overwriteConfirmed = false
        var askedForOverwrite = false

        for outputPlan in plan.plans {
            let parentIndex = plan.tasks.firstIndex { $0.role == .pairing && $0.inputURL == outputPlan.audioURL }
            guard let parentIndex else { continue }
            let parentID = plan.tasks[parentIndex].id
            let audioIndex = plan.tasks.firstIndex { $0.parentID == parentID && $0.operation == .mp3 }
            let subtitleIndex = plan.tasks.firstIndex { $0.parentID == parentID && $0.operation == .lrc }

            if retryOnly && !shouldRetry(audioIndex.flatMap { plan.tasks[$0].status }, subtitleStatus: subtitleIndex.flatMap { plan.tasks[$0].status }) {
                aggregate(parentID: parentID, in: &plan.tasks)
                continue
            }

            if isCancelled() {
                cancelWaiting(parentID: parentID, in: &plan.tasks)
                aggregate(parentID: parentID, in: &plan.tasks)
                continue
            }

            let overwrite: Bool
            if outputPlan.policy == .overwrite {
                if askedForOverwrite {
                    overwrite = overwriteConfirmed
                } else {
                    askedForOverwrite = true
                    overwriteConfirmed = await confirmOverwrite()
                    overwrite = overwriteConfirmed
                }
            } else {
                overwrite = false
            }

            if let audioIndex, shouldRun(plan.tasks[audioIndex].status) {
                if retryOnly, let subtitleIndex,
                   isAudioAvailable(plan.tasks[audioIndex].status),
                   ifSkippedByDependency(plan.tasks[subtitleIndex].status) {
                    plan.tasks[subtitleIndex].status = .waiting
                    plan.tasks[subtitleIndex].progress = 0
                }
                guard snapshotMatches(plan.tasks[audioIndex]) else {
                    plan.tasks[audioIndex].status = .failed("输入文件在执行前发生变化")
                    plan.tasks[audioIndex].progress = 0
                    if let subtitleIndex { plan.tasks[subtitleIndex].status = .skipped("音频输入无效") }
                    aggregate(parentID: parentID, in: &plan.tasks)
                    continue
                }
                guard let outputURL = outputPlan.mp3URL else {
                    plan.tasks[audioIndex].status = .skipped("未选择 MP3 输出")
                    plan.tasks[audioIndex].progress = 0
                    aggregate(parentID: parentID, in: &plan.tasks)
                    continue
                }
                if !overwrite && FileManager.default.fileExists(atPath: outputURL.path) {
                    plan.tasks[audioIndex].status = .skipped("输出已存在，未覆盖")
                    plan.tasks[audioIndex].outputURL = outputURL
                } else if outputPlan.policy == .overwrite && !overwrite {
                    plan.tasks[audioIndex].status = .skipped("未确认覆盖")
                } else {
                    plan.tasks[audioIndex].status = .running
                    let audioTaskID = plan.tasks[audioIndex].id
                    let result = await audioExecutor(
                        outputPlan.audioURL,
                        outputURL,
                        { value in progress(audioTaskID, value) },
                        isCancelled,
                        overwrite
                    )
                    switch result {
                    case .succeeded:
                        plan.tasks[audioIndex].status = .succeeded
                        plan.tasks[audioIndex].progress = 1
                        if retryOnly, let subtitleIndex, ifSkippedByDependency(plan.tasks[subtitleIndex].status) {
                            plan.tasks[subtitleIndex].status = .waiting
                            plan.tasks[subtitleIndex].progress = 0
                        }
                    case let .failed(reason):
                        plan.tasks[audioIndex].status = .failed(reason)
                    case .cancelled:
                        plan.tasks[audioIndex].status = .cancelled
                    }
                }
            }

            if let subtitleIndex, shouldRun(plan.tasks[subtitleIndex].status) {
                guard let audioIndex else {
                    if outputPlan.mp3URL != nil {
                        plan.tasks[subtitleIndex].status = .failed("缺少音频子任务")
                        aggregate(parentID: parentID, in: &plan.tasks)
                        continue
                    }
                    // LRC-only batches have no audio dependency.
                    if !snapshotMatches(plan.tasks[subtitleIndex]) {
                        plan.tasks[subtitleIndex].status = .failed("字幕文件在执行前发生变化")
                        aggregate(parentID: parentID, in: &plan.tasks)
                        continue
                    }
                    if let outputURL = outputPlan.lrcURL {
                        plan.tasks[subtitleIndex].status = .running
                        let outcome = converter.convertFile(at: outputPlan.subtitleURL, destination: outputURL,
                                                            keepSpeakers: keepSpeakers, mode: mode,
                                                            overwrite: overwrite, isCancelled: isCancelled)
                        plan.tasks[subtitleIndex].status = status(for: outcome)
                        if case .created = outcome { plan.tasks[subtitleIndex].progress = 1 }
                        if case .createdWithWarnings = outcome { plan.tasks[subtitleIndex].progress = 1 }
                    }
                    aggregate(parentID: parentID, in: &plan.tasks)
                    continue
                }
                guard isAudioAvailable(plan.tasks[audioIndex].status) || outputPlan.mp3URL == nil else {
                    plan.tasks[subtitleIndex].status = .skipped("音频转换失败，未生成字幕")
                    aggregate(parentID: parentID, in: &plan.tasks)
                    continue
                }
                guard snapshotMatches(plan.tasks[subtitleIndex]) else {
                    plan.tasks[subtitleIndex].status = .failed("字幕文件在执行前发生变化")
                    aggregate(parentID: parentID, in: &plan.tasks)
                    continue
                }
                guard let outputURL = outputPlan.lrcURL else {
                    plan.tasks[subtitleIndex].status = .skipped("未选择 LRC 输出")
                    aggregate(parentID: parentID, in: &plan.tasks)
                    continue
                }
                if isCancelled() {
                    plan.tasks[subtitleIndex].status = .cancelled
                } else if !overwrite && FileManager.default.fileExists(atPath: outputURL.path) {
                    plan.tasks[subtitleIndex].status = .skipped("输出已存在，未覆盖")
                } else if outputPlan.policy == .overwrite && !overwrite {
                    plan.tasks[subtitleIndex].status = .skipped("未确认覆盖")
                } else {
                    plan.tasks[subtitleIndex].status = .running
                    let outcome = converter.convertFile(
                        at: outputPlan.subtitleURL,
                        destination: outputURL,
                        keepSpeakers: keepSpeakers,
                        mode: mode,
                        overwrite: overwrite,
                        isCancelled: isCancelled
                    )
                    plan.tasks[subtitleIndex].status = status(for: outcome)
                    if case .created = outcome { plan.tasks[subtitleIndex].progress = 1 }
                    if case .createdWithWarnings = outcome { plan.tasks[subtitleIndex].progress = 1 }
                }
            }
            aggregate(parentID: parentID, in: &plan.tasks)
        }
        return plan
    }

    private func shouldRetry(_ audio: TaskStatus?, subtitleStatus: TaskStatus?) -> Bool {
        [audio, subtitleStatus].compactMap { $0 }.contains { status in
            if case .failed = status { return true }
            if case .cancelled = status { return true }
            return false
        }
    }

    private func ifSkippedByDependency(_ status: TaskStatus) -> Bool {
        if case let .skipped(reason) = status { return reason == "音频转换失败，未生成字幕" || reason == "音频输入无效" }
        return false
    }

    private func shouldRun(_ status: TaskStatus) -> Bool {
        if case .waiting = status { return true }
        if case .failed = status { return true }
        if case .cancelled = status { return true }
        return false
    }

    private func snapshotMatches(_ task: WorkflowTask) -> Bool {
        task.snapshot?.matchesCurrentFile() ?? false
    }

    private func isAudioAvailable(_ status: TaskStatus) -> Bool {
        switch status {
        case .succeeded, .succeededWithWarnings, .skipped: return true
        default: return false
        }
    }

    private func status(for outcome: FileConversionOutcome) -> TaskStatus {
        switch outcome {
        case .created: return .succeeded
        case let .createdWithWarnings(warnings): return .succeededWithWarnings(warnings)
        case .alreadyExists: return .skipped("输出已存在，未覆盖")
        case let .skipped(reason): return .skipped(reason)
        case let .failed(reason): return .failed(reason)
        }
    }

    private func cancelWaiting(parentID: UUID, in tasks: inout [WorkflowTask]) {
        for index in tasks.indices where tasks[index].parentID == parentID && shouldRun(tasks[index].status) {
            tasks[index].status = .cancelled
        }
    }

    private func aggregate(parentID: UUID, in tasks: inout [WorkflowTask]) {
        guard let parent = tasks.firstIndex(where: { $0.id == parentID }) else { return }
        let children = tasks.filter { $0.parentID == parentID }
        guard !children.isEmpty else { return }
        let warnings = children.flatMap { status -> [String] in
            if case let .succeededWithWarnings(values) = status.status { return values }
            return []
        }
        if children.contains(where: { if case .failed = $0.status { return true }; return false }) {
            tasks[parent].status = .failed("配对中有子任务失败")
        } else if children.contains(where: { $0.status == .cancelled }) {
            tasks[parent].status = .cancelled
        } else if children.contains(where: { if case .skipped = $0.status { return true }; return false }) {
            tasks[parent].status = .skipped("配对子任务已跳过")
        } else if !warnings.isEmpty {
            tasks[parent].status = .succeededWithWarnings(warnings)
        } else if children.allSatisfy({ $0.status == .succeeded }) {
            tasks[parent].status = .succeeded
        } else {
            tasks[parent].status = .waiting
        }
        tasks[parent].progress = children.map(\.progress).reduce(0, +) / Double(children.count)
    }
}

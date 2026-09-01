import Foundation
import VoiceConvertCore
import VoiceConvertAudioBackend

public enum ExitCode: Int32, Sendable {
    case success = 0
    case partialFailure = 1
    case usage = 64
    case noInput = 66
    case unavailable = 69
}

private final class PairResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PairBatchPlan

    init(_ value: PairBatchPlan) {
        self.value = value
    }

    func set(_ value: PairBatchPlan) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> PairBatchPlan {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public struct CLI: Sendable {
    private let arguments: [String]
    private let out: @Sendable (String) -> Void
    private let err: @Sendable (String) -> Void

    public init(
        arguments: [String],
        out: @escaping @Sendable (String) -> Void = { print($0) },
        err: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) {
        self.arguments = arguments
        self.out = out
        self.err = err
    }

    public func run() -> ExitCode {
        guard let first = arguments.first else { return failUsage("缺少子命令。") }
        if ["-h", "--help", "help"].contains(first) {
            out(Self.usage)
            return .success
        }
        switch first {
        case "audio": return runAudio(Array(arguments.dropFirst()))
        case "subtitle": return runSubtitle(Array(arguments.dropFirst()))
        case "pair": return runPair(Array(arguments.dropFirst()))
        case "--convert": return runLegacyConvert(Array(arguments.dropFirst()))
        default: return failUsage("未知子命令：\(first)")
        }
    }

    private func runLegacyConvert(_ args: [String]) -> ExitCode {
        var paths: [String] = []
        var speakers = false
        for argument in args {
            switch argument {
            case "--speakers": speakers = true
            case let value where value.hasPrefix("-"): return failUsage("--convert 不支持选项：\(value)")
            default: paths.append(argument)
            }
        }
        guard paths.count == 1 else { return failUsage("--convert 需要且只接受一个路径。") }
        return runSubtitle([paths[0]] + (speakers ? ["--speakers"] : []))
    }

    private func runAudio(_ args: [String]) -> ExitCode {
        var paths: [String] = []
        var output: URL?
        var policy: OutputConflictPolicy = .suffix
        var checkOnly = false
        var overwriteConfirmed = false
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--check": checkOnly = true; index += 1
            case "--yes": overwriteConfirmed = true; index += 1
            case "--output":
                guard index + 1 < args.count else { return failUsage("audio --output 需要一个目录。") }
                output = URL(fileURLWithPath: args[index + 1]).standardizedFileURL; index += 2
            case "--policy":
                guard index + 1 < args.count, let value = OutputConflictPolicy(rawValue: args[index + 1]) else { return failUsage("audio --policy 必须是 suffix、skip 或 overwrite。") }
                policy = value; index += 2
            case let value where value.hasPrefix("-"): return failUsage("audio 不支持选项：\(value)")
            default: paths.append(args[index]); index += 1
            }
        }
        guard !paths.isEmpty else { return failUsage("audio 至少需要一个路径。") }
        let result = WorkflowScanner().scan(urls(paths), kind: .audio)
        report(result.issues)
        guard !result.inputs.isEmpty else { err("未找到可处理的音频输入。"); return .noInput }
        if checkOnly {
            for input in result.inputs { out("AUDIO\t\(input.url.path)") }
            return result.issues.isEmpty ? .success : .partialFailure
        }
        let root = output ?? defaultOutputRoot(for: result.inputs.first!.root)
        let converter = CLIAudioConverter()
        var failed = !result.issues.isEmpty
        var reserved = Set<String>()
        for input in result.inputs {
            do {
                guard let destination = try OutputNamePlanner().plan(input: input, outputRoot: root, outputExtension: "mp3", policy: policy, reserved: &reserved) else {
                    err("SKIPPED\t\(input.url.path)\t输出已存在，未覆盖"); failed = true; continue
                }
                if policy == .overwrite && !overwriteConfirmed {
                    err("SKIPPED\t\(destination.path)\t覆盖需要 --yes"); failed = true; continue
                }
                _ = try converter.convert(inputURL: input.url, outputURL: destination, overwrite: policy == .overwrite)
                out("CREATED\t\(destination.path)")
            } catch {
                err("FAILED\t\(input.url.path)\t\(error.localizedDescription)"); failed = true
            }
        }
        return failed ? .partialFailure : .success
    }

    private func runSubtitle(_ args: [String]) -> ExitCode {
        var paths: [String] = []
        var speakers = false
        var strict = false
        for argument in args {
            switch argument { case "--speakers": speakers = true; case "--strict": strict = true; case let value where value.hasPrefix("-"): return failUsage("subtitle 不支持选项：\(argument)"); default: paths.append(argument) }
        }
        guard !paths.isEmpty else { return failUsage("subtitle 至少需要一个路径。") }
        let result = WorkflowScanner().scan(urls(paths), kind: .subtitle)
        report(result.issues)
        guard !result.inputs.isEmpty else { err("未找到可转换的 .vtt 字幕文件。"); return .noInput }
        let converter = VttToLrcConverter()
        let mode: SubtitleConversionMode = strict ? .strict : .lenient
        var failed = !result.issues.isEmpty
        for input in result.inputs {
            let destination = VttToLrcConverter.lrcDestination(for: input.url)
            switch converter.convertFile(at: input.url, destination: destination, keepSpeakers: speakers, mode: mode) {
            case .created: out("CREATED\t\(destination.path)")
            case .createdWithWarnings(let warnings): out("CREATED_WITH_WARNINGS\t\(destination.path)\t\(warnings.joined(separator: ";"))")
            case .skipped(let reason): err("SKIPPED\t\(input.url.path)\t\(reason)"); failed = true
            case .alreadyExists: err("SKIPPED\t\(destination.path)\t输出已存在，未覆盖"); failed = true
            case .failed(let reason): err("FAILED\t\(input.url.path)\t\(reason)"); failed = true
            }
        }
        return failed ? .partialFailure : .success
    }

    private func runPair(_ args: [String]) -> ExitCode {
        var audioPaths: [String] = [], subtitlePaths: [String] = [], positional: [String] = []
        var output: URL?, policy: OutputConflictPolicy = .suffix, yes = false, generateMP3 = true, generateLRC = true
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--audio", "--subtitle":
                guard index + 1 < args.count else { return failUsage("\(args[index]) 需要一个路径。") }
                if args[index] == "--audio" { audioPaths.append(args[index + 1]) } else { subtitlePaths.append(args[index + 1]) }; index += 2
            case "--output": guard index + 1 < args.count else { return failUsage("pair --output 需要一个目录。") }; output = URL(fileURLWithPath: args[index + 1]).standardizedFileURL; index += 2
            case "--policy": guard index + 1 < args.count, let value = OutputConflictPolicy(rawValue: args[index + 1]) else { return failUsage("pair --policy 必须是 suffix、skip 或 overwrite。") }; policy = value; index += 2
            case "--yes": yes = true; index += 1
            case "--no-mp3": generateMP3 = false; index += 1
            case "--no-lrc": generateLRC = false; index += 1
            case let value where value.hasPrefix("-"): return failUsage("pair 不支持选项：\(value)")
            default: positional.append(args[index]); index += 1
            }
        }
        if audioPaths.isEmpty && subtitlePaths.isEmpty { guard positional.count == 2 else { return failUsage("pair 需要一个音频路径和一个字幕路径。") }; audioPaths = [positional[0]]; subtitlePaths = [positional[1]] }
        guard !audioPaths.isEmpty, !subtitlePaths.isEmpty else { return failUsage("pair 同时需要音频和字幕路径。") }
        let scanner = WorkflowScanner(), audio = scanner.scan(urls(audioPaths), kind: .audio), subtitles = scanner.scan(urls(subtitlePaths), kind: .subtitle)
        report(audio.issues); report(subtitles.issues)
        guard !audio.inputs.isEmpty, !subtitles.inputs.isEmpty else { err("配对需要至少一个受支持的音频文件和字幕文件。"); return .noInput }
        let pairing = PairingMatcher().match(audio: audio.inputs, subtitles: subtitles.inputs)
        for issue in pairing.issues { err("UNPAIRED\t\(issue.subtitle?.path ?? issue.audio?.path ?? "-")\t\(issue.reason)") }
        guard !pairing.pairs.isEmpty else { return .partialFailure }
        do {
            let root = output ?? defaultOutputRoot(for: audio.inputs.first!.root)
            let plan = try PairBatchPlanner().makePlan(from: pairing, outputRoot: root, generateMP3: generateMP3, generateLRC: generateLRC, policy: policy)
            let completed = waitForPair(plan: plan, yes: yes)
            for task in completed.tasks where task.role != .pairing {
                let path = task.outputURL?.path ?? "-"
                switch task.status {
                case .succeeded: out("CREATED\t\(path)")
                case .succeededWithWarnings(let warnings): out("CREATED_WITH_WARNINGS\t\(path)\t\(warnings.joined(separator: ";"))")
                case .skipped(let reason): err("SKIPPED\t\(path)\t\(reason)")
                case .failed(let reason): err("FAILED\t\(task.inputURL.path)\t\(reason)")
                case .cancelled: err("CANCELLED\t\(task.inputURL.path)")
                case .waiting, .running: err("FAILED\t\(task.inputURL.path)\t任务未完成")
                }
            }
            return completed.tasks.contains { if case .failed = $0.status { return true }; if case .cancelled = $0.status { return true }; if case .skipped = $0.status { return true }; return false } ? .partialFailure : .success
        } catch { err("FAILED\t配对计划\t\(error.localizedDescription)"); return .partialFailure }
    }

    private func waitForPair(plan: PairBatchPlan, yes: Bool) -> PairBatchPlan {
        let semaphore = DispatchSemaphore(value: 0)
        let box = PairResultBox(plan)
        Task {
            let completed = await PairBatchExecutor().execute(plan: plan, audioExecutor: { input, output, progress, cancelled, overwrite in
                do { _ = try CLIAudioConverter().convert(inputURL: input, outputURL: output, progress: progress, isCancelled: cancelled, overwrite: overwrite); return .succeeded }
                catch let error as CLIAudioError where error == .cancelled { return .cancelled }
                catch { return .failed(error.localizedDescription) }
            }, confirmOverwrite: { yes })
            box.set(completed)
            semaphore.signal()
        }
        semaphore.wait()
        return box.get()
    }

    private func defaultOutputRoot(for inputRoot: URL) -> URL {
        inputRoot.deletingLastPathComponent()
            .appendingPathComponent("\(inputRoot.lastPathComponent)-converted", isDirectory: true)
            .standardizedFileURL
    }

    private func urls(_ paths: [String]) -> [URL] { paths.map { URL(fileURLWithPath: $0).standardizedFileURL } }
    private func report(_ issues: [ScanIssue]) { for issue in issues { switch issue { case .duplicate(let path, let kept): err("WARNING\t\(path)\t重复输入，保留 \(kept)"); case .inaccessible(let path, let reason): err("WARNING\t\(path)\t\(reason)"); case .unsupported(let path): err("WARNING\t\(path)\t不支持的文件类型") } } }
    private func failUsage(_ message: String) -> ExitCode { err(message); err("使用 --help 查看用法。"); return .usage }

    public static let usage = """
    用法：voiceconvert <audio|subtitle|pair> ...
      audio PATH... [--check] [--output DIR] [--policy suffix|skip|overwrite] [--yes]
      subtitle PATH... [--speakers] [--strict]
      pair AUDIO_PATH SUBTITLE_PATH [--output DIR] [--policy suffix|skip|overwrite] [--yes]
    """
}

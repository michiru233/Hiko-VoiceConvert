import Foundation

public enum InputKind: String, Codable, Sendable {
    case audio
    case subtitle
}

public struct ScannedInput: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let kind: InputKind
    public let root: URL
    public let relativePath: String

    public init(id: UUID = UUID(), url: URL, kind: InputKind, root: URL, relativePath: String) {
        self.id = id
        self.url = url.standardizedFileURL
        self.kind = kind
        self.root = root.standardizedFileURL
        self.relativePath = relativePath
    }
}

public enum ScanIssue: Codable, Equatable, Sendable {
    case duplicate(path: String, kept: String)
    case inaccessible(path: String, reason: String)
    case unsupported(path: String)

    private enum CodingKeys: String, CodingKey { case type, path, kept, reason }
    private enum Kind: String, Codable { case duplicate, inaccessible, unsupported }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .duplicate(path, kept):
            try c.encode(Kind.duplicate, forKey: .type); try c.encode(path, forKey: .path); try c.encode(kept, forKey: .kept)
        case let .inaccessible(path, reason):
            try c.encode(Kind.inaccessible, forKey: .type); try c.encode(path, forKey: .path); try c.encode(reason, forKey: .reason)
        case let .unsupported(path):
            try c.encode(Kind.unsupported, forKey: .type); try c.encode(path, forKey: .path)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .duplicate: self = .duplicate(path: try c.decode(String.self, forKey: .path), kept: try c.decode(String.self, forKey: .kept))
        case .inaccessible: self = .inaccessible(path: try c.decode(String.self, forKey: .path), reason: try c.decode(String.self, forKey: .reason))
        case .unsupported: self = .unsupported(path: try c.decode(String.self, forKey: .path))
        }
    }
}

public struct ScanResult: Equatable, Sendable {
    public let inputs: [ScannedInput]
    public let issues: [ScanIssue]
    public init(inputs: [ScannedInput], issues: [ScanIssue]) { self.inputs = inputs; self.issues = issues }
}

public struct WorkflowScanner: Sendable {
    public static let audioExtensions: Set<String> = ["wav", "flac", "aiff", "aif", "m4a"]
    public static let subtitleExtensions: Set<String> = ["vtt"]

    public init() {}

    public func scan(_ urls: [URL], kind: InputKind) -> ScanResult {
        var found: [(URL, URL)] = []
        var issues: [ScanIssue] = []
        for supplied in urls {
            let root = supplied.standardizedFileURL
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                issues.append(.inaccessible(path: root.path, reason: "路径不存在")); continue
            }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                    issues.append(.inaccessible(path: root.path, reason: "无法读取目录")); continue
                }
                for case let child as URL in enumerator {
                    let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                    if values?.isSymbolicLink == true {
                        continue
                    }
                    guard values?.isRegularFile == true else { continue }
                    if supported(child, kind: kind) { found.append((root, child)) }
                }
            } else if supported(root, kind: kind) {
                found.append((root.deletingLastPathComponent(), root))
            } else {
                issues.append(.unsupported(path: root.path))
            }
        }

        var unique: [ScannedInput] = []
        var seen = Set<String>()
        for (root, url) in found.sorted(by: { $0.1.path.localizedStandardCompare($1.1.path) == .orderedAscending }) {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            let key = canonical.path.lowercased()
            guard seen.insert(key).inserted else {
                issues.append(.duplicate(path: url.path, kept: canonical.path)); continue
            }
            let relative = relativePath(of: url.standardizedFileURL, to: root.standardizedFileURL)
            unique.append(ScannedInput(url: canonical, kind: kind, root: root, relativePath: relative))
        }
        return ScanResult(inputs: unique, issues: issues)
    }

    private func supported(_ url: URL, kind: InputKind) -> Bool {
        let ext = url.pathExtension.lowercased()
        return kind == .audio ? Self.audioExtensions.contains(ext) : Self.subtitleExtensions.contains(ext)
    }

    private func relativePath(of url: URL, to root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.lastPathComponent
    }
}

public enum OutputConflictPolicy: String, Codable, Sendable { case suffix, skip, overwrite }

public enum OutputNameError: LocalizedError, Equatable, Sendable {
    case outsideRoot
    case rootCollision
    public var errorDescription: String? {
        switch self { case .outsideRoot: return "输出路径不能离开输出目录"; case .rootCollision: return "输出目录与输入目录重合" }
    }
}

public struct OutputNamePlanner: Sendable {
    public init() {}

    public func plan(input: ScannedInput, outputRoot: URL, outputExtension: String, policy: OutputConflictPolicy, reserved: inout Set<String>) throws -> URL? {
        let root = outputRoot.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let relativeURL = URL(fileURLWithPath: input.relativePath)
        guard !input.relativePath.hasPrefix("/"), !relativeURL.pathComponents.contains("..") else {
            throw OutputNameError.outsideRoot
        }
        let relative = input.relativePath as NSString
        let relativeDirectory = relative.deletingLastPathComponent
        let sourceStem = relativeURL.deletingPathExtension().lastPathComponent
        guard !sourceStem.isEmpty else { throw OutputNameError.outsideRoot }
        var candidate = root.appendingPathComponent(relativeDirectory, isDirectory: true).appendingPathComponent(sourceStem).appendingPathExtension(outputExtension).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            throw OutputNameError.outsideRoot
        }
        let inputRoot = input.root.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        let outputCanonical = root.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        let inputRootPrefix = inputRoot.hasSuffix("/") ? inputRoot : inputRoot + "/"
        let outputRootPrefix = outputCanonical.hasSuffix("/") ? outputCanonical : outputCanonical + "/"
        if inputRoot == outputCanonical || inputRoot.hasPrefix(outputRootPrefix) || outputCanonical.hasPrefix(inputRootPrefix) {
            throw OutputNameError.rootCollision
        }
        if policy == .skip && (reserved.contains(key(candidate)) || FileManager.default.fileExists(atPath: candidate.path)) { return nil }
        if policy == .suffix {
            var index = 0
            while reserved.contains(key(candidate)) || FileManager.default.fileExists(atPath: candidate.path) {
                index += 1
                candidate = root.appendingPathComponent(relativeDirectory, isDirectory: true).appendingPathComponent("\(sourceStem) (\(index))").appendingPathExtension(outputExtension).standardizedFileURL
            }
        }
        reserved.insert(key(candidate))
        return candidate
    }

    private func key(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }
}

public struct AudioSubtitlePair: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let audio: ScannedInput
    public let subtitle: ScannedInput
    public let outputSubdirectory: String?
    public init(id: UUID = UUID(), audio: ScannedInput, subtitle: ScannedInput, outputSubdirectory: String? = nil) {
        self.id = id; self.audio = audio; self.subtitle = subtitle; self.outputSubdirectory = outputSubdirectory
    }
}

public struct PairingIssue: Codable, Equatable, Sendable {
    public let audio: URL?
    public let subtitle: URL?
    public let reason: String
    public init(audio: URL? = nil, subtitle: URL? = nil, reason: String) { self.audio = audio; self.subtitle = subtitle; self.reason = reason }
}

public struct PairingResult: Equatable, Sendable {
    public let pairs: [AudioSubtitlePair]
    public let issues: [PairingIssue]
    public init(pairs: [AudioSubtitlePair], issues: [PairingIssue]) { self.pairs = pairs; self.issues = issues }
}

public struct PairingMatcher: Sendable {
    public init() {}
    public func match(audio: [ScannedInput], subtitles: [ScannedInput]) -> PairingResult {
        var audioByStem: [String: [ScannedInput]] = [:]
        var subtitleByStem: [String: [ScannedInput]] = [:]
        for item in audio { audioByStem[safeStem(item.url, isSubtitle: false), default: []].append(item) }
        for item in subtitles { subtitleByStem[safeStem(item.url, isSubtitle: true), default: []].append(item) }

        var pairs: [AudioSubtitlePair] = []
        var issues: [PairingIssue] = []
        let keys = Set(audioByStem.keys).union(subtitleByStem.keys).sorted()
        for key in keys {
            let matchingAudio = audioByStem[key] ?? []
            let matchingSubtitles = subtitleByStem[key] ?? []
            if matchingAudio.count == 1 && matchingSubtitles.count == 1 {
                pairs.append(AudioSubtitlePair(audio: matchingAudio[0], subtitle: matchingSubtitles[0]))
            } else {
                if matchingSubtitles.isEmpty {
                    for item in matchingAudio { issues.append(PairingIssue(audio: item.url, reason: "未找到匹配字幕")) }
                } else if matchingAudio.isEmpty {
                    for item in matchingSubtitles { issues.append(PairingIssue(subtitle: item.url, reason: "未找到匹配音频")) }
                } else if matchingAudio.count > 1 {
                    for item in matchingSubtitles { issues.append(PairingIssue(subtitle: item.url, reason: "匹配音频不唯一")) }
                } else {
                    for item in matchingSubtitles { issues.append(PairingIssue(subtitle: item.url, reason: "匹配字幕不唯一")) }
                }
            }
        }
        return PairingResult(pairs: pairs, issues: issues)
    }
    private func safeStem(_ url: URL, isSubtitle: Bool) -> String {
        var stem = url.deletingPathExtension().lastPathComponent
        if isSubtitle {
            let lower = stem.lowercased()
            let extensions = ["mp3", "wav", "flac", "aiff", "aif", "m4a"]
            if let matched = extensions.first(where: { lower.hasSuffix(".\($0)") }) {
                stem = String(stem.dropLast(matched.count + 1))
            }
        }
        return stem.precomposedStringWithCanonicalMapping.lowercased()
    }
}

public struct InputSnapshot: Codable, Equatable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let modificationDate: Date?
    public init(url: URL, byteCount: Int64, modificationDate: Date?) { path = url.standardizedFileURL.path; self.byteCount = byteCount; self.modificationDate = modificationDate }
    public init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadNoSuchFile) }
        self.init(url: url, byteCount: Int64(values.fileSize ?? 0), modificationDate: values.contentModificationDate)
    }
    public func matchesCurrentFile() -> Bool { guard let current = try? InputSnapshot(url: URL(fileURLWithPath: path)) else { return false }; return current == self }
}

public enum TaskStatus: Codable, Equatable, Sendable {
    case waiting, running, succeeded, succeededWithWarnings([String]), skipped(String), failed(String), cancelled
    private enum CodingKeys: String, CodingKey { case type, warnings, reason }
    private enum Kind: String, Codable { case waiting, running, succeeded, succeededWithWarnings, skipped, failed, cancelled }
    public func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); switch self { case .waiting: try c.encode(Kind.waiting, forKey: .type); case .running: try c.encode(Kind.running, forKey: .type); case .succeeded: try c.encode(Kind.succeeded, forKey: .type); case let .succeededWithWarnings(w): try c.encode(Kind.succeededWithWarnings, forKey: .type); try c.encode(w, forKey: .warnings); case let .skipped(r): try c.encode(Kind.skipped, forKey: .type); try c.encode(r, forKey: .reason); case let .failed(r): try c.encode(Kind.failed, forKey: .type); try c.encode(r, forKey: .reason); case .cancelled: try c.encode(Kind.cancelled, forKey: .type) } }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); switch try c.decode(Kind.self, forKey: .type) { case .waiting: self = .waiting; case .running: self = .running; case .succeeded: self = .succeeded; case .succeededWithWarnings: self = .succeededWithWarnings(try c.decode([String].self, forKey: .warnings)); case .skipped: self = .skipped(try c.decode(String.self, forKey: .reason)); case .failed: self = .failed(try c.decode(String.self, forKey: .reason)); case .cancelled: self = .cancelled } }
}

public struct WorkflowTask: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let parentID: UUID?
    public let inputURL: URL
    public let role: WorkflowTaskRole
    public let operation: PairTaskOperation?
    public var outputURL: URL?
    public var status: TaskStatus
    public var progress: Double
    public var snapshot: InputSnapshot?
    public init(id: UUID = UUID(), parentID: UUID? = nil, inputURL: URL, outputURL: URL? = nil, status: TaskStatus = .waiting, progress: Double = 0, snapshot: InputSnapshot? = nil, role: WorkflowTaskRole = .audio, operation: PairTaskOperation? = nil) {
        self.id = id; self.parentID = parentID; self.inputURL = inputURL; self.role = role; self.operation = operation; self.outputURL = outputURL; self.status = status; self.progress = progress; self.snapshot = snapshot
    }

    private enum CodingKeys: String, CodingKey { case id, parentID, inputURL, role, operation, outputURL, status, progress, snapshot }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        inputURL = try c.decode(URL.self, forKey: .inputURL)
        role = try c.decodeIfPresent(WorkflowTaskRole.self, forKey: .role) ?? (parentID == nil ? .audio : .audio)
        operation = try c.decodeIfPresent(PairTaskOperation.self, forKey: .operation)
        outputURL = try c.decodeIfPresent(URL.self, forKey: .outputURL)
        status = try c.decode(TaskStatus.self, forKey: .status)
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        snapshot = try c.decodeIfPresent(InputSnapshot.self, forKey: .snapshot)
    }
}

public struct BatchRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let schemaVersion: Int
    public let startedAt: Date
    public var finishedAt: Date?
    public var tasks: [WorkflowTask]
    public var outputRoot: URL?
    public var generateMP3: Bool?
    public var generateLRC: Bool?
    public var outputSubdirectory: String?
    public var conflictPolicy: OutputConflictPolicy?
    public var warnings: [String]

    public init(
        id: UUID = UUID(), schemaVersion: Int = 1, startedAt: Date = .now,
        finishedAt: Date? = nil, tasks: [WorkflowTask] = [], outputRoot: URL? = nil,
        generateMP3: Bool? = nil, generateLRC: Bool? = nil, outputSubdirectory: String? = nil,
        conflictPolicy: OutputConflictPolicy? = nil, warnings: [String] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.tasks = tasks
        self.outputRoot = outputRoot
        self.generateMP3 = generateMP3
        self.generateLRC = generateLRC
        self.outputSubdirectory = outputSubdirectory
        self.conflictPolicy = conflictPolicy
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, startedAt, finishedAt, tasks, outputRoot
        case generateMP3, generateLRC, outputSubdirectory, conflictPolicy, warnings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        tasks = try c.decode([WorkflowTask].self, forKey: .tasks)
        outputRoot = try c.decodeIfPresent(URL.self, forKey: .outputRoot)
        generateMP3 = try c.decodeIfPresent(Bool.self, forKey: .generateMP3)
        generateLRC = try c.decodeIfPresent(Bool.self, forKey: .generateLRC)
        outputSubdirectory = try c.decodeIfPresent(String.self, forKey: .outputSubdirectory)
        conflictPolicy = try c.decodeIfPresent(OutputConflictPolicy.self, forKey: .conflictPolicy)
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}


public enum WorkflowTaskRole: String, Codable, Sendable {
    case pairing
    case audio
    case subtitle
}

public enum PairOutputKind: String, Codable, Sendable {
    case mp3
    case lrc
}

public struct PairOutputPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let pairID: UUID
    public let audioURL: URL
    public let subtitleURL: URL
    public let mp3URL: URL?
    public let lrcURL: URL?
    public let policy: OutputConflictPolicy

    public init(
        id: UUID = UUID(), pairID: UUID, audioURL: URL, subtitleURL: URL,
        mp3URL: URL?, lrcURL: URL?, policy: OutputConflictPolicy
    ) {
        self.id = id
        self.pairID = pairID
        self.audioURL = audioURL.standardizedFileURL
        self.subtitleURL = subtitleURL.standardizedFileURL
        self.mp3URL = mp3URL?.standardizedFileURL
        self.lrcURL = lrcURL?.standardizedFileURL
        self.policy = policy
    }
}

public struct PairBatchPlan: Codable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let outputRoot: URL
    public let generateMP3: Bool
    public let generateLRC: Bool
    public let outputSubdirectory: String?
    public let plans: [PairOutputPlan]
    public var tasks: [WorkflowTask]

    public init(
        id: UUID = UUID(), startedAt: Date = .now, outputRoot: URL,
        generateMP3: Bool = true, generateLRC: Bool = true,
        outputSubdirectory: String? = nil, plans: [PairOutputPlan], tasks: [WorkflowTask]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.outputRoot = outputRoot.standardizedFileURL
        self.generateMP3 = generateMP3
        self.generateLRC = generateLRC
        self.outputSubdirectory = outputSubdirectory
        self.plans = plans
        self.tasks = tasks
    }

    public var batchRecord: BatchRecord {
        let warnings = tasks.flatMap { task -> [String] in
            if case let .succeededWithWarnings(values) = task.status { return values }
            return []
        }
        return BatchRecord(
            id: id,
            startedAt: startedAt,
            tasks: tasks,
            outputRoot: outputRoot,
            generateMP3: generateMP3,
            generateLRC: generateLRC,
            outputSubdirectory: outputSubdirectory,
            conflictPolicy: plans.first?.policy,
            warnings: warnings
        )
    }
}

public enum PairPlanError: LocalizedError, Equatable, Sendable {
    case noOutputsSelected
    case invalidSubdirectory
    case outputRootCollision
    public var errorDescription: String? {
        switch self {
        case .noOutputsSelected: return "至少选择一种输出"
        case .invalidSubdirectory: return "输出子目录无效"
        case .outputRootCollision: return "输出目录与输入目录重合"
        }
    }
}

public struct PairBatchPlanner: Sendable {
    public init() {}

    public func makePlan(
        from result: PairingResult,
        outputRoot: URL,
        outputSubdirectory: String? = nil,
        generateMP3: Bool = true,
        generateLRC: Bool = true,
        policy: OutputConflictPolicy = .suffix
    ) throws -> PairBatchPlan {
        guard generateMP3 || generateLRC else { throw PairPlanError.noOutputsSelected }
        let subdirectory = try normalizedSubdirectory(outputSubdirectory)
        let root = outputRoot.standardizedFileURL
        var reserved = Set<String>()
        var outputPlans: [PairOutputPlan] = []
        var tasks: [WorkflowTask] = []
        for pair in result.pairs {
            let parentID = UUID()
            let relativePath = pair.audio.relativePath as NSString
            let relativeDirectory = relativePath.deletingLastPathComponent
            let stemURL = URL(fileURLWithPath: relativePath as String)
            let stem = stemURL.deletingPathExtension().lastPathComponent
            guard !stem.isEmpty else { continue }
            let directory = root
                .appendingPathComponent(subdirectory ?? "", isDirectory: true)
                .appendingPathComponent(relativeDirectory, isDirectory: true)
                .standardizedFileURL
            guard isInside(directory, root: root) else { throw PairPlanError.invalidSubdirectory }
            guard !rootsCollide(pair.audio.root, root) else { throw PairPlanError.outputRootCollision }
            let base = directory.appendingPathComponent(stem)
            let candidate = try pairedCandidate(base: base, policy: policy, reserved: &reserved,
                                                needMP3: generateMP3, needLRC: generateLRC)
            let mp3 = generateMP3 ? candidate.appendingPathExtension("mp3") : nil
            let lrc = generateLRC ? candidate.appendingPathExtension("lrc") : nil
            let outputPlan = PairOutputPlan(pairID: pair.id, audioURL: pair.audio.url, subtitleURL: pair.subtitle.url,
                                            mp3URL: mp3, lrcURL: lrc, policy: policy)
            outputPlans.append(outputPlan)
            let parent = WorkflowTask(id: parentID, parentID: nil, inputURL: pair.audio.url, role: .pairing, operation: nil,
                                      outputURL: mp3, status: .waiting, progress: 0,
                                      snapshot: try? InputSnapshot(url: pair.audio.url))
            tasks.append(parent)
            if generateMP3 {
                tasks.append(WorkflowTask(parentID: parentID, inputURL: pair.audio.url, role: .audio, operation: .mp3,
                                           outputURL: mp3, snapshot: try? InputSnapshot(url: pair.audio.url)))
            }
            if generateLRC {
                tasks.append(WorkflowTask(parentID: parentID, inputURL: pair.subtitle.url, role: .subtitle, operation: .lrc,
                                           outputURL: lrc, snapshot: try? InputSnapshot(url: pair.subtitle.url)))
            }
        }
        return PairBatchPlan(outputRoot: root, generateMP3: generateMP3, generateLRC: generateLRC,
                             outputSubdirectory: subdirectory, plans: outputPlans, tasks: tasks)
    }

    private func normalizedSubdirectory(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        let url = URL(fileURLWithPath: value)
        guard !value.hasPrefix("/"), !url.pathComponents.contains(".."), value != "." else {
            throw PairPlanError.invalidSubdirectory
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func isInside(_ candidate: URL, root: URL) -> Bool {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(prefix)
    }

    private func rootsCollide(_ input: URL, _ output: URL) -> Bool {
        let a = input.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        let b = output.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        let ap = a.hasSuffix("/") ? a : a + "/"
        let bp = b.hasSuffix("/") ? b : b + "/"
        return a == b || a.hasPrefix(bp) || b.hasPrefix(ap)
    }

    private func pairedCandidate(base: URL, policy: OutputConflictPolicy, reserved: inout Set<String>, needMP3: Bool, needLRC: Bool) throws -> URL {
        func occupied(_ url: URL) -> Bool {
            reserved.contains(url.path.lowercased()) || FileManager.default.fileExists(atPath: url.path)
        }
        func pairOccupied(_ stem: URL) -> Bool {
            (needMP3 && occupied(stem.appendingPathExtension("mp3"))) ||
            (needLRC && occupied(stem.appendingPathExtension("lrc")))
        }
        var candidate = base
        if policy == .suffix {
            var index = 0
            while pairOccupied(candidate) {
                index += 1
                candidate = base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent) (\(index))")
            }
        }
        if policy == .skip && pairOccupied(candidate) { return candidate }
        if needMP3 { reserved.insert(candidate.appendingPathExtension("mp3").path.lowercased()) }
        if needLRC { reserved.insert(candidate.appendingPathExtension("lrc").path.lowercased()) }
        return candidate
    }
}

public enum PairTaskOperation: String, Codable, Sendable { case mp3, lrc }

public extension WorkflowTask {
    init(
        id: UUID = UUID(), parentID: UUID? = nil, inputURL: URL, role: WorkflowTaskRole,
        operation: PairTaskOperation?, outputURL: URL? = nil, status: TaskStatus = .waiting,
        progress: Double = 0, snapshot: InputSnapshot? = nil
    ) {
        self.init(id: id, parentID: parentID, inputURL: inputURL, outputURL: outputURL,
                  status: status, progress: progress, snapshot: snapshot, role: role, operation: operation)
    }
}

public struct RecentBatchStore: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public private(set) var batches: [BatchRecord]
    public init(batches: [BatchRecord] = []) { self.batches = Array(batches.prefix(30)) }
    public mutating func append(_ batch: BatchRecord) { batches.insert(batch, at: 0); if batches.count > 30 { batches.removeLast(batches.count - 30) } }
}
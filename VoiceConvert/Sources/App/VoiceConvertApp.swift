import SwiftUI
import UniformTypeIdentifiers
import Combine
import AppKit

@main
struct VoiceConvertApp: App {
    var body: some Scene { WindowGroup("音声转换") { ContentView() }.defaultSize(width: 980, height: 680) }
}

enum WorkspaceModule: String, CaseIterable, Identifiable {
    case audio = "音频转换", subtitle = "字幕转换", pairing = "配对处理"
    var id: String { rawValue }
    var icon: String { switch self { case .audio: return "waveform"; case .subtitle: return "captions.bubble"; case .pairing: return "link" } }
}

private final class PairCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

@MainActor
final class VoiceConvertViewModel: ObservableObject {
    @Published var module: WorkspaceModule = .audio
    @Published var audioItems: [QueueItem] = []
    @Published var summary = QueueSummary(total: 0, succeeded: 0, failed: 0, cancelled: 0)
    @Published var config = ConversionConfig()
    @Published var subtitleFiles: [URL] = []
    @Published var subtitleResults: [URL: FileConversionOutcome] = [:]
    @Published var pairResult: PairingResult?
    @Published var strictMode = false
    @Published var keepSpeakers = false
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var banner: String?
    @Published var pairPlan: PairBatchPlan?
    @Published var pairTasks: [WorkflowTask] = []
    @Published var pairGenerateMP3 = true
    @Published var pairGenerateLRC = true
    @Published var pairOutputSubdirectory = ""
    @Published var pairConflictPolicy: OutputConflictPolicy = .suffix
    @Published var recentBatches = RecentBatchStore()
    @Published var confirmOverwritePresented = false
    @Published var settingsPanelPresented = false
    @Published var exportSettingsPresented = false
    @Published var importSettingsPresented = false
    @Published var exportDiagnosticPresented = false
    @Published var licensePresented = false
    @Published var outputDirectoryBookmark: SecurityScopedBookmark?
    @Published var outputDirectoryAccessActive = false
    private var activeOutputDirectory: URL?
    private var pairingAudio: [ScannedInput] = []
    private var pairingSubtitles: [ScannedInput] = []
    private let pairCancellation = PairCancellation()
    private var overwriteContinuation: CheckedContinuation<Bool, Never>?
    private let queue = BatchQueue()
    private var task: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "VoiceConvert.ConversionConfig"), let saved = try? JSONDecoder().decode(ConversionConfig.self, from: data) { config = saved }
        strictMode = UserDefaults.standard.bool(forKey: "VoiceConvert.StrictMode")
        keepSpeakers = UserDefaults.standard.bool(forKey: "VoiceConvert.KeepSpeakers")
        if let url = recentBatchURL, let saved = try? RecentBatchStore.load(from: url) { recentBatches = saved }
        if let bookmark = try? AppSettingsController.loadBookmark() {
            outputDirectoryBookmark = bookmark
            if let resolved = try? AppSettingsController.resolveBookmark(bookmark) {
                config.outputDirectory = resolved
                activeOutputDirectory = resolved
                outputDirectoryAccessActive = resolved.startAccessingSecurityScopedResource()
            } else {
                banner = AppSettingsError.invalidBookmark.localizedDescription
                try? AppSettingsController.saveBookmark(nil)
            }
        }
    }
    private var recentBatchURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("VoiceConvert", isDirectory: true)
            .appendingPathComponent("recent-batches.json")
    }
    func chooseOutputDirectory() {
        guard !isRunning else { banner = "任务运行期间不能更改输出目录"; return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            if let activeOutputDirectory { activeOutputDirectory.stopAccessingSecurityScopedResource() }
            let bookmark = try AppSettingsController.bookmark(from: directory)
            let resolved = try AppSettingsController.resolveBookmark(bookmark)
            outputDirectoryBookmark = bookmark
            activeOutputDirectory = resolved
            outputDirectoryAccessActive = resolved.startAccessingSecurityScopedResource()
            config.outputDirectory = resolved
            try AppSettingsController.saveBookmark(bookmark)
            persist()
            rebuildPairPlan()
            banner = "输出目录已更新"
        } catch {
            banner = error.localizedDescription
        }
    }

    private var currentSettingsSnapshot: SettingsSnapshot {
        SettingsSnapshot(
            vbrQuality: config.vbrQuality.rawValue,
            concurrency: config.concurrency,
            outputDirectory: config.outputDirectory,
            deleteSourceOnSuccess: config.deleteSourceOnSuccess,
            strictMode: strictMode,
            keepSpeakerPrefixes: keepSpeakers
        )
    }

    func exportSettings(to url: URL) {
        do { try AppSettingsController.exportSettings(currentSettingsSnapshot, to: url); banner = "设置已导出" }
        catch { banner = "设置导出失败：\(error.localizedDescription)" }
    }

    func importSettings(from url: URL) {
        guard !isRunning else { banner = AppSettingsError.importWhileRunning.localizedDescription; return }
        do {
            let snapshot = try AppSettingsController.importSettings(from: url)
            var runtime = SettingsRuntimeState(preferences: currentSettingsSnapshot, outputDirectoryBookmark: outputDirectoryBookmark?.data, recentBatches: recentBatches, runningTasks: pairTasks)
            SettingsImportPolicy.apply(snapshot, to: &runtime)
            config = ConversionConfig(vbrQuality: VBRQuality(rawValue: snapshot.vbrQuality) ?? .v2, concurrency: snapshot.concurrency, deleteSourceOnSuccess: snapshot.deleteSourceOnSuccess, outputDirectory: snapshot.outputDirectory)
            strictMode = snapshot.strictMode
            keepSpeakers = snapshot.keepSpeakerPrefixes
            persist()
            rebuildPairPlan()
            banner = "设置已导入"
        } catch { banner = "设置导入失败：\(error.localizedDescription)" }
    }

    func exportSettingsFromPanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "音声转换-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportSettings(to: url)
    }

    func importSettingsFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importSettings(from: url)
    }

    func exportDiagnosticFromPanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "音声转换-diagnostic.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportDiagnostic(to: url)
    }
    func exportDiagnostic(to url: URL) {
        let report = AppSettingsController.diagnosticReport(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0", recentBatchCount: recentBatches.batches.count, tasks: pairTasks)
        do { try report.save(to: url); banner = "诊断报告已导出" }
        catch { banner = "诊断报告导出失败：\(error.localizedDescription)" }
    }

    func clearOutputDirectoryBookmark() {
        activeOutputDirectory?.stopAccessingSecurityScopedResource()
        activeOutputDirectory = nil
        outputDirectoryAccessActive = false
        outputDirectoryBookmark = nil
        config.outputDirectory = nil
        try? AppSettingsController.saveBookmark(nil)
        persist()
        rebuildPairPlan()
    }
    func add(_ urls: [URL]) {
        switch module {
        case .audio: queue.enqueue(urls); sync()
        case .subtitle:
            let result = WorkflowScanner().scan(urls, kind: .subtitle)
            subtitleFiles = Array(Set(subtitleFiles + result.inputs.map(\.url))).sorted { $0.path < $1.path }
            if !result.issues.isEmpty { banner = "已跳过 \(result.issues.count) 个重复或不可用输入" }
        case .pairing:
            let scanner = WorkflowScanner()
            let audio = scanner.scan(urls, kind: .audio).inputs
            let vtt = scanner.scan(urls, kind: .subtitle).inputs
            pairingAudio = mergeScanned(pairingAudio, audio)
            pairingSubtitles = mergeScanned(pairingSubtitles, vtt)
            pairResult = PairingMatcher().match(audio: pairingAudio, subtitles: pairingSubtitles)
            rebuildPairPlan()
        }
    }
    func startAudio() {
        guard !audioItems.isEmpty, !isRunning else { return }
        isRunning = true; persist()
        task = Task { [weak self] in guard let self else { return }; await queue.run(config: config); sync(); isRunning = false; isPaused = false }
    }
    func convertSubtitles() {
        let mode: SubtitleConversionMode = strictMode ? .strict : .lenient; let converter = VttToLrcConverter()
        for file in subtitleFiles { subtitleResults[file] = converter.convertFile(at: file, keepSpeakers: keepSpeakers, mode: mode) }
        banner = "字幕批次已完成"
    }
    func clearAudio() { queue.clear(); sync() }
    func pause() { queue.pause(); sync() }
    func resume() { queue.resume(); sync() }
    func cancel() { queue.cancel(); sync() }
    func startPairing() {
        guard let pairResult, !pairResult.pairs.isEmpty, !isRunning else { return }
        do {
            let outputRoot = config.outputDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/音声库")
            let plan = try PairBatchPlanner().makePlan(from: pairResult, outputRoot: outputRoot,
                                                       outputSubdirectory: pairOutputSubdirectory.isEmpty ? nil : pairOutputSubdirectory,
                                                       generateMP3: pairGenerateMP3, generateLRC: pairGenerateLRC,
                                                       policy: pairConflictPolicy)
            pairPlan = plan
            pairTasks = plan.tasks
            pairCancellation.reset()
            isRunning = true
            let settings = config
            let speakers = keepSpeakers
            let conversionMode: SubtitleConversionMode = strictMode ? .strict : .lenient
            task = Task { [weak self] in
                guard let self else { return }
                let completed = await PairBatchExecutor().execute(plan: plan, audioExecutor: { input, output, progress, cancelled, overwrite in
                    do {
                        _ = try ConversionEngine().convert(inputURL: input, outputURL: output, config: settings,
                                                           progress: progress, isCancelled: cancelled, overwrite: overwrite)
                        return .succeeded
                    } catch let error as ConversionError where error == .cancelled { return .cancelled }
                    catch { return .failed(error.localizedDescription) }
                }, isCancelled: { self.pairCancellation.isCancelled() || Task.isCancelled },
                confirmOverwrite: { await self.requestOverwrite() }, keepSpeakers: speakers, mode: conversionMode,
                progress: { [weak self] taskID, value in
                    Task { @MainActor in
                        guard let self else { return }
                        guard let index = self.pairTasks.firstIndex(where: { $0.id == taskID }) else { return }
                        self.pairTasks[index].progress = value
                    }
                })
                await MainActor.run { self.finishPairing(completed, message: "配对批次已完成") }
            }
        } catch { banner = error.localizedDescription }
    }

    func cancelPairing() {
        pairCancellation.cancel()
        resolveOverwrite(false)
        task?.cancel()
        isRunning = false
        banner = "配对批次已取消"
    }

    func retryPairing() {
        guard let plan = pairPlan, !isRunning else { return }
        pairCancellation.reset()
        isRunning = true
        let settings = config
        let speakers = keepSpeakers
        let conversionMode: SubtitleConversionMode = strictMode ? .strict : .lenient
        task = Task { [weak self] in
            guard let self else { return }
            let completed = await PairBatchExecutor().retry(plan: plan, audioExecutor: { input, output, progress, cancelled, overwrite in
                do {
                    _ = try ConversionEngine().convert(inputURL: input, outputURL: output, config: settings,
                                                       progress: progress, isCancelled: cancelled, overwrite: overwrite)
                    return .succeeded
                } catch let error as ConversionError where error == .cancelled { return .cancelled }
                catch { return .failed(error.localizedDescription) }
            }, isCancelled: { self.pairCancellation.isCancelled() || Task.isCancelled },
            confirmOverwrite: { await self.requestOverwrite() }, keepSpeakers: speakers, mode: conversionMode)
            await MainActor.run { self.finishPairing(completed, message: "失败子任务已重试") }
        }
    }

    private func requestOverwrite() async -> Bool {
        await withCheckedContinuation { continuation in
            overwriteContinuation = continuation
            confirmOverwritePresented = true
        }
    }

    func resolveOverwrite(_ accepted: Bool) {
        confirmOverwritePresented = false
        let continuation = overwriteContinuation
        overwriteContinuation = nil
        continuation?.resume(returning: accepted)
    }

    private func finishPairing(_ completed: PairBatchPlan, message: String) {
        pairPlan = completed
        pairTasks = completed.tasks
        isRunning = false
        banner = message
        var history = recentBatches
        var record = completed.batchRecord
        record.finishedAt = .now
        history.append(record)
        recentBatches = history
        if let url = recentBatchURL { try? history.save(to: url) }
    }
    private func rebuildPairPlan() {
        guard let pairResult else { pairPlan = nil; pairTasks = []; return }
        let root = config.outputDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/音声库")
        pairPlan = try? PairBatchPlanner().makePlan(from: pairResult, outputRoot: root,
                                                      outputSubdirectory: pairOutputSubdirectory.isEmpty ? nil : pairOutputSubdirectory,
                                                      generateMP3: pairGenerateMP3, generateLRC: pairGenerateLRC,
                                                      policy: pairConflictPolicy)
        pairTasks = pairPlan?.tasks ?? []
    }
    func rebuildPairPlanForUI() { rebuildPairPlan() }
    func taskStatusText(_ status: TaskStatus) -> String {
        switch status {
        case .waiting: return "等待"
        case .running: return "处理中"
        case .succeeded: return "成功"
        case .succeededWithWarnings(let warnings): return "成功（\(warnings.count) 条警告）"
        case .skipped(let reason): return "已跳过：\(reason)"
        case .failed(let reason): return "失败：\(reason)"
        case .cancelled: return "已取消"
        }
    }
    func persist() {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: "VoiceConvert.ConversionConfig") }
        UserDefaults.standard.set(strictMode, forKey: "VoiceConvert.StrictMode")
        UserDefaults.standard.set(keepSpeakers, forKey: "VoiceConvert.KeepSpeakers")
    }
    private func mergeScanned(_ current: [ScannedInput], _ additions: [ScannedInput]) -> [ScannedInput] {
        var byPath = Dictionary(uniqueKeysWithValues: current.map { ($0.url.standardizedFileURL.path.lowercased(), $0) })
        for item in additions { byPath[item.url.standardizedFileURL.path.lowercased()] = item }
        return byPath.values.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }
    private func sync() { audioItems = queue.items; summary = queue.summary; isRunning = queue.isRunning; isPaused = queue.isPaused }
}

struct ContentView: View {
    @StateObject private var model = VoiceConvertViewModel()
    var body: some View {
        NavigationSplitView {
            List(WorkspaceModule.allCases, selection: $model.module) { item in Label(item.rawValue, systemImage: item.icon).tag(item) }
                .navigationTitle("音声转换")
                .safeAreaInset(edge: .bottom) { Text("最近批次\n音频 \(model.summary.succeeded)/\(model.summary.total)；字幕 \(model.subtitleResults.count) 个").font(.caption).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading) }
        } detail: {
            VStack(spacing: 0) { header; Divider(); detail }
                .frame(minWidth: 720, minHeight: 560)
                .overlay(alignment: .bottom) { if let banner = model.banner { Text(banner).padding(10).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 8)).padding(12) } }
                .onDrop(of: [UTType.fileURL], isTargeted: .constant(false)) { providers in
                    for provider in providers { _ = provider.loadObject(ofClass: NSURL.self) { object, _ in if let url = (object as? NSURL) as URL? { Task { @MainActor in model.add([url]) } } } }; return true
                }
        }.onChange(of: model.config) { _, _ in model.persist() }
            .sheet(isPresented: $model.settingsPanelPresented) { SettingsView(model: model) }
    }
    private var header: some View { HStack { Image(systemName: model.module.icon).font(.title2).foregroundStyle(.tint); VStack(alignment: .leading) { Text(String(localized: "module.\(model.module.id)")); Text(description).font(.callout).foregroundStyle(.secondary) }; Spacer(); Button { model.settingsPanelPresented = true } label: { Label(String(localized: "settings.title"), systemImage: "gear") }.accessibilityLabel(String(localized: "settings.title")); Button { choose() } label: { Label(String(localized: "action.addInput"), systemImage: "plus") }.disabled(model.isRunning) }.padding(18) }
    @ViewBuilder private var detail: some View { switch model.module { case .audio: AudioView(model: model); case .subtitle: SubtitleView(model: model); case .pairing: PairView(model: model) } }
    private var description: String { switch model.module { case .audio: return "WAV、FLAC、AIFF、AIF、M4A → MP3"; case .subtitle: return "WebVTT → UTF-8 LRC"; case .pairing: return "安全主干名唯一匹配" } }
    private func choose() { let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true; p.prompt = "添加"; if p.runModal() == .OK { model.add(p.urls) } }
}

struct SettingsView: View {
    @ObservedObject var model: VoiceConvertViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "settings.title")).font(.title2.bold())
                Spacer()
                Button(String(localized: "action.done")) { dismiss() }
            }
            GroupBox(String(localized: "settings.outputDirectory")) {
                HStack {
                    Image(systemName: model.outputDirectoryAccessActive ? "checkmark.shield" : "folder")
                    Text(model.config.outputDirectory?.lastPathComponent ?? String(localized: "settings.outputDirectory.default"))
                        .lineLimit(1)
                    Spacer()
                    Button(String(localized: "action.choose")) { model.chooseOutputDirectory() }
                    if model.outputDirectoryBookmark != nil {
                        Button { model.clearOutputDirectoryBookmark() } label: { Image(systemName: "trash") }
                            .help(String(localized: "action.clear"))
                    }
                }
            }
            Form {
                Picker(String(localized: "settings.quality"), selection: $model.config.vbrQuality) {
                    ForEach(VBRQuality.allCases) { quality in Text(quality.displayName).tag(quality) }
                }
                Stepper(String(format: String(localized: "settings.concurrency"), model.config.concurrency), value: $model.config.concurrency, in: 1...8)
                Toggle(String(localized: "settings.deleteSource"), isOn: $model.config.deleteSourceOnSuccess)
                Toggle(String(localized: "settings.strict"), isOn: $model.strictMode)
                Toggle(String(localized: "settings.speakers"), isOn: $model.keepSpeakers)
            }
            HStack {
                Button(String(localized: "settings.export")) { model.exportSettingsFromPanel() }
                Button(String(localized: "settings.import")) { model.importSettingsFromPanel() }
                Button(String(localized: "settings.diagnostic")) { model.exportDiagnosticFromPanel() }
                Button(String(localized: "settings.licenses")) { model.licensePresented = true }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 420)
        .sheet(isPresented: $model.licensePresented) { LicenseView() }
    }
}

struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "license.title")).font(.title2.bold())
                Spacer()
                Button(String(localized: "action.done")) { dismiss() }
            }
            Text(String(localized: "license.body"))
                .textSelection(.enabled)
            ScrollView {
                Text("LAME: ThirdParty/licenses/LAME_COPYING 和 LAME_LICENSE\nmpg123: ThirdParty/licenses/MPG123_COPYING 和 MPG123_AUTHORS\n\nNOTICE 和完整许可证文件随仓库保存在 ThirdParty/licenses/。当前二进制来源和精确版本仍待核查。")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 620, height: 360)
    }
}

struct AudioView: View {
    @ObservedObject var model: VoiceConvertViewModel

    var body: some View {
        VStack(spacing: 14) {
            DropHint(text: "拖入音频文件或文件夹", detail: "支持 WAV、FLAC、AIFF、AIF、M4A，目录递归扫描")
            HStack {
                GroupBox("转换队列") {
                    if model.audioItems.isEmpty {
                        ContentUnavailableView("队列为空", systemImage: "tray")
                    } else {
                        List(model.audioItems) { item in Text(item.inputURL.lastPathComponent) }
                    }
                }
                .frame(maxWidth: .infinity)
                Form {
                    Picker("质量", selection: $model.config.vbrQuality) {
                        ForEach(VBRQuality.allCases) { quality in Text(quality.displayName).tag(quality) }
                    }
                    Toggle("完整立体声", isOn: $model.config.fullStereo)
                    Stepper("并发数：\(model.config.concurrency)", value: $model.config.concurrency, in: 1...8)
                }
                .formStyle(.grouped)
                .frame(width: 240)
            }
            HStack {
                Text("\(model.summary.succeeded) 成功 · \(model.summary.failed) 失败").foregroundStyle(.secondary)
                Spacer()
                if model.isRunning {
                    Button(model.isPaused ? "继续" : "暂停") { model.isPaused ? model.resume() : model.pause() }
                    Button("取消") { model.cancel() }
                } else {
                    Button { model.startAudio() } label: { Label("开始转换", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(18)
    }
}

struct SubtitleView: View {
    @ObservedObject var model: VoiceConvertViewModel

    var body: some View {
        VStack(spacing: 14) {
            DropHint(text: "拖入 WebVTT 文件或文件夹", detail: "输出同目录 UTF-8 无 BOM LRC")
            HStack {
                GroupBox("字幕清单") {
                    if model.subtitleFiles.isEmpty {
                        ContentUnavailableView("暂无字幕", systemImage: "captions.bubble")
                    } else {
                        List(model.subtitleFiles, id: \.self) { file in
                            HStack { Text(file.lastPathComponent); Spacer(); Text(status(file)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                Form {
                    Toggle("严格模式", isOn: $model.strictMode)
                    Toggle("保留说话人前缀", isOn: $model.keepSpeakers)
                    Button("转换字幕") { model.convertSubtitles() }.disabled(model.subtitleFiles.isEmpty)
                }
                .formStyle(.grouped)
                .frame(width: 230)
            }
        }
        .padding(18)
    }

    private func status(_ file: URL) -> String {
        guard let result = model.subtitleResults[file] else { return "待转换" }
        switch result {
        case .created: return "成功"
        case .createdWithWarnings: return "成功（有警告）"
        case .alreadyExists, .skipped: return "已跳过"
        case .failed: return "失败"
        }
    }
}

struct PairView: View {
    @ObservedObject var model: VoiceConvertViewModel

    var body: some View {
        VStack(spacing: 14) {
            DropHint(text: "拖入音频和 WebVTT 文件或文件夹", detail: "歧义项不会自动配对")
            GroupBox("配对预览") {
                if let result = model.pairResult {
                    List {
                        ForEach(result.pairs) { pair in
                            Text("PAIR  \(pair.audio.url.lastPathComponent)  ↔  \(pair.subtitle.url.lastPathComponent)")
                        }
                        ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                            Text("\(issue.reason)：\(issue.subtitle?.lastPathComponent ?? issue.audio?.lastPathComponent ?? "")")
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(minHeight: 220)
                } else {
                    ContentUnavailableView("暂无配对", systemImage: "link")
                }
            }
            .frame(maxWidth: .infinity)
            GroupBox("配对设置") {
                Form {
                    Toggle("生成 MP3", isOn: $model.pairGenerateMP3)
                    Toggle("生成 LRC", isOn: $model.pairGenerateLRC)
                    TextField("输出子目录", text: $model.pairOutputSubdirectory)
                    Picker("冲突处理", selection: $model.pairConflictPolicy) {
                        Text("自动加后缀").tag(OutputConflictPolicy.suffix)
                        Text("跳过").tag(OutputConflictPolicy.skip)
                        Text("覆盖").tag(OutputConflictPolicy.overwrite)
                    }
                }
                .formStyle(.grouped)
                .onChange(of: model.pairGenerateMP3) { _, _ in model.rebuildPairPlanForUI() }
                .onChange(of: model.pairGenerateLRC) { _, _ in model.rebuildPairPlanForUI() }
                .onChange(of: model.pairOutputSubdirectory) { _, _ in model.rebuildPairPlanForUI() }
                .onChange(of: model.pairConflictPolicy) { _, _ in model.rebuildPairPlanForUI() }
            }
            HStack {
                if model.isRunning {
                    Button { model.cancelPairing() } label: { Label("取消", systemImage: "stop.fill") }
                } else {
                    Button { model.startPairing() } label: { Label("执行配对", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                    Button { model.retryPairing() } label: { Label("重试失败项", systemImage: "arrow.clockwise") }
                        .disabled(!model.pairTasks.contains { if case .failed = $0.status { return true }; if case .cancelled = $0.status { return true }; return false })
                }
                Spacer()
                Text("父任务 \(model.pairTasks.filter { $0.role == .pairing }.count) · 子任务 \(model.pairTasks.filter { $0.role != .pairing }.count)")
                    .foregroundStyle(.secondary)
            }
            if !model.pairTasks.isEmpty {
                GroupBox("执行状态") {
                    List(model.pairTasks) { task in
                        HStack {
                            Image(systemName: task.role == .pairing ? "link" : (task.operation == .mp3 ? "waveform" : "captions.bubble"))
                            Text(task.inputURL.lastPathComponent)
                            Spacer()
                            Text(model.taskStatusText(task.status)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 140)
                }
            }
        }
        .padding(18)
        .alert("确认覆盖已有输出？", isPresented: $model.confirmOverwritePresented) {
            Button("覆盖", role: .destructive) { model.resolveOverwrite(true) }
            Button("取消", role: .cancel) { model.resolveOverwrite(false) }
        } message: {
            Text("本批次将使用覆盖策略替换已有 MP3 或 LRC 文件。")
        }
    }
}

struct DropHint: View {
    let text: String
    let detail: String
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.down.doc").font(.title)
            Text(text).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(Color.secondary.opacity(0.08))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [7, 5])) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(text)
    }
}

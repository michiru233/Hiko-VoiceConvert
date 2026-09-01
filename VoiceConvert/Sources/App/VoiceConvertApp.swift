import SwiftUI
import UniformTypeIdentifiers
import Combine
import AppKit

@main
struct VoiceConvertApp: App {
    var body: some Scene {
        WindowGroup("音声转换") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 860, height: 620)
    }
}

@MainActor
final class VoiceConvertViewModel: ObservableObject {
    @Published var items: [QueueItem] = []
    @Published var summary = QueueSummary(total: 0, succeeded: 0, failed: 0, cancelled: 0)
    @Published var config: ConversionConfig
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var showDeleteConfirmation = false
    @Published var showOutputPicker = false
    @Published var errorMessage: String?

    private let queue = BatchQueue()
    private var refreshTask: Task<Void, Never>?
    private let defaultsKey = "VoiceConvert.ConversionConfig"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(ConversionConfig.self, from: data) {
            config = saved
        } else {
            config = ConversionConfig()
        }
    }

    func enqueue(_ urls: [URL]) {
        queue.enqueue(urls)
        sync()
    }

    func clear() {
        queue.clear()
        sync()
    }

    func chooseInputFiles() {
        chooseInputs(canChooseFiles: true, canChooseDirectories: false, allowsMultipleSelection: true)
    }

    func chooseInputFolder() {
        chooseInputs(canChooseFiles: false, canChooseDirectories: true, allowsMultipleSelection: false)
    }

    func pause() {
        queue.pause()
        sync()
    }

    func resume() {
        queue.resume()
        sync()
    }

    func cancel() {
        queue.cancel()
        sync()
    }

    func start() {
        guard !items.isEmpty, !isRunning else { return }
        persistConfig()
        isRunning = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let deleteConfirmed: Bool
            if config.deleteSourceOnSuccess {
                deleteConfirmed = await MainActor.run { self.confirmDelete() }
            } else {
                deleteConfirmed = false
            }
            await queue.run(config: config, confirmDelete: { deleteConfirmed })
            sync()
            isRunning = false
            isPaused = false
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            config.outputDirectory = url
            persistConfig()
        }
    }

    private func chooseInputs(
        canChooseFiles: Bool,
        canChooseDirectories: Bool,
        allowsMultipleSelection: Bool
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return }
        enqueue(panel.urls)
    }

    var outputDirectoryLabel: String {
        config.outputDirectory?.path ?? "~/Music/音声库"
    }

    func persistConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func confirmDelete() -> Bool {
        let alert = NSAlert()
        alert.messageText = "确认删除源文件？"
        alert.informativeText = "转换成功后将删除本批次源音频，此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除源文件")
        alert.addButton(withTitle: "保留源文件")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func sync() {
        items = queue.items
        summary = queue.summary
        isRunning = queue.isRunning
        isPaused = queue.isPaused
    }
}

struct ContentView: View {
    @StateObject private var model = VoiceConvertViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainContent
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.config) { _, _ in model.persistConfig() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.and.music.note")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("音声转换").font(.title2.weight(.semibold))
                Text("批量转换为体积更小的 MP3，保留空间声场")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.chooseInputFiles()
            } label: {
                Label("添加文件", systemImage: "doc.badge.plus")
            }
            .disabled(model.isRunning)
            Button {
                model.chooseInputFolder()
            } label: {
                Label("添加文件夹", systemImage: "folder.badge.plus")
            }
            .disabled(model.isRunning)
            Button {
                model.clear()
            } label: {
                Label("清空队列", systemImage: "trash")
            }
            .disabled(model.isRunning || model.items.isEmpty)
        }
        .padding(20)
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 14) {
                dropZone
                queueList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            settingsPanel
        }
        .padding(18)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text("拖入音频文件或文件夹")
                .font(.headline)
            Text("支持 WAV、FLAC、AIFF、M4A，文件夹会递归扫描")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("选择文件") { model.chooseInputFiles() }
                Button("选择文件夹") { model.chooseInputFolder() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    guard let url = (object as? NSURL) as URL? else { return }
                    Task { @MainActor in model.enqueue([url]) }
                }
            }
            return true
        }
        .accessibilityLabel("拖入音频文件或文件夹")
    }

    private var queueList: some View {
        GroupBox {
            if model.items.isEmpty {
                ContentUnavailableView("队列为空", systemImage: "tray", description: Text("拖入文件后即可开始转换"))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(model.items) { item in
                    QueueRow(item: item)
                }
                .listStyle(.inset)
                .frame(minHeight: 210)
            }
        } label: {
            Label("转换队列", systemImage: "list.bullet.rectangle")
        }
    }

    private var settingsPanel: some View {
        Form {
            Section("编码") {
                Picker("质量", selection: Binding(
                    get: { model.config.vbrQuality },
                    set: { model.config.vbrQuality = $0 }
                )) {
                    ForEach(VBRQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                Toggle("完整立体声", isOn: Binding(
                    get: { model.config.fullStereo },
                    set: { model.config.fullStereo = $0 }
                ))
                Stepper("并发数：\(model.config.concurrency)", value: Binding(
                    get: { model.config.concurrency },
                    set: { model.config.concurrency = min(8, max(1, $0)) }
                ), in: 1...8)
            }
            Section("输出") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("输出目录").font(.callout.weight(.medium))
                    Text(model.outputDirectoryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button("选择目录") { model.chooseOutputDirectory() }
                }
                Toggle("转换成功后删除源文件", isOn: Binding(
                    get: { model.config.deleteSourceOnSuccess },
                    set: { model.config.deleteSourceOnSuccess = $0 }
                ))
                .help("开始批次时会再次确认")
            }
        }
        .formStyle(.grouped)
        .frame(width: 260)
    }

    private var footer: some View {
        HStack {
            Label("\(model.summary.succeeded) 成功", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
            Label("\(model.summary.failed) 失败", systemImage: "xmark.circle")
                .foregroundStyle(.red)
            if model.summary.cancelled > 0 {
                Label("\(model.summary.cancelled) 已取消", systemImage: "pause.circle")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if model.isRunning {
                Button(model.isPaused ? "继续" : "暂停") {
                    model.isPaused ? model.resume() : model.pause()
                }
                Button("取消") { model.cancel() }
                    .buttonStyle(.bordered)
            } else {
                Button {
                    model.start()
                } label: {
                    Label("开始转换", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.items.isEmpty)
            }
        }
        .padding(14)
    }
}

struct QueueRow: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.inputURL.lastPathComponent)
                    .lineLimit(1)
                if let output = item.outputURL {
                    Text(output.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if case .failed(let reason) = item.state {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if case .converting = item.state {
                ProgressView(value: item.progress)
                    .frame(width: 80)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch item.state {
        case .waiting: return "clock"
        case .converting: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "pause.circle.fill"
        }
    }

    private var iconColor: Color {
        switch item.state {
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .secondary
        }
    }

    private var statusText: String {
        switch item.state {
        case .waiting: return "等待"
        case .converting: return "转换中"
        case .succeeded: return "完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

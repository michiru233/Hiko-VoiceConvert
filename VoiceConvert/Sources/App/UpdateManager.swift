import AppKit
import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case installing(UpdateRelease)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private let service = GitHubReleaseService()

    var isBusy: Bool {
        switch state {
        case .checking, .installing: return true
        default: return false
        }
    }

    func check(silent: Bool = false) async {
        guard !isBusy else { return }
        state = .checking
        do {
            switch try await service.checkForUpdate() {
            case .upToDate:
                state = .upToDate
                if !silent { show(message: "当前已是最新版本 \(UpdateConfiguration.currentVersionString)。") }
            case .updateAvailable(let release):
                state = .available(release)
                if !silent { offer(release) }
            }
        } catch {
            state = .failed(error.localizedDescription)
            if !silent { show(message: "检查更新失败：\(error.localizedDescription)") }
        }
    }

    func installAvailable() {
        guard case .available(let release) = state else { return }
        offer(release)
    }

    private func offer(_ release: UpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "发现新版本"
        alert.informativeText = "音声转换 \(release.version) 已发布。下载并安装前会验证文件完整性和代码签名。"
        alert.addButton(withTitle: "下载并安装")
        alert.addButton(withTitle: "打开发布页")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await downloadAndInstall(release) }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.releasePageURL)
        default:
            break
        }
    }

    private func downloadAndInstall(_ release: UpdateRelease) async {
        state = .installing(release)
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("voiceconvert-update-\(UUID().uuidString)", isDirectory: true)
        var helperOwnsWork = false
        defer { if !helperOwnsWork { try? fileManager.removeItem(at: work) } }

        do {
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            let loader = URLSessionUpdateDataLoader()
            let archive = try await loader.data(from: release.archiveURL)
            let checksum = try await loader.data(from: release.checksumURL)
            let archiveName = release.archiveURL.lastPathComponent
            try SHA256Verifier.verify(archiveData: archive, checksumFile: checksum, archiveName: archiveName)

            let archiveURL = work.appendingPathComponent(archiveName)
            try archive.write(to: archiveURL, options: .atomic)
            let extractURL = work.appendingPathComponent("extracted", isDirectory: true)
            try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)
            let entries = try runFixedTool("/usr/bin/unzip", arguments: ["-Z1", archiveURL.path])
                .split(whereSeparator: \.isNewline).map(String.init)
            let appPath = try UpdateArchiveLayout.applicationPath(in: entries)
            _ = try runFixedTool("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractURL.path])
            try rejectSymbolicLinks(in: extractURL)
            let candidate = extractURL.appendingPathComponent(appPath)
            try validateApplication(candidate, version: release.version)
            try launchHelper(newAppURL: candidate, cleanupDirectory: work)
            helperOwnsWork = true
        } catch {
            state = .failed(error.localizedDescription)
            if case UpdateError.unsupportedInstallation = error { NSWorkspace.shared.open(release.releasePageURL) }
            show(message: "更新未安装：\(error.localizedDescription)")
        }
    }

    private func rejectSymbolicLinks(in directory: URL) throws {
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw UpdateError.malformedArchive
            }
        }
    }

    private var fileManager: FileManager { .default }

    private func validateApplication(_ appURL: URL, version: SemanticVersion) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue,
              appURL.pathExtension == "app",
              let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == UpdateConfiguration.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version.description else {
            throw UpdateError.invalidApplication
        }
        do { _ = try runFixedTool("/usr/bin/codesign", arguments: ["--verify", "--strict", appURL.path]) }
        catch { throw UpdateError.codeSignatureInvalid }
    }

    private func launchHelper(newAppURL: URL, cleanupDirectory: URL) throws {
        let currentApp = Bundle.main.bundleURL
        let parent = currentApp.deletingLastPathComponent()
        guard currentApp.pathExtension == "app", fileManager.isWritableFile(atPath: parent.path),
              let bundledHelper = Bundle.main.url(forResource: "update-helper", withExtension: nil, subdirectory: "Helpers") else {
            throw UpdateError.unsupportedInstallation
        }

        let helperURL = cleanupDirectory.appendingPathComponent("update-helper")
        try fileManager.copyItem(at: bundledHelper, to: helperURL)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--install-update", newAppURL.path, currentApp.path, "\(ProcessInfo.processInfo.processIdentifier)", cleanupDirectory.path]
        try process.run()
        NSApplication.shared.terminate(nil)
    }

    private func runFixedTool(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw UpdateError.malformedArchive }
        return text
    }

    private func show(message: String) {
        let alert = NSAlert()
        alert.messageText = "音声转换"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

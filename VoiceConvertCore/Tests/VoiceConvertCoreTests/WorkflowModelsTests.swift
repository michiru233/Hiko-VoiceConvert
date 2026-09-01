import Foundation
import Testing
@testable import VoiceConvertCore

struct WorkflowModelsTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-core-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func scannerSkipsHiddenFilesAndSymlinkedDirectories() throws {
        let root = try tempDir()
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("one.vtt"))
        try Data().write(to: root.appendingPathComponent(".hidden.vtt"))
        let link = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: nested)
        let result = WorkflowScanner().scan([root], kind: .subtitle)
        #expect(result.inputs.map(\.url.lastPathComponent) == ["one.vtt"])
        #expect(result.issues.isEmpty)
    }

    @Test func scannerDeduplicatesCanonicalCaseInsensitivePaths() throws {
        let root = try tempDir()
        let file = root.appendingPathComponent("Track.VTT")
        try Data().write(to: file)
        let result = WorkflowScanner().scan([file, file], kind: .subtitle)
        #expect(result.inputs.count == 1)
        #expect(result.issues.contains { if case .duplicate = $0 { true } else { false } })
    }

    @Test func plannerUsesSuffixSkipAndOverwritePolicies() throws {
        let root = try tempDir()
        let inputRoot = try tempDir()
        let inputURL = inputRoot.appendingPathComponent("in/track.mp3.vtt")
        let input = ScannedInput(url: inputURL, kind: .subtitle, root: inputRoot, relativePath: "in/track.mp3.vtt")
        let outputRoot = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let existing = outputRoot.appendingPathComponent("in/track.mp3.lrc")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: existing)
        var reserved = Set<String>()
        let suffix = try OutputNamePlanner().plan(input: input, outputRoot: outputRoot, outputExtension: "lrc", policy: .suffix, reserved: &reserved)
        #expect(suffix?.lastPathComponent == "track.mp3 (1).lrc")
        var skipReserved = Set<String>()
        #expect(try OutputNamePlanner().plan(input: input, outputRoot: outputRoot, outputExtension: "lrc", policy: .skip, reserved: &skipReserved) == nil)
        var overwriteReserved = Set<String>()
        #expect(try OutputNamePlanner().plan(input: input, outputRoot: outputRoot, outputExtension: "lrc", policy: .overwrite, reserved: &overwriteReserved)?.lastPathComponent == "track.mp3.lrc")
    }

    @Test func pairingMatchesAudioSuffixAndRejectsAmbiguity() {
        let root = URL(fileURLWithPath: "/tmp")
        func audio(_ name: String) -> ScannedInput { ScannedInput(url: root.appendingPathComponent(name), kind: .audio, root: root, relativePath: name) }
        func subtitle(_ name: String) -> ScannedInput { ScannedInput(url: root.appendingPathComponent(name), kind: .subtitle, root: root, relativePath: name) }
        let result = PairingMatcher().match(audio: [audio("Track.mp3"), audio("track.wav")], subtitles: [subtitle("track.mp3.vtt")])
        #expect(result.pairs.isEmpty)
        #expect(result.issues.first?.reason == "匹配音频不唯一")
        let one = PairingMatcher().match(audio: [audio("Track.mp3")], subtitles: [subtitle("track.mp3.vtt")])
        #expect(one.pairs.count == 1)
    }

    @Test func plannerRejectsTraversal() throws {
        let inputRoot = try tempDir()
        let outputRoot = try tempDir()
        let input = ScannedInput(
            url: inputRoot.appendingPathComponent("track.vtt"),
            kind: .subtitle,
            root: inputRoot,
            relativePath: "../outside/track.vtt"
        )
        var reserved = Set<String>()
        #expect(throws: OutputNameError.outsideRoot) {
            try OutputNamePlanner().plan(input: input, outputRoot: outputRoot, outputExtension: "lrc", policy: .suffix, reserved: &reserved)
        }
    }

    @Test func pairingSupportsAllCompanionExtensionsAndReportsUnmatchedAudio() {
        let root = URL(fileURLWithPath: "/tmp")
        func audio(_ name: String) -> ScannedInput { ScannedInput(url: root.appendingPathComponent(name), kind: .audio, root: root, relativePath: name) }
        func subtitle(_ name: String) -> ScannedInput { ScannedInput(url: root.appendingPathComponent(name), kind: .subtitle, root: root, relativePath: name) }
        let result = PairingMatcher().match(
            audio: [audio("song.flac"), audio("voice.aiff"), audio("alone.wav")],
            subtitles: [subtitle("song.flac.vtt"), subtitle("voice.aiff.vtt")]
        )
        #expect(result.pairs.count == 2)
        #expect(result.issues.contains { $0.audio?.lastPathComponent == "alone.wav" && $0.reason == "未找到匹配字幕" })
    }

    @Test func taskStatusAndRecentStoreRoundTripAndCapAtThirty() throws {
        var store = RecentBatchStore()
        for _ in 0..<31 { store.append(BatchRecord(tasks: [WorkflowTask(inputURL: URL(fileURLWithPath: "/tmp/a"), status: .succeededWithWarnings(["cue 超时"]))])) }
        #expect(store.batches.count == 30)
        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(RecentBatchStore.self, from: data)
        #expect(decoded == store)
        #expect(decoded.batches.first?.tasks.first?.status == .succeededWithWarnings(["cue 超时"]))
    }
}

import Foundation
import AVFoundation
import Testing
@testable import VoiceConvertCLIKit
import VoiceConvertAudioBackend
import VoiceConvertCore

struct VoiceConvertCLITests {
    @Test func subtitleConversionAndUniquePairingUseCoreContracts() throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let output = LockedLines()
        let errors = LockedLines()
        let code = CLI(arguments: ["subtitle", value.subtitle.path, "--speakers"], out: { output.append($0) }, err: { errors.append($0) }).run()
        #expect(code == .success)
        #expect(output.values.contains { $0.hasPrefix("CREATED\t") })
        let lrc = value.subtitle.deletingPathExtension().deletingPathExtension().appendingPathExtension("lrc")
        #expect(String(decoding: try Data(contentsOf: lrc), as: UTF8.self) == "[00:00.01]Narrator：Line\n")
        #expect(errors.values.isEmpty)
    }

    @Test func audioFixtureCreatesValidatedMP3AndSuffixPreservesSentinel() throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let outputRoot = value.root.deletingLastPathComponent().appendingPathComponent("voiceconvert-audio-output-\(UUID().uuidString)", isDirectory: true)
        let first = LockedLines()
        let firstCode = CLI(arguments: ["audio", value.audio.path, "--output", outputRoot.path], out: { first.append($0) }, err: { _ in }).run()
        #expect(firstCode == .success)
        let mp3 = outputRoot.appendingPathComponent("scene.mp3")
        let description = try AVAudioFile(forReading: mp3).processingFormat
        #expect(description.channelCount == 2)
        #expect(description.sampleRate == 48_000)
        try Data("sentinel".utf8).write(to: mp3)
        let second = LockedLines()
        let secondOutput = LockedLines()
        let secondCode = CLI(arguments: ["audio", value.audio.path, "--output", outputRoot.path], out: { secondOutput.append($0) }, err: { second.append($0) }).run()
        #expect(secondCode == .success)
        #expect(secondOutput.values.contains { $0.contains("scene (1).mp3") })
        #expect(second.values.isEmpty)
        #expect(try Data(contentsOf: mp3) == Data("sentinel".utf8))
        #expect(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("scene (1).mp3").path))
    }

    @Test func audioSkipPolicyPreservesSentinelAndReturnsPartialFailure() throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let outputRoot = value.root.deletingLastPathComponent().appendingPathComponent("voiceconvert-audio-skip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let mp3 = outputRoot.appendingPathComponent("scene.mp3")
        try Data("sentinel".utf8).write(to: mp3)
        let errors = LockedLines()
        let code = CLI(arguments: ["audio", value.audio.path, "--output", outputRoot.path, "--policy", "skip"], out: { _ in }, err: { errors.append($0) }).run()
        #expect(code == .partialFailure)
        #expect(errors.values.contains { $0.contains("SKIPPED") })
        #expect(try Data(contentsOf: mp3) == Data("sentinel".utf8))
    }
    @Test func pairFixtureCreatesSharedStemOutputsAndReportsBadAudio() throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let outputRoot = value.root.deletingLastPathComponent().appendingPathComponent("voiceconvert-pair-output-\(UUID().uuidString)", isDirectory: true)
        let lines = LockedLines()
        let code = CLI(arguments: ["pair", value.audio.path, value.subtitle.path, "--output", outputRoot.path], out: { lines.append($0) }, err: { lines.append($0) }).run()
        #expect(code == .success)
        let mp3 = outputRoot.appendingPathComponent("scene.mp3")
        let lrc = outputRoot.appendingPathComponent("scene.lrc")
        #expect(FileManager.default.fileExists(atPath: mp3.path))
        #expect(FileManager.default.fileExists(atPath: lrc.path))
        #expect(mp3.deletingPathExtension().lastPathComponent == lrc.deletingPathExtension().lastPathComponent)

        let broken = value.root.appendingPathComponent("broken.wav")
        let brokenVTT = value.root.appendingPathComponent("broken.wav.vtt")
        try Data([0, 1, 2]).write(to: broken)
        try Data("WEBVTT\n\n00:00.010 --> 00:00.100\nBroken\n".utf8).write(to: brokenVTT)
        let failed = LockedLines()
        let failedCode = CLI(arguments: ["pair", broken.path, brokenVTT.path, "--output", value.root.deletingLastPathComponent().appendingPathComponent("voiceconvert-failed-\(UUID().uuidString)").path], out: { _ in }, err: { failed.append($0) }).run()
        #expect(failedCode == .partialFailure)
        #expect(failed.values.contains { $0.contains("FAILED") })
    }


    @Test func cliExitCodesCoverUsageAndNoInput() {
        #expect(CLI(arguments: []).run() == .usage)
        #expect(CLI(arguments: ["audio", "/path/that/does/not/exist"]).run() == .noInput)
    }

    private func fixture() throws -> (root: URL, audio: URL, subtitle: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voiceconvert-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: "/System/Library/Sounds/Basso.aiff")
        let audio = root.appendingPathComponent("scene.wav")
        try exportWAV(source: source, destination: audio)
        let subtitle = root.appendingPathComponent("scene.wav.vtt")
        try Data("WEBVTT\n\n00:00.010 --> 00:00.100\n<v Narrator>Line\n".utf8).write(to: subtitle)
        return (root, audio, subtitle)
    }

    private func exportWAV(source: URL, destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32]
        let output = try AVAudioFile(forWriting: destination, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 48_000) else { throw CocoaError(.fileWriteUnknown) }
        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: min(buffer.frameCapacity, AVAudioFrameCount(input.length - input.framePosition)))
            try output.write(from: buffer)
        }
    }
}

private final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [String] = []
    func append(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
}

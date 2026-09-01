import XCTest
import AVFoundation

final class ConversionEngineTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("VoiceConvertTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
    }

    func testDefaultConfigUsesV2FullStereoAndFourWorkers() {
        let config = ConversionConfig()
        XCTAssertEqual(config.vbrQuality, .v2)
        XCTAssertTrue(config.fullStereo)
        XCTAssertEqual(config.concurrency, 4)
        XCTAssertFalse(config.deleteSourceOnSuccess)
    }

    func testScannerRecursesAndIgnoresUnsupportedFiles() throws {
        let nested = root.appendingPathComponent("a/b")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        let first = nested.appendingPathComponent("voice.wav")
        let second = root.appendingPathComponent("ignore.txt")
        try Data([1, 2, 3]).write(to: first)
        try Data([1]).write(to: second)

        let result = AudioInputScanner().scan([root])
        XCTAssertEqual(result, [first.standardizedFileURL])
    }

    func testRelativeOutputAndCollisionSuffix() throws {
        let inputRoot = root.appendingPathComponent("input")
        let outputRoot = root.appendingPathComponent("output")
        try fileManager.createDirectory(at: inputRoot.appendingPathComponent("a"), withIntermediateDirectories: true)
        let input = inputRoot.appendingPathComponent("a/voice.wav")
        let output = try OutputPathResolver.resolve(input: input, root: outputRoot, relativeRoot: inputRoot)
        XCTAssertEqual(output.path, outputRoot.appendingPathComponent("a/voice.mp3").path)

        var reserved = Set<String>()
        let first = OutputPathResolver.uniqueURL(output, reserved: &reserved)
        let second = OutputPathResolver.uniqueURL(output, reserved: &reserved)
        XCTAssertEqual(first.lastPathComponent, "voice.mp3")
        XCTAssertEqual(second.lastPathComponent, "voice-1.mp3")
    }

    func testCorruptInputFailsWithoutCreatingOutput() throws {
        let input = root.appendingPathComponent("broken.wav")
        let output = root.appendingPathComponent("broken.mp3")
        try Data([0, 1, 2, 3, 4]).write(to: input)
        XCTAssertThrowsError(try ConversionEngine().convert(inputURL: input, outputURL: output))
        XCTAssertFalse(fileManager.fileExists(atPath: output.path))
    }

    func testExistingOutputIsNeverOverwritten() throws {
        let input = root.appendingPathComponent("tone.wav")
        let output = root.appendingPathComponent("tone.mp3")
        try makeWAV(at: input, sampleRate: 48_000, duration: 0.1)
        let sentinel = Data("keep this file".utf8)
        try sentinel.write(to: output)

        XCTAssertThrowsError(try ConversionEngine().convert(inputURL: input, outputURL: output))
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
    }

    func testOutputMustUseMP3Extension() throws {
        let input = root.appendingPathComponent("tone.wav")
        let output = root.appendingPathComponent("tone.wav")
        try makeWAV(at: input, sampleRate: 48_000, duration: 0.1)

        XCTAssertThrowsError(try ConversionEngine().convert(inputURL: input, outputURL: output))
    }

    func testWAVConvertsToMP3WithMatchingTechnicalFormat() throws {
        let input = root.appendingPathComponent("tone.wav")
        let output = root.appendingPathComponent("tone.mp3")
        try makeWAV(at: input, sampleRate: 48_000, duration: 0.35)

        let result = try ConversionEngine().convert(inputURL: input, outputURL: output)
        XCTAssertEqual(result.source.channelCount, 2)
        XCTAssertEqual(result.output.channelCount, 2)
        XCTAssertEqual(result.output.sampleRate, 48_000, accuracy: 1)
        XCTAssertLessThanOrEqual(abs(result.output.duration - result.source.duration), 0.1)
        XCTAssertTrue(fileManager.fileExists(atPath: output.path))
    }

    private func makeWAV(at url: URL, sampleRate: Double, duration: TimeInterval) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frames = AVAudioFrameCount((sampleRate * duration).rounded())
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channels = buffer.floatChannelData!
        for channel in 0..<2 {
            for frame in 0..<Int(frames) {
                channels[channel][frame] = sin(Float(frame) * 0.03) * 0.2
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

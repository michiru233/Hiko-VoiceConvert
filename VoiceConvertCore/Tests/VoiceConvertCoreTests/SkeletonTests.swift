import Testing
@testable import VoiceConvertCore

struct SkeletonTests {
    @Test func coreVersionIsReported() {
        #expect(CoreInfo.version == "0.1.0")
    }
}

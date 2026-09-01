import Testing
@testable import VoiceConvertCore

/// 测试名即业务规格：每条用一个「期望完整字符串」锁死输出。
struct ConverterSpecTests {

    private let converter = VttToLrcConverter()

    // MARK: 结构块

    @Test func webvttHeaderIsIgnoredAndCueBodyConverts() {
        let vtt = """
        WEBVTT

        00:01.000 --> 00:03.500
        こんにちは
        """
        #expect(converter.convert(vtt) == "[00:01.00]こんにちは")
    }

    @Test func noteBlockIsIgnoredEntirely() {
        let vtt = """
        WEBVTT

        NOTE this is a comment
        spanning multiple lines

        00:02.000 --> 00:04.000
        セリフ
        """
        #expect(converter.convert(vtt) == "[00:02.00]セリフ")
    }

    @Test func styleAndRegionBlocksAreIgnoredEntirely() {
        let vtt = """
        WEBVTT

        STYLE
        ::cue { color: red }

        REGION
        id:r1 width:40%

        00:05.000 --> 00:06.000
        本文
        """
        #expect(converter.convert(vtt) == "[00:05.00]本文")
    }

    // MARK: 时间戳格式

    @Test func bothHourAndMinuteTimestampFormatsAreSupported() {
        let vtt = """
        WEBVTT

        01:02:03.456 --> 01:02:05.000
        fold

        00:10.500 --> 00:11.000
        short
        """
        #expect(converter.convert(vtt) == "[00:10.50]short\n[62:03.46]fold")
    }

    /// 拍板第三条专用用例：01:05:30.000 → [65:30.xx]，总分钟数容纳小时、内容不丢。
    @Test func hoursFoldIntoTotalMinutesPerDecision() {
        let vtt = """
        WEBVTT

        01:05:30.000 --> 01:06:40.500
        长篇台词
        """
        #expect(converter.convert(vtt) == "[65:30.00]长篇台词")
    }

    // MARK: 行结构

    @Test func cueIdentifierLineBeforeTimingIsDiscarded() {
        let vtt = """
        WEBVTT

        cue-id-001
        00:20.000 --> 00:22.000
        セリフＡ
        """
        #expect(converter.convert(vtt) == "[00:20.00]セリフＡ")
    }

    @Test func cueSettingsAfterTimingOnSameLineAreDiscarded() {
        let vtt = """
        WEBVTT

        00:30.000 --> 00:32.000 align:start line:0% position:50%
        setting text
        """
        #expect(converter.convert(vtt) == "[00:30.00]setting text")
    }

    // MARK: 标签与实体

    @Test func htmlTagsAndKaraokeWordTimestampsAreStripped() {
        let vtt = """
        WEBVTT

        01:00.000 --> 01:04.000
        <i>強調</i>と<b>太字</b><u>下線</u>
        <font color="red">赤</font>
        <ruby>漢<rt>かん</rt></ruby>
        <00:00.500>カラオケ
        """
        #expect(converter.convert(vtt) == "[01:00.00]強調と太字下線 赤 漢かん カラオケ")
    }

    @Test func voiceSpeakerTagIsStrippedByDefault() {
        let vtt = """
        WEBVTT

        00:03.000 --> 00:05.000
        <v 神代妹紅>おはよう。
        """
        #expect(converter.convert(vtt) == "[00:03.00]おはよう。")
    }

    @Test func voiceSpeakerTagBecomesNamePrefixWhenEnabled() {
        let vtt = """
        WEBVTT

        00:03.000 --> 00:05.000
        <v 神代妹紅>おはよう。
        """
        #expect(
            converter.convert(vtt, keepSpeakers: true)
                == "[00:03.00]神代妹紅：おはよう。"
        )
    }

    @Test func listedEntitiesAreDecodedOnce() {
        let vtt = """
        WEBVTT

        00:02.000 --> 00:03.000
        A &amp; B &lt;x&gt; &quot;q&quot; &#39;p&#39;
        """
        #expect(converter.convert(vtt) == "[00:02.00]A & B <x> \"q\" 'p'")
    }

    /// 单遍解码：实体解码结果不再二次解码；解码在剥标签之后，&lt;i&gt; 还原为字面文本而非被当成标签。
    @Test func entityDecodingIsNotRecursiveAndRunsAfterTagStripping() {
        let vtt = """
        WEBVTT

        00:07.000 --> 00:08.000
        &amp;lt; &amp;amp;
        """
        #expect(converter.convert(vtt) == "[00:07.00]&lt; &amp;")
    }

    // MARK: 排序

    @Test func cuesSortByStartTimeAscendingAcrossHourBoundary() {
        let vtt = """
        WEBVTT

        02:00.000 --> 02:04.000
        b中段

        01:05:00.000 --> 01:05:10.000
        c跨小时

        00:30.000 --> 00:31.000
        a开头
        """
        #expect(converter.convert(vtt) == "[00:30.00]a开头\n[02:00.00]b中段\n[65:00.00]c跨小时")
    }

    @Test func duplicateTimestampCuesStayAsIndependentLines() {
        let vtt = """
        WEBVTT

        00:05.000 --> 00:07.000
        一

        00:05.000 --> 00:08.000
        二

        00:01.000 --> 00:02.000
        零
        """
        #expect(converter.convert(vtt) == "[00:01.00]零\n[00:05.00]一\n[00:05.00]二")
    }

    // MARK: 编码与边界

    @Test func crlfLineEndingsAndUtf8BomAreHandled() {
        let vtt = "\u{FEFF}WEBVTT\r\n\r\n00:15.000 --> 00:16.000\r\n改行処理\r\n"
        #expect(converter.convert(vtt) == "[00:15.00]改行処理")
    }

    @Test func emptyInputYieldsEmptyOutputWithoutError() {
        #expect(converter.convert("") == "")
        #expect(converter.convert("WEBVTT\n") == "")
    }

    @Test func fileWithNoCuesYieldsEmptyOutputWithoutError() {
        let vtt = "WEBVTT\n\nNOTE nothing here\n\nSTYLE\n::cue{}\n"
        #expect(converter.convert(vtt) == "")
    }

    /// 百分秒四舍五入进位：999ms → 100 百分秒 → 秒+1。
    @Test func centisecondRoundingCarriesIntoNextSecond() {
        let vtt = """
        WEBVTT

        00:00.999 --> 00:01.500
        carry
        """
        #expect(converter.convert(vtt) == "[00:01.00]carry")
    }
}

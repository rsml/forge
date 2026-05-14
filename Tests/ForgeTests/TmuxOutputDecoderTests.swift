import Testing
@testable import ForgeCore

@Suite("TmuxOutputDecoder")
struct TmuxOutputDecoderTests {

    @Test("plain text passes through unchanged")
    func plainText() {
        let result = TmuxOutputDecoder.decode("hello world")
        #expect(result == [UInt8]("hello world".utf8))
    }

    @Test("decodes octal-escaped newline")
    func octalNewline() {
        let result = TmuxOutputDecoder.decode("hello\\012world")
        #expect(result == [UInt8]("hello".utf8) + [0x0A] + [UInt8]("world".utf8))
    }

    @Test("decodes octal-escaped carriage return")
    func octalCR() {
        let result = TmuxOutputDecoder.decode("line\\015\\012")
        #expect(result == [UInt8]("line".utf8) + [0x0D, 0x0A])
    }

    @Test("decodes escaped backslash")
    func escapedBackslash() {
        let result = TmuxOutputDecoder.decode("path\\\\dir")
        #expect(result == [UInt8]("path\\dir".utf8))
    }

    @Test("handles mixed content")
    func mixedContent() {
        let result = TmuxOutputDecoder.decode("\\033[1mBold\\033[0m\\012")
        #expect(result == [0x1B] + [UInt8]("[1mBold".utf8) + [0x1B] + [UInt8]("[0m".utf8) + [0x0A])
    }

    @Test("empty string returns empty array")
    func emptyString() {
        let result = TmuxOutputDecoder.decode("")
        #expect(result.isEmpty)
    }
}

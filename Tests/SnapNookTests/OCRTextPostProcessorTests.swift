import XCTest
@testable import SnapNook

final class OCRTextPostProcessorTests: XCTestCase {
    func testFixesCodeStyleParenthesesAndColon() {
        XCTAssertEqual(
            OCRTextPostProcessor.process("ClipboardWriter.copy（text：）"),
            "ClipboardWriter.copy(text:)"
        )
    }

    func testFixesCodeLikeLineAggressively() {
        XCTAssertEqual(
            OCRTextPostProcessor.process("func test（）｛ return true； ｝"),
            "func test(){ return true; }"
        )
    }

    func testFixesURLSymbols() {
        XCTAssertEqual(
            OCRTextPostProcessor.process("http：//example。com/path"),
            "http://example.com/path"
        )
    }

    func testFixesVersionNumber() {
        XCTAssertEqual(
            OCRTextPostProcessor.process("let version = 1。2"),
            "let version = 1.2"
        )
    }

    func testKeepsChinesePunctuationInChineseSentence() {
        XCTAssertEqual(
            OCRTextPostProcessor.process("说明：这是一个测试，请点击按钮。"),
            "说明：这是一个测试，请点击按钮。"
        )
    }

    func testMixedChineseAndEnglishOnlyNormalizesCodeContext() {
        XCTAssertEqual(
            OCRTextPostProcessor.process("错误码：404，message：not found"),
            "错误码：404,message:not found"
        )
    }

    func testFixesArrayIndexing() {
        XCTAssertEqual(
            OCRTextPostProcessor.process("array［0］"),
            "array[0]"
        )
    }

    func testFixesQuotedEnglishInCodeLikeContext() {
        XCTAssertEqual(
            OCRTextPostProcessor.process("“hello”"),
            "\"hello\""
        )
    }
}

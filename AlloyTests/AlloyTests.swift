import XCTest

final class AlloyTests: XCTestCase {
    func testTextBufferRoundtrip() {
        let buf = TextBuffer(string: "hello\nworld")
        XCTAssertEqual(buf.lineCount, 2)
        XCTAssertEqual(buf.lineString(0), "hello")
        XCTAssertEqual(buf.lineString(1), "world")
    }
}

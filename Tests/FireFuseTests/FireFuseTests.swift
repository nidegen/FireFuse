import XCTest
@testable import FireFuse

final class FireFuseTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(FireFuse().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

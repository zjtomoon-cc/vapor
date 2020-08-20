import XCTest
import Vapor

final class ProcessTests: XCTestCase {
    func testExample() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try XCTAssertEqual(app.process.whoami().wait(), "tanner")
//        try XCTAssertContains(app.process.cat(#file).wait(), "42")
//        XCTAssertThrowsError(try app.process.cat("/tmp/\(UUID())").wait())
//
//        try XCTAssertEqual(
//            app.process.swift.package.at("/Users/tanner/dev/vapor/vapor").dump().wait().toolsVersion._version,
//            "5.2.0"
//        )
    }

    override class func setUp() {
        XCTAssertTrue(isLoggingConfigured)
    }
}

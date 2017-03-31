
import Shared
import XCTest

class TimeConstantsTests: XCTestCase {
    
    func testNow() {
        let ts: Timestamp = Date.now()
        XCTAssertNotEqual(ts, Timestamp(0.0))

        let convertedBack = Date().timeIntervalSince1970 - (Double(ts) / 1000.0)
        XCTAssertGreaterThan(convertedBack, 0.0)
        XCTAssertLessThan(convertedBack, 0.25)
    }

    func testNowNumber() {
        let ts: NSNumber = Date.nowNumber()
        XCTAssertNotEqual(ts.doubleValue, 0.0)

        let convertedBack = Date().timeIntervalSince1970 - (Double(ts.doubleValue) / 1000.0)
        XCTAssertGreaterThan(convertedBack, 0.0)
        XCTAssertLessThan(convertedBack, 0.25)
    }

    func testNowMicroSeconds() {
        let ts: MicrosecondTimestamp = Date.nowMicroseconds()
        XCTAssertNotEqual(ts, MicrosecondTimestamp(0.0))

        let convertedBack = Date().timeIntervalSince1970 - (Double(ts) / 1000000.0)
        XCTAssertGreaterThan(convertedBack, 0.0)
        XCTAssertLessThan(convertedBack, 0.25)
    }

    func testFromTimestamp() {
        let date = Date.fromTimestamp(Timestamp(1490794650974))
        let expectedDate = Date(timeIntervalSince1970: 1490794650.974)
        XCTAssertEqual(expectedDate, date)
    }

    func testFromMicrosecondTimestamp() {
        let date = Date.fromMicrosecondTimestamp(MicrosecondTimestamp(1490794650974123))
        let expectedDate = Date(timeIntervalSince1970: 1490794650.974123)
        XCTAssertEqual(expectedDate, date)
    }

    func testToRelativeTimeString() {

        let year = Date(timeIntervalSinceNow: -365 * 24 * 60 * 60)
        XCTAssertEqual(year.toRelativeTimeString(), DateFormatter.localizedString(from: year, dateStyle: DateFormatter.Style.short, timeStyle: DateFormatter.Style.short))

        // Today
        //XCTAssertTrue( Date(timeIntervalSinceNow: -60).toRelativeTimeString().startsWith("today at"))
        //XCTAssertTrue( Date(timeIntervalSinceNow: -60*60*24).toRelativeTimeString().startsWith("today at"))

        // Past minute
        XCTAssertEqual(Date(timeIntervalSinceNow:  0).toRelativeTimeString(), "just now")
        XCTAssertEqual(Date(timeIntervalSinceNow: -59).toRelativeTimeString(), "just now")

    }

    func testDecimalSecondsStringToTimestamp() {
        XCTAssertEqual(Timestamp(1490794650974), decimalSecondsStringToTimestamp("1490794650.974"))
        XCTAssertEqual(Timestamp(1490794650974), decimalSecondsStringToTimestamp("+1490794650.974"))
        XCTAssertEqual(nil, decimalSecondsStringToTimestamp(""))
        XCTAssertEqual(nil, decimalSecondsStringToTimestamp("cheese"))
        XCTAssertEqual(nil, decimalSecondsStringToTimestamp("c0ffee"))
        XCTAssertEqual(nil, decimalSecondsStringToTimestamp("1234x"))
    }

    func testMillisecondsToDecimalSeconds() {
        // Two decimals because that is what the Sync Server expects
        XCTAssertEqual("1490794650.97", millisecondsToDecimalSeconds(Timestamp(1490794650974)))
        XCTAssertEqual("1490794650.00", millisecondsToDecimalSeconds(Timestamp(1490794650000)))
    }
}

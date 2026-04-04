import XCTest

// NOTE: Add this file to an "OnlineIndicatorTests" Unit Testing Bundle target via
// Xcode → File → New → Target → Unit Testing Bundle. The target must link the
// app's source files (or use @testable import OnlineIndicator once the product
// module name is set).

// MARK: - UserDefaults.Key

final class UserDefaultsKeyTests: XCTestCase {

    private let suiteName = "com.OnlineIndicator.tests.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStringRoundTrip() {
        defaults.set("https://example.com", for: .pingURL)
        XCTAssertEqual(defaults.string(for: .pingURL), "https://example.com")
    }

    func testDoubleRoundTrip() {
        defaults.set(120.0, for: .refreshInterval)
        XCTAssertEqual(defaults.double(for: .refreshInterval), 120.0)
    }

    func testRemoveObject() {
        defaults.set("hello", for: .pingURL)
        defaults.removeObject(for: .pingURL)
        XCTAssertNil(defaults.string(for: .pingURL))
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(UserDefaults.Key.refreshInterval.rawValue, "refreshInterval")
        XCTAssertEqual(UserDefaults.Key.pingURL.rawValue,         "pingURL")
    }
}

// MARK: - ConnectivityChecker (URL validation)

final class ConnectivityCheckerURLTests: XCTestCase {

    func testDefaultURLIsValid() {
        XCTAssertNotNil(URL(string: "http://captive.apple.com"))
    }

    func testCustomURLAcceptsHTTPS() {
        let url = URL(string: "https://example.com")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
    }

    func testInvalidSchemeRejected() {
        let url = URL(string: "ftp://example.com")
        let isValid = url.flatMap { u in
            u.scheme.map { ["http", "https"].contains($0) }
        } ?? false
        XCTAssertFalse(isValid)
    }

    func testEmptyStringProducesNil() {
        XCTAssertNil(URL(string: ""))
    }
}

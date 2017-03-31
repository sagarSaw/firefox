
import Alamofire
import XCTest

class AlamoFireExtensionsTests: XCTestCase {
    
    func testSessionManagerManagerWithUserAgent() {
        let configuration = URLSessionConfiguration.default
        let _ = SessionManager.managerWithUserAgent("Hello", configuration: configuration)
        XCTAssertEqual("Hello", configuration.httpAdditionalHeaders?["User-Agent"] as? String)
    }
    
}

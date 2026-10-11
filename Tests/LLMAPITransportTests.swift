import Foundation

enum LLMAPITransportTests {
    static func run() {
        testDroppedConnectionsAreRetried()
        testOtherFailuresAreNotRetried()
    }

    private static func testDroppedConnectionsAreRetried() {
        for code in [URLError.Code.networkConnectionLost, .cannotConnectToHost, .secureConnectionFailed] {
            TestSupport.expect(
                LLMAPITransport.isTransientConnectionError(URLError(code)),
                "Expected \(code) to be retried"
            )
        }
    }

    private static func testOtherFailuresAreNotRetried() {
        for code in [URLError.Code.timedOut, .notConnectedToInternet, .cancelled, .badServerResponse] {
            TestSupport.expect(
                !LLMAPITransport.isTransientConnectionError(URLError(code)),
                "Expected \(code) not to be retried"
            )
        }
        TestSupport.expect(
            !LLMAPITransport.isTransientConnectionError(CancellationError()),
            "Expected non-URL errors not to be retried"
        )
    }
}

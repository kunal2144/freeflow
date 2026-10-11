import Foundation

enum LLMAPITransport {
    private static func makeEphemeralSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        // URLSession's resource timeout is session-scoped, while each caller
        // already puts its configured timeout on the URLRequest. Keep both
        // session timers aligned with that request instead of applying one
        // global timeout to every provider and operation.
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    private static func timeout(for request: URLRequest) -> TimeInterval {
        let requestTimeout = request.timeoutInterval
        guard requestTimeout.isFinite, requestTimeout > 0 else {
            return 60
        }
        return requestTimeout
    }

    static func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await retryingOnceIfConnectionDropped {
            let session = makeEphemeralSession(timeout: timeout(for: request))
            defer { session.finishTasksAndInvalidate() }
            return try await session.data(for: request)
        }
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data
    ) async throws -> (Data, URLResponse) {
        try await retryingOnceIfConnectionDropped {
            // Fresh session per upload — no poisoned connection re-use.
            let session = makeEphemeralSession(timeout: timeout(for: request))
            defer { session.finishTasksAndInvalidate() }
            return try await session.upload(for: request, from: bodyData)
        }
    }

    /// Connection-level failures where the request most likely never reached
    /// the provider (for example an HTTP/3 connection the server closed while
    /// idle). One immediate retry on a fresh session usually succeeds, and is
    /// far better than silently pasting the raw transcript.
    static func isTransientConnectionError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .cannotConnectToHost, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private static func retryingOnceIfConnectionDropped<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch where isTransientConnectionError(error) {
            try await Task.sleep(nanoseconds: 300_000_000)
            return try await operation()
        }
    }
}

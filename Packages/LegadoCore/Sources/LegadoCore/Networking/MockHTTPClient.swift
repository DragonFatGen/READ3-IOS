public actor MockHTTPClient: HTTPClient {
    private var results: [Result<HTTPResponse, HTTPError>]
    private var capturedRequests: [HTTPRequest] = []

    public init(results: [Result<HTTPResponse, HTTPError>]) {
        self.results = results
    }

    public init(response: HTTPResponse) {
        results = [.success(response)]
    }

    public init(error: HTTPError) {
        results = [.failure(error)]
    }

    public var requests: [HTTPRequest] {
        capturedRequests
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        capturedRequests.append(request)
        guard !results.isEmpty else {
            throw HTTPError.transportError("MockHTTPClient has no configured result.")
        }
        let result = results.count == 1 ? results[0] : results.removeFirst()
        return try result.get()
    }
}

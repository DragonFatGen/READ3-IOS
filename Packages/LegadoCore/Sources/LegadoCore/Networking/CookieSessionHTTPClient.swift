import Foundation

public struct CookieSessionHTTPClient: HTTPClient {
    private let transport: any HTTPClient
    private let cookieStore: any HTTPCookieStore

    public init(transport: any HTTPClient, cookieStore: any HTTPCookieStore) {
        self.transport = transport
        self.cookieStore = cookieStore
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let explicitCookies = explicitCookieValues(from: request)
        var url = request.url
        var method = request.method
        var body = request.body
        var bodyKind = request.bodyKind
        var shouldDropBodyHeaders = false
        var redirects: [HTTPRedirect] = []
        var receivedCookies: [HTTPCookie] = []

        while true {
            var headers = request.headers
            let stored = try await cookieStore.cookies(
                for: url,
                sourceIdentifier: request.sessionIdentifier
            )
            headers["Cookie"] = mergedCookieHeader(stored: stored, explicit: explicitCookies)
            if shouldDropBodyHeaders {
                headers["Content-Length"] = nil
                headers["Content-Type"] = nil
            }
            let hopRequest = HTTPRequest(
                url: url,
                method: method,
                headers: headers,
                body: body,
                bodyKind: bodyKind,
                charset: request.charset,
                redirectPolicy: .doNotFollow,
                cookies: stored,
                sessionIdentifier: request.sessionIdentifier,
                timeout: request.timeout,
                retryCount: request.retryCount,
                options: request.options
            )
            let response = try await transport.send(hopRequest)
            try await cookieStore.store(
                response.cookies,
                for: response.finalURL,
                sourceIdentifier: request.sessionIdentifier
            )
            receivedCookies.append(contentsOf: response.cookies)

            guard case let .follow(maximumHops) = request.redirectPolicy,
                  redirects.count < maximumHops,
                  isRedirect(response.statusCode),
                  let location = response.headers["Location"],
                  let nextURL = URL(string: location, relativeTo: response.finalURL)?.absoluteURL else {
                return HTTPResponse(
                    statusCode: response.statusCode,
                    headers: response.headers,
                    data: response.data,
                    finalURL: response.finalURL,
                    redirects: redirects,
                    cookies: receivedCookies
                )
            }

            redirects.append(HTTPRedirect(
                from: response.finalURL,
                to: nextURL,
                statusCode: response.statusCode
            ))
            if response.statusCode == 303 || ((response.statusCode == 301 || response.statusCode == 302) && method == .post) {
                method = .get
                body = nil
                bodyKind = .none
                shouldDropBodyHeaders = true
            }
            url = nextURL
        }
    }

    private func explicitCookieValues(from request: HTTPRequest) -> [(String, String)] {
        var values = parseCookieHeader(request.headers["Cookie"])
        for cookie in request.cookies {
            if let index = values.firstIndex(where: { $0.0 == cookie.name && $0.1 == cookie.value }) {
                values.remove(at: index)
            }
        }
        return values
    }

    private func mergedCookieHeader(
        stored: [HTTPCookie],
        explicit: [(String, String)]
    ) -> String? {
        var values = stored.map { ($0.name, $0.value) }
        for pair in explicit {
            let insertionIndex = values.firstIndex { $0.0 == pair.0 } ?? values.endIndex
            values.removeAll { $0.0 == pair.0 }
            values.insert(pair, at: min(insertionIndex, values.endIndex))
        }
        guard !values.isEmpty else { return nil }
        return values.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }

    private func parseCookieHeader(_ value: String?) -> [(String, String)] {
        guard let value else { return [] }
        return value.split(separator: ";").compactMap { item in
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            return (
                pair[0].trimmingCharacters(in: .whitespacesAndNewlines),
                String(pair[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func isRedirect(_ statusCode: Int) -> Bool {
        [301, 302, 303, 307, 308].contains(statusCode)
    }
}

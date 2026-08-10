import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var lastResponse: HTTPResponse?
        for _ in 0...request.retryCount {
            let response = try await sendOnce(request)
            lastResponse = response
            if (200..<300).contains(response.statusCode) { return response }
        }
        guard let lastResponse else { throw HTTPError.invalidResponse }
        return lastResponse
    }

    private func sendOnce(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for header in request.headers {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }
        let redirectDelegate = RedirectDelegate(policy: request.redirectPolicy)
        do {
            let (data, response) = try await perform(urlRequest, delegate: redirectDelegate)
            guard let response = response as? HTTPURLResponse,
                  let finalURL = response.url else { throw HTTPError.invalidResponse }
            let headers = HTTPHeaders(response.allHeaderFields.compactMap { entry in
                guard let name = entry.key as? String else { return nil }
                return HTTPHeader(name: name, value: String(describing: entry.value))
            })
            return HTTPResponse(
                statusCode: response.statusCode,
                headers: headers,
                data: data,
                finalURL: finalURL,
                redirects: redirectDelegate.redirects,
                cookies: parseCookies(headers["Set-Cookie"], responseURL: finalURL)
            )
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.transportError(String(describing: error))
        }
    }

    private func perform(
        _ request: URLRequest,
        delegate: RedirectDelegate
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request) { data, response, error in
                defer { session.finishTasksAndInvalidate() }
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: HTTPError.invalidResponse)
                }
            }
            task.resume()
        }
    }

    private func parseCookies(_ header: String?, responseURL: URL) -> [HTTPCookie] {
        guard let header else { return [] }
        return header.split(whereSeparator: { $0 == "\n" }).compactMap { line in
            let parts = line.split(separator: ";").map(String.init)
            guard let first = parts.first else { return nil }
            let pair = first.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, let host = responseURL.host else { return nil }
            var domain = host
            var path = "/"
            var secure = false
            var httpOnly = false
            for attribute in parts.dropFirst() {
                let item = attribute.trimmingCharacters(in: .whitespacesAndNewlines)
                let field = item.split(separator: "=", maxSplits: 1).map(String.init)
                switch field[0].lowercased() {
                case "domain" where field.count == 2: domain = field[1].trimmingCharacters(in: CharacterSet(charactersIn: "."))
                case "path" where field.count == 2: path = field[1]
                case "secure": secure = true
                case "httponly": httpOnly = true
                default: break
                }
            }
            return HTTPCookie(
                name: String(pair[0]),
                value: String(pair[1]),
                domain: domain,
                path: path,
                isSecure: secure,
                isHTTPOnly: httpOnly
            )
        }
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: HTTPRedirectPolicy
    private let lock = NSLock()
    private var storage: [HTTPRedirect] = []

    init(policy: HTTPRedirectPolicy) {
        self.policy = policy
    }

    var redirects: [HTTPRedirect] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        let shouldFollow: Bool
        if let from = response.url, let to = request.url {
            switch policy {
            case .doNotFollow:
                shouldFollow = false
            case let .follow(maximumHops):
                if storage.count < maximumHops {
                    storage.append(HTTPRedirect(from: from, to: to, statusCode: response.statusCode))
                    shouldFollow = true
                } else {
                    shouldFollow = false
                }
            }
        } else {
            shouldFollow = false
        }
        lock.unlock()
        completionHandler(shouldFollow ? request : nil)
    }
}

import Foundation

public struct HTTPCookie: Codable, Equatable, Sendable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expires: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expires: Date? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false
    ) {
        self.name = name
        self.value = value
        self.domain = domain.lowercased()
        self.path = path
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    public func matches(_ url: URL, now: Date = Date()) -> Bool {
        let requestPath = url.path.isEmpty ? "/" : url.path
        guard expires.map({ $0 > now }) ?? true,
              let host = url.host?.lowercased(),
              host == domain || host.hasSuffix("." + domain),
              requestPath.hasPrefix(path),
              !isSecure || url.scheme?.lowercased() == "https" else { return false }
        return true
    }
}

public protocol HTTPCookieStore: Sendable {
    func cookies(for url: URL, sourceIdentifier: String?) async -> [HTTPCookie]
    func store(_ cookies: [HTTPCookie], for url: URL, sourceIdentifier: String?) async
    func removeAll(sourceIdentifier: String?) async
}

public actor InMemoryHTTPCookieStore: HTTPCookieStore {
    private var storage: [String: [HTTPCookie]] = [:]

    public init() {}

    public func cookies(for url: URL, sourceIdentifier: String?) -> [HTTPCookie] {
        storage[key(for: url, sourceIdentifier: sourceIdentifier)]?.filter { $0.matches(url) } ?? []
    }

    public func store(_ cookies: [HTTPCookie], for url: URL, sourceIdentifier: String?) {
        let key = key(for: url, sourceIdentifier: sourceIdentifier)
        var values = storage[key] ?? []
        for cookie in cookies {
            values.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            values.append(cookie)
        }
        storage[key] = values
    }

    public func removeAll(sourceIdentifier: String?) {
        if let sourceIdentifier {
            storage[sourceIdentifier] = nil
        } else {
            storage.removeAll()
        }
    }

    private func key(for url: URL, sourceIdentifier: String?) -> String {
        sourceIdentifier ?? url.host?.lowercased() ?? url.absoluteString
    }
}

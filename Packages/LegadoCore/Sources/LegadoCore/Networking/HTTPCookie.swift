import Foundation

public struct HTTPCookie: Codable, Equatable, Sendable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expires: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool
    public let isHostOnly: Bool

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expires: Date? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false,
        isHostOnly: Bool = false
    ) {
        self.name = name
        self.value = value
        self.domain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        self.path = path.isEmpty || !path.hasPrefix("/") ? "/" : path
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.isHostOnly = isHostOnly
    }

    public var isSessionCookie: Bool { expires == nil }

    public func matches(_ url: URL, now: Date = Date()) -> Bool {
        let requestPath = url.path.isEmpty ? "/" : url.path
        guard expires.map({ $0 > now }) ?? true,
              let host = url.host?.lowercased(),
              isHostOnly ? host == domain : Self.domainMatches(host: host, domain: domain),
              Self.pathMatches(requestPath: requestPath, cookiePath: path),
              !isSecure || url.scheme?.lowercased() == "https" else { return false }
        return true
    }

    public static func domainMatches(host: String, domain: String) -> Bool {
        let host = host.lowercased()
        let domain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || host.hasSuffix("." + domain)
    }

    public static func pathMatches(requestPath: String, cookiePath: String) -> Bool {
        if requestPath == cookiePath { return true }
        guard requestPath.hasPrefix(cookiePath) else { return false }
        return cookiePath.hasSuffix("/") || requestPath.dropFirst(cookiePath.count).first == "/"
    }

    private enum CodingKeys: String, CodingKey {
        case name, value, domain, path, expires, isSecure, isHTTPOnly, isHostOnly
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            value: try container.decode(String.self, forKey: .value),
            domain: try container.decode(String.self, forKey: .domain),
            path: try container.decodeIfPresent(String.self, forKey: .path) ?? "/",
            expires: try container.decodeIfPresent(Date.self, forKey: .expires),
            isSecure: try container.decodeIfPresent(Bool.self, forKey: .isSecure) ?? false,
            isHTTPOnly: try container.decodeIfPresent(Bool.self, forKey: .isHTTPOnly) ?? false,
            // Old READ3-IOS values used domain-cookie matching for every record.
            isHostOnly: try container.decodeIfPresent(Bool.self, forKey: .isHostOnly) ?? false
        )
    }
}

public protocol HTTPCookieStore: Sendable {
    func cookies(for url: URL, sourceIdentifier: String?) async throws -> [HTTPCookie]
    func store(_ cookies: [HTTPCookie], for url: URL, sourceIdentifier: String?) async throws
    func removeAll(sourceIdentifier: String?) async throws
}

public struct StoredHTTPCookie: Codable, Equatable, Sendable {
    public let cookie: HTTPCookie
    public let sourceIdentifier: String?

    public init(cookie: HTTPCookie, sourceIdentifier: String?) {
        self.cookie = cookie
        self.sourceIdentifier = sourceIdentifier
    }
}

public struct HTTPCookieCollection: Codable, Equatable, Sendable {
    public private(set) var records: [StoredHTTPCookie]

    public init(records: [StoredHTTPCookie] = []) {
        self.records = records
    }

    public mutating func cookies(for url: URL, now: Date = Date()) -> [HTTPCookie] {
        removeExpired(now: now)
        return records.map(\.cookie)
            .filter { $0.matches(url, now: now) }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.path.count != rhs.element.path.count {
                    return lhs.element.path.count > rhs.element.path.count
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public mutating func store(
        _ cookies: [HTTPCookie],
        sourceIdentifier: String?,
        now: Date = Date()
    ) {
        removeExpired(now: now)
        for cookie in cookies {
            records.removeAll { Self.sameIdentity($0.cookie, cookie) }
            if cookie.expires.map({ $0 <= now }) != true {
                records.append(StoredHTTPCookie(cookie: cookie, sourceIdentifier: sourceIdentifier))
            }
        }
    }

    public mutating func removeAll(sourceIdentifier: String?) {
        if let sourceIdentifier {
            records.removeAll { $0.sourceIdentifier == sourceIdentifier }
        } else {
            records.removeAll()
        }
    }

    public mutating func removeExpired(now: Date = Date()) {
        records.removeAll { $0.cookie.expires.map { $0 <= now } == true }
    }

    private static func sameIdentity(_ lhs: HTTPCookie, _ rhs: HTTPCookie) -> Bool {
        lhs.name == rhs.name && lhs.domain == rhs.domain && lhs.path == rhs.path
    }
}

public actor InMemoryHTTPCookieStore: HTTPCookieStore {
    private var collection = HTTPCookieCollection()

    public init() {}

    public func cookies(for url: URL, sourceIdentifier: String?) throws -> [HTTPCookie] {
        // Android's CookieStore is shared by effective domain. sourceIdentifier
        // records ownership for targeted removal; it is not a visibility scope.
        collection.cookies(for: url)
    }

    public func store(_ cookies: [HTTPCookie], for url: URL, sourceIdentifier: String?) throws {
        collection.store(cookies, sourceIdentifier: sourceIdentifier)
    }

    public func removeAll(sourceIdentifier: String?) throws {
        collection.removeAll(sourceIdentifier: sourceIdentifier)
    }
}

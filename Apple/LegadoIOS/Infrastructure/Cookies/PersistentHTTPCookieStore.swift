import Foundation
import LegadoCore

actor PersistentHTTPCookieStore: HTTPCookieStore {
    private let persistence: any CookiePersistence
    private var collection = HTTPCookieCollection()
    private var isLoaded = false

    init(persistence: any CookiePersistence = KeychainCookiePersistence()) {
        self.persistence = persistence
    }

    func cookies(for url: URL, sourceIdentifier: String?) async throws -> [LegadoCore.HTTPCookie] {
        try await ensureLoaded()
        let previousCount = collection.records.count
        let values = collection.cookies(for: url)
        if collection.records.count != previousCount {
            try await persist()
        }
        return values
    }

    func store(
        _ cookies: [LegadoCore.HTTPCookie],
        for url: URL,
        sourceIdentifier: String?
    ) async throws {
        try await ensureLoaded()
        collection.store(cookies, sourceIdentifier: sourceIdentifier)
        try await persist()
    }

    func removeAll(sourceIdentifier: String?) async throws {
        try await ensureLoaded()
        collection.removeAll(sourceIdentifier: sourceIdentifier)
        try await persist()
    }

    private func ensureLoaded() async throws {
        guard !isLoaded else { return }
        if let data = try await persistence.load() {
            collection = try JSONDecoder().decode(HTTPCookieCollection.self, from: data)
        }
        collection.removeExpired()
        isLoaded = true
        try await persist()
    }

    private func persist() async throws {
        if collection.records.isEmpty {
            try await persistence.remove()
        } else {
            try await persistence.save(JSONEncoder().encode(collection))
        }
    }
}

/// Platform-neutral seam for the future WKHTTPCookieStore adapter. The login
/// feature will push native cookies before navigation and pull WebKit cookies
/// after login without exposing WebKit types to LegadoCore.
protocol WebCookieSynchronizing: Sendable {
    func copyNativeCookiesToWebView(for url: URL, sourceIdentifier: String?) async throws
    func copyWebViewCookiesToNative(for url: URL, sourceIdentifier: String?) async throws
}

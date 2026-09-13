import Foundation
import LegadoCore

/// Private runner interchange only. Never included in the CLI report.
struct DiagnosticRequestSnapshot: Codable {
    let url: String
    let method: String
    let headers: [String: String]
    let maximumRedirects: Int
    let hasBody: Bool

    init(_ request: HTTPRequest) {
        url = request.url.absoluteString
        method = request.method.rawValue
        headers = Dictionary(uniqueKeysWithValues: request.headers.map { ($0.name, $0.value) })
        if case let .follow(hops) = request.redirectPolicy { maximumRedirects = min(20, max(0, hops)) }
        else { maximumRedirects = 0 }
        hasBody = request.body != nil
    }
}

actor DiagnosticRequestCapture: HTTPClient {
    let transport: any HTTPClient
    let directory: URL
    private var captured = false

    init(transport: any HTTPClient, directory: URL) {
        self.transport = transport
        self.directory = directory
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if !captured {
            captured = true
            // Capture failure must not replace the original Swift transport outcome.
            do {
                try (request.body ?? Data()).write(to: directory.appendingPathComponent("request.body"))
                try JSONEncoder().encode(DiagnosticRequestSnapshot(request))
                    .write(to: directory.appendingPathComponent("request.json"))
            } catch { /* Missing snapshot is reported separately by the runner. */ }
        }
        return try await transport.send(request)
    }
}

struct DiagnosticReplayClient: HTTPClient {
    let directory: URL

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        struct Metadata: Decodable {
            let http_code: Int
            let url_effective: String
            let num_redirects: Int
            let content_type: String?
        }
        let metadata = try JSONDecoder().decode(Metadata.self,
            from: Data(contentsOf: directory.appendingPathComponent("curl.stdout")))
        guard let finalURL = URL(string: metadata.url_effective),
              (100...599).contains(metadata.http_code) else { throw HTTPError.invalidResponse }
        return HTTPResponse(statusCode: metadata.http_code,
            headers: HTTPHeaders(["Content-Type": metadata.content_type ?? ""]),
            data: try Data(contentsOf: directory.appendingPathComponent("curl.body")),
            finalURL: finalURL,
            redirects: metadata.num_redirects > 0
                ? [HTTPRedirect(from: request.url, to: finalURL, statusCode: 302)] : [])
    }
}

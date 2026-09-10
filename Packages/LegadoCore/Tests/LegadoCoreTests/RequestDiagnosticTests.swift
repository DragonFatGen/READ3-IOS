import Foundation
import XCTest
@testable import LegadoCore

final class RequestDiagnosticTests: XCTestCase {
    func testURLNetworkClassificationUsesCodesNotDescriptions() throws {
        let cases: [(URLError.Code, RequestDiagnostic.Kind)] = [
            (.badURL, .requestConstruction), (.unsupportedURL, .requestConstruction),
            (.cannotFindHost, .dns), (.dnsLookupFailed, .dns),
            (.cannotConnectToHost, .connection), (.networkConnectionLost, .connection),
            (.notConnectedToInternet, .connection), (.secureConnectionFailed, .tls),
            (.serverCertificateHasBadDate, .tls), (.serverCertificateUntrusted, .tls),
            (.serverCertificateHasUnknownRoot, .tls), (.serverCertificateNotYetValid, .tls),
            (.clientCertificateRejected, .tls), (.clientCertificateRequired, .tls),
            (.timedOut, .timeout), (.cancelled, .cancelled),
            (.badServerResponse, .otherNetwork), (.unknown, .unknown)
        ]
        for (code, kind) in cases {
            let error = NSError(domain: NSURLErrorDomain, code: code.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "private-description DNS TLS timeout",
                NSURLErrorFailingURLStringErrorKey: "https://private-host.invalid/?credential=private-query",
                "Cookie": "private-cookie", "Authorization": "private-token"
            ])
            let diagnostic = RequestDiagnostic.network(error)
            XCTAssertEqual(diagnostic.kind, kind)
            XCTAssertEqual(diagnostic.errorDomain, NSURLErrorDomain)
            XCTAssertEqual(diagnostic.errorCode, code.rawValue)
            XCTAssertNil(diagnostic.httpStatusCode)
            let json = String(decoding: try JSONEncoder().encode(diagnostic), as: UTF8.self)
            XCTAssertFalse(json.contains("private-"))
            XCTAssertFalse(HTTPError.networkFailure(diagnostic).localizedDescription.contains("private-"))
        }
        XCTAssertEqual(RequestDiagnostic.network(URLError(.timedOut)).kind, .timeout)
        XCTAssertEqual(RequestDiagnostic.network(CancellationError()).kind, .cancelled)
    }

    func testUnknownDomainsAndCodesDoNotInventCauses() {
        let custom = RequestDiagnostic.network(NSError(
            domain: "https://private-domain.invalid/?token=private-token", code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "DNS failure"]
        ))
        XCTAssertEqual(custom.kind, .unknown)
        XCTAssertNil(custom.errorDomain)
        XCTAssertNil(custom.errorCode)
        let future = RequestDiagnostic.network(NSError(domain: NSURLErrorDomain, code: -987654))
        XCTAssertEqual(future.kind, .unknown)
        XCTAssertEqual(future.errorCode, -987654)
        let posix = RequestDiagnostic.network(NSError(domain: NSPOSIXErrorDomain, code: 2))
        XCTAssertEqual(posix.kind, .unknown)
        XCTAssertEqual(posix.errorDomain, NSPOSIXErrorDomain)
        XCTAssertEqual(posix.errorCode, 2)
        XCTAssertEqual(RequestDiagnostic.network(HTTPError.transportError("DNS timeout")).kind, .unknown)
    }

    func testConstructionAndResponseMetadataStaySeparate() {
        for error in [HTTPError.invalidURL("private-url"), .invalidRequestOptions("private-options"),
                      .invalidHeaders("private-headers"), .unsupportedMethod("private-method")] {
            let diagnostic = RequestDiagnostic.construction(error)
            XCTAssertEqual(diagnostic.kind, .requestConstruction)
            XCTAssertNil(diagnostic.errorDomain)
            XCTAssertNil(diagnostic.errorCode)
            XCTAssertNil(diagnostic.httpStatusCode)
        }
        let error = URLError(.networkConnectionLost)
        let received = RequestDiagnostic.network(error, httpStatusCode: 503)
        XCTAssertEqual(received.httpStatusCode, 503)
        XCTAssertEqual(RequestDiagnostic.network(HTTPError.networkFailure(received)), received)
        XCTAssertNil(RequestDiagnostic.network(error).httpStatusCode)
        XCTAssertNil(RequestDiagnostic.network(error, httpStatusCode: 0).httpStatusCode)
    }
}

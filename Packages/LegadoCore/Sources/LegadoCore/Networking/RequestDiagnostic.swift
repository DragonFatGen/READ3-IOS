import Foundation

/// Safe metadata only: never retains NSError.userInfo, URLs or localized descriptions.
public struct RequestDiagnostic: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case requestConstruction, dns, connection, tls, timeout, cancelled, otherNetwork, unknown
    }

    public let kind: Kind
    public let errorDomain: String?
    public let errorCode: Int?
    /// The response accompanying this failure, not a previous request or redirect.
    public let httpStatusCode: Int?

    private init(
        kind: Kind,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        httpStatusCode: Int? = nil
    ) {
        self.kind = kind
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.httpStatusCode = httpStatusCode
    }

    public static func construction(_ error: any Error) -> Self {
        let metadata = network(error)
        return Self(kind: .requestConstruction, errorDomain: metadata.errorDomain,
                    errorCode: metadata.errorCode)
    }

    public static func network(_ error: any Error, httpStatusCode: Int? = nil) -> Self {
        if case let HTTPError.networkFailure(diagnostic) = error { return diagnostic }
        let status = httpStatusCode.flatMap { (100...599).contains($0) ? $0 : nil }
        if error is CancellationError { return Self(kind: .cancelled, httpStatusCode: status) }
        let native = error as NSError
        // Custom domains may themselves contain private data. Keep only known system domains.
        let domain = [NSURLErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain]
            .contains(native.domain) ? native.domain : nil
        let kind: Kind
        if native.domain == NSURLErrorDomain {
            typealias Code = URLError.Code
            switch native.code {
            case Code.badURL.rawValue, Code.unsupportedURL.rawValue: kind = .requestConstruction
            case Code.cannotFindHost.rawValue, Code.dnsLookupFailed.rawValue: kind = .dns
            case Code.cannotConnectToHost.rawValue, Code.networkConnectionLost.rawValue, Code.notConnectedToInternet.rawValue:
                kind = .connection
            case Code.secureConnectionFailed.rawValue, Code.serverCertificateHasBadDate.rawValue,
                 Code.serverCertificateUntrusted.rawValue, Code.serverCertificateHasUnknownRoot.rawValue,
                 Code.serverCertificateNotYetValid.rawValue, Code.clientCertificateRejected.rawValue,
                 Code.clientCertificateRequired.rawValue: kind = .tls
            case Code.timedOut.rawValue: kind = .timeout
            case Code.cancelled.rawValue: kind = .cancelled
            case Code.resourceUnavailable.rawValue, Code.badServerResponse.rawValue, Code.httpTooManyRedirects.rawValue,
                 Code.redirectToNonExistentLocation.rawValue, Code.cannotParseResponse.rawValue,
                 Code.cannotDecodeRawData.rawValue, Code.cannotDecodeContentData.rawValue: kind = .otherNetwork
            default: kind = .unknown
            }
        } else {
            // POSIX/OSStatus codes are retained without guessing a platform-specific cause.
            kind = .unknown
        }
        return Self(kind: kind, errorDomain: domain,
                    errorCode: domain == nil ? nil : native.code, httpStatusCode: status)
    }
}

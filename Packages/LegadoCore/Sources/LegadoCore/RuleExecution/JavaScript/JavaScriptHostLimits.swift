import Foundation

public struct JavaScriptHostLimits: Sendable, Equatable {
    public var maximumNetworkRequestsPerExecution: Int
    public var maximumRequestBodyBytes: Int
    public var maximumResponseBodyBytes: Int

    public init(
        maximumNetworkRequestsPerExecution: Int = 16,
        maximumRequestBodyBytes: Int = 1_048_576,
        maximumResponseBodyBytes: Int = 8_388_608
    ) {
        self.maximumNetworkRequestsPerExecution = max(0, maximumNetworkRequestsPerExecution)
        self.maximumRequestBodyBytes = max(0, maximumRequestBodyBytes)
        self.maximumResponseBodyBytes = max(0, maximumResponseBodyBytes)
    }

    public static let `default` = JavaScriptHostLimits()
}

/// Mutable state owned by exactly one JavaScript evaluation. It is a value type
/// so counters cannot leak between contexts or executor instances.
public struct JavaScriptHostBudget: Sendable, Equatable {
    public let limits: JavaScriptHostLimits
    public private(set) var networkRequestCount: Int

    public init(limits: JavaScriptHostLimits = .default) {
        self.limits = limits
        networkRequestCount = 0
    }

    public mutating func beginRequest(body: String? = nil) throws {
        guard networkRequestCount < limits.maximumNetworkRequestsPerExecution else {
            throw JavaScriptHostError.requestLimitExceeded(
                maximum: limits.maximumNetworkRequestsPerExecution
            )
        }
        if let body {
            let byteCount = body.utf8.count
            guard byteCount <= limits.maximumRequestBodyBytes else {
                throw JavaScriptHostError.requestBodyLimitExceeded(
                    actual: byteCount,
                    maximum: limits.maximumRequestBodyBytes
                )
            }
        }
        networkRequestCount += 1
    }

    public func validate(_ response: JavaScriptHTTPResponseSnapshot) throws {
        let byteCount = response.body.utf8.count
        guard byteCount <= limits.maximumResponseBodyBytes else {
            throw JavaScriptHostError.responseBodyLimitExceeded(
                actual: byteCount,
                maximum: limits.maximumResponseBodyBytes
            )
        }
    }

    public func validateAjaxBody(_ body: String?) throws {
        guard let body else { return }
        let byteCount = body.utf8.count
        guard byteCount <= limits.maximumResponseBodyBytes else {
            throw JavaScriptHostError.responseBodyLimitExceeded(
                actual: byteCount,
                maximum: limits.maximumResponseBodyBytes
            )
        }
    }
}

public enum JavaScriptHostError: Error, Sendable, Equatable {
    case networkUnavailable
    case invalidRequest(String)
    case transportFailed(String)
    case unsupportedCharset(String)
    case requestLimitExceeded(maximum: Int)
    case requestBodyLimitExceeded(actual: Int, maximum: Int)
    case responseBodyLimitExceeded(actual: Int, maximum: Int)
    case timeout
    case cancelled
    case unsupportedHostMethod(String)
}

extension JavaScriptHostError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            "JavaScript network access is unavailable."
        case let .invalidRequest(message):
            "Invalid JavaScript host request: \(message)"
        case let .transportFailed(message):
            "JavaScript host transport failed: \(message)"
        case let .unsupportedCharset(charset):
            "Unsupported JavaScript host response charset: \(charset)"
        case let .requestLimitExceeded(maximum):
            "JavaScript network request limit exceeded (maximum \(maximum))."
        case let .requestBodyLimitExceeded(actual, maximum):
            "JavaScript request body is \(actual) bytes; maximum is \(maximum)."
        case let .responseBodyLimitExceeded(actual, maximum):
            "JavaScript response body is \(actual) bytes; maximum is \(maximum)."
        case .timeout:
            "JavaScript host request timed out."
        case .cancelled:
            "JavaScript host request was cancelled."
        case let .unsupportedHostMethod(method):
            "Unsupported JavaScript host method: \(method)"
        }
    }

    /// Android `ajax` catches request failures and returns error text, whereas
    /// jsoup-backed get/post/head leave failures as JavaScript exceptions.
    public var isAndroidAjaxTextResult: Bool {
        switch self {
        case .networkUnavailable, .invalidRequest, .transportFailed,
             .unsupportedCharset, .timeout:
            true
        case .requestLimitExceeded, .requestBodyLimitExceeded,
             .responseBodyLimitExceeded, .cancelled, .unsupportedHostMethod:
            false
        }
    }
}

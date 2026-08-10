/// The synchronous host surface observed by an executing Legado script.
///
/// Blocking implementations are only safe on a dedicated native-thread worker.
/// This protocol must never be implemented by synchronously waiting for the
/// async `HTTPClient`, and it must not be called on the MainActor or a Swift
/// cooperative-executor worker. The current production runtime intentionally
/// has no network implementation; immediate fakes are supported for tests.
public protocol RuleJavaScriptHost: Sendable {
    func ajax(
        _ url: String,
        context: JavaScriptExecutionContext
    ) throws -> String?

    func get(
        _ url: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot

    func post(
        _ url: String,
        body: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot

    func head(
        _ url: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot
}

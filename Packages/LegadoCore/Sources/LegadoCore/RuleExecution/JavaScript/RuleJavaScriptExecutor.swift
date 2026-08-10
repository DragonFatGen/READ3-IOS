public protocol RuleJavaScriptExecutor: Sendable {
    func execute(
        script: String,
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptExecutionResult
}

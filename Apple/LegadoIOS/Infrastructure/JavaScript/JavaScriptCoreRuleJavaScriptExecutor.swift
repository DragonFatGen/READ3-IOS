import Foundation
import JavaScriptCore
import LegadoCore

/// Executes one pure JavaScript rule in an isolated JavaScriptCore context.
/// Engine-native objects never escape this synchronous call.
struct JavaScriptCoreRuleJavaScriptExecutor: RuleJavaScriptExecutor, Sendable {
    private static let maximumScriptBytes = 1_000_000
    private static let maximumContainerMembers: UInt32 = 100_000

    func execute(
        script: String,
        context executionContext: JavaScriptExecutionContext
    ) throws -> JavaScriptExecutionResult {
        guard script.utf8.count <= Self.maximumScriptBytes else {
            throw JavaScriptExecutionError.resourceLimitExceeded("Script exceeds 1000000 UTF-8 bytes")
        }
        guard let context = JSContext() else {
            throw JavaScriptExecutionError.evaluationFailed("Unable to create JavaScriptCore context")
        }

        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString() ?? "Unknown JavaScriptCore exception"
        }

        // Capture Object.keys before source code can replace the global Object.
        let objectKeys = context.evaluateScript(
            "(function(keys) { return function(value) { return keys(value); }; })(Object.keys)"
        )
        context.setObject(
            bridgedResult(executionContext.result),
            forKeyedSubscript: "result" as NSString
        )
        context.setObject(
            executionContext.baseUrl,
            forKeyedSubscript: "baseUrl" as NSString
        )

        exceptionMessage = nil
        guard let value = context.evaluateScript(script) else {
            throw JavaScriptExecutionError.evaluationFailed(
                exceptionMessage ?? "JavaScriptCore returned no result"
            )
        }
        if let exceptionMessage {
            throw JavaScriptExecutionError.evaluationFailed(exceptionMessage)
        }
        return try snapshot(value, objectKeys: objectKeys, depth: 0)
    }

    private func bridgedResult(_ value: RuleValue) -> Any {
        switch value {
        case .none:
            NSNull()
        case let .string(value):
            value
        case let .strings(values):
            values
        }
    }

    private func snapshot(
        _ value: JSValue,
        objectKeys: JSValue?,
        depth: Int
    ) throws -> JavaScriptExecutionResult {
        guard depth <= 64 else {
            throw JavaScriptExecutionError.resultConversionFailed("Result nesting exceeds 64 levels")
        }
        if value.isUndefined { return .undefined }
        if value.isNull { return .null }
        if value.isBoolean { return .boolean(value.toBool()) }
        if value.isNumber { return .number(value.toDouble()) }
        if value.isString { return .string(value.toString()) }
        if value.isArray {
            let length = value.forProperty("length")?.toUInt32() ?? 0
            guard length <= Self.maximumContainerMembers else {
                throw JavaScriptExecutionError.resourceLimitExceeded("Array exceeds 100000 members")
            }
            var result: [JavaScriptExecutionResult] = []
            result.reserveCapacity(Int(length))
            for index in 0..<length {
                guard let item = value.atIndex(Int(index)) else {
                    result.append(.undefined)
                    continue
                }
                result.append(try snapshot(item, objectKeys: objectKeys, depth: depth + 1))
            }
            return .array(result)
        }
        if value.isObject {
            guard let keysValue = objectKeys?.call(withArguments: [value]),
                  let keys = keysValue.toArray() as? [String] else {
                throw JavaScriptExecutionError.resultConversionFailed("Unable to enumerate object keys")
            }
            guard keys.count <= Int(Self.maximumContainerMembers) else {
                throw JavaScriptExecutionError.resourceLimitExceeded("Object exceeds 100000 members")
            }
            var result: [String: JavaScriptExecutionResult] = [:]
            for key in keys.sorted() {
                guard let item = value.forProperty(key) else { continue }
                result[key] = try snapshot(item, objectKeys: objectKeys, depth: depth + 1)
            }
            return .object(result)
        }
        throw JavaScriptExecutionError.resultConversionFailed("Unsupported JavaScriptCore result type")
    }
}

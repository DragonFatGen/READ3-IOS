import Foundation
import JavaScriptCore
import LegadoCore

/// Executes one pure JavaScript rule in an isolated JavaScriptCore context.
/// Engine-native objects never escape this synchronous call.
struct JavaScriptCoreRuleJavaScriptExecutor: RuleJavaScriptExecutor, Sendable {
    private static let maximumScriptBytes = 1_000_000
    private static let maximumContainerMembers: UInt32 = 100_000
    private let host: (any RuleJavaScriptHost)?
    private let hostLimits: JavaScriptHostLimits

    init(
        host: (any RuleJavaScriptHost)? = nil,
        hostLimits: JavaScriptHostLimits = .default
    ) {
        self.host = host
        self.hostLimits = hostLimits
    }

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
        if let host {
            try installHost(
                host,
                limits: hostLimits,
                executionContext: executionContext,
                in: context,
                exceptionMessage: &exceptionMessage
            )
        }

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

    private func installHost(
        _ host: any RuleJavaScriptHost,
        limits: JavaScriptHostLimits,
        executionContext: JavaScriptExecutionContext,
        in context: JSContext,
        exceptionMessage: inout String?
    ) throws {
        let state = JavaScriptHostInvocationState(
            host: host,
            limits: limits,
            executionContext: executionContext
        )
        let dispatch: @convention(block) (String, String, String, String) -> String = {
            method, url, body, headersJSON in
            state.invoke(method: method, url: url, body: body, headersJSON: headersJSON)
        }
        context.setObject(dispatch, forKeyedSubscript: "__legadoHostCall" as NSString)
        exceptionMessage = nil
        guard context.evaluateScript(Self.hostBootstrap) != nil, exceptionMessage == nil else {
            throw JavaScriptExecutionError.evaluationFailed(
                exceptionMessage ?? "Unable to install JavaScript host"
            )
        }
        // The generated allowlisted functions retain the dispatcher. Removing
        // its global name prevents source code from invoking the raw transport.
        context.evaluateScript("delete this.__legadoHostCall")
        if let exceptionMessage {
            throw JavaScriptExecutionError.evaluationFailed(exceptionMessage)
        }
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

    private static let hostBootstrap = #"""
    (function(dispatch, parse, stringify, freeze, objectKeys, stringValue, errorValue) {
        function call(method, url, body, headers) {
            var headersJSON;
            try {
                headersJSON = stringify(headers == null ? {} : headers);
            } catch (_) {
                throw new errorValue("Invalid headers object");
            }
            var envelope = parse(dispatch(
                method,
                stringValue(url),
                body == null ? "" : stringValue(body),
                headersJSON
            ));
            if (!envelope.ok) {
                throw new errorValue(envelope.error || "JavaScript host call failed");
            }
            return envelope;
        }

        function valueForCaseInsensitiveKey(values, name) {
            var wanted = stringValue(name).toLowerCase();
            var names = objectKeys(values);
            for (var index = 0; index < names.length; index++) {
                if (names[index].toLowerCase() === wanted) return values[names[index]];
            }
            return undefined;
        }

        function response(snapshot) {
            var headers = freeze(snapshot.headers || {});
            var cookies = freeze(snapshot.cookies || {});
            return freeze({
                body: function() { return snapshot.body; },
                statusCode: function() { return snapshot.statusCode; },
                statusMessage: function() { return snapshot.statusMessage; },
                headers: function() { return headers; },
                header: function(name) { return valueForCaseInsensitiveKey(headers, name); },
                cookies: function() { return cookies; },
                cookie: function(name) { return cookies[stringValue(name)]; },
                url: function() { return snapshot.url; },
                contentType: function() { return snapshot.contentType == null ? null : snapshot.contentType; },
                charset: function() { return snapshot.charset == null ? null : snapshot.charset; },
                method: function() { return snapshot.method; }
            });
        }

        this.java = freeze({
            ajax: function(url) {
                var envelope = call("ajax", url, "", {});
                return envelope.isNull ? null : envelope.body;
            },
            get: function(url, headers) {
                if (arguments.length < 2 || headers == null) {
                    throw new errorValue("java.get requires url and headers");
                }
                return response(call("get", url, "", headers).response);
            },
            post: function(url, body, headers) {
                if (arguments.length < 3 || headers == null) {
                    throw new errorValue("java.post requires url, body, and headers");
                }
                return response(call("post", url, body, headers).response);
            },
            head: function(url, headers) {
                if (arguments.length < 2 || headers == null) {
                    throw new errorValue("java.head requires url and headers");
                }
                return response(call("head", url, "", headers).response);
            }
        });
    })(__legadoHostCall, JSON.parse, JSON.stringify, Object.freeze, Object.keys, String, Error);
    """#
}

private final class JavaScriptHostInvocationState {
    private let host: any RuleJavaScriptHost
    private let executionContext: JavaScriptExecutionContext
    private var budget: JavaScriptHostBudget
    private let encoder: JSONEncoder

    init(
        host: any RuleJavaScriptHost,
        limits: JavaScriptHostLimits,
        executionContext: JavaScriptExecutionContext
    ) {
        self.host = host
        self.executionContext = executionContext
        budget = JavaScriptHostBudget(limits: limits)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func invoke(method: String, url: String, body: String, headersJSON: String) -> String {
        do {
            let headers = try decodeHeaders(headersJSON)
            switch method {
            case "ajax":
                try budget.beginRequest()
                do {
                    let result = try host.ajax(url, context: executionContext)
                    try budget.validateAjaxBody(result)
                    return encode(.ajax(result))
                } catch let error as JavaScriptHostError where error.isAndroidAjaxTextResult {
                    return encode(.ajax(error.localizedDescription))
                } catch let error as JavaScriptHostError {
                    throw error
                } catch {
                    // Android AnalyzeRule.ajax catches every request throwable
                    // and exposes error text rather than a Rhino exception.
                    return encode(.ajax(error.localizedDescription))
                }
            case "get":
                try budget.beginRequest()
                return try responseEnvelope(
                    host.get(url, headers: headers, context: executionContext)
                )
            case "post":
                try budget.beginRequest(body: body)
                return try responseEnvelope(
                    host.post(url, body: body, headers: headers, context: executionContext)
                )
            case "head":
                try budget.beginRequest()
                return try responseEnvelope(
                    host.head(url, headers: headers, context: executionContext)
                )
            default:
                throw JavaScriptHostError.unsupportedHostMethod(method)
            }
        } catch {
            return encode(.failure(error.localizedDescription))
        }
    }

    private func responseEnvelope(
        _ response: JavaScriptHTTPResponseSnapshot
    ) throws -> String {
        try budget.validate(response)
        return encode(.response(response))
    }

    private func decodeHeaders(_ json: String) throws -> [String: String] {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw JavaScriptHostError.invalidRequest("headers must be a string-valued object")
        }
        return value
    }

    private func encode(_ envelope: JavaScriptHostEnvelope) -> String {
        guard let data = try? encoder.encode(envelope) else {
            return #"{"ok":false,"error":"Unable to encode JavaScript host response"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct JavaScriptHostEnvelope: Encodable {
    let ok: Bool
    let body: String?
    let isNull: Bool
    let response: JavaScriptHTTPResponseSnapshot?
    let error: String?

    static func ajax(_ body: String?) -> Self {
        Self(ok: true, body: body, isNull: body == nil, response: nil, error: nil)
    }

    static func response(_ response: JavaScriptHTTPResponseSnapshot) -> Self {
        Self(ok: true, body: nil, isNull: false, response: response, error: nil)
    }

    static func failure(_ error: String) -> Self {
        Self(ok: false, body: nil, isNull: false, response: nil, error: error)
    }
}

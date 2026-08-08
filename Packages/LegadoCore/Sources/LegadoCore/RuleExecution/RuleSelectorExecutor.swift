public protocol RuleSelectorExecutor: Sendable {
    func execute(selector: SelectorRule, input: RuleValue) throws -> RuleValue
    func execute(jsonPath: String, input: RuleValue) throws -> RuleValue
    func execute(xpath: String, input: RuleValue) throws -> RuleValue
}

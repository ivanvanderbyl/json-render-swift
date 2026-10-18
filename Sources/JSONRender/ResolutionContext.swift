/// Everything needed to evaluate visibility conditions and resolve prop
/// expressions, like upstream `VisibilityContext` and `PropResolutionContext`.
public struct ResolutionContext: Sendable {
    /// The state model, read by `$state` and `$bindState`.
    public var state: JSONValue
    /// The current repeat item, or `undefined` outside a repeat scope.
    public var repeatItem: JSONValue
    /// The current repeat index, or `nil` outside a repeat scope.
    public var repeatIndex: Int?
    /// The absolute state path of the current repeat item, for example
    /// "/todos/0". `$bindItem` and `$item` action params resolve against it.
    public var repeatBasePath: String?
    /// Functions available to `$computed` expressions.
    public var functions: [String: ComputedFunction]
    /// Custom `$`-prefixed directives.
    public var directives: DirectiveRegistry?

    public init(
        state: JSONValue = [:],
        repeatItem: JSONValue = .undefined,
        repeatIndex: Int? = nil,
        repeatBasePath: String? = nil,
        functions: [String: ComputedFunction] = [:],
        directives: DirectiveRegistry? = nil
    ) {
        self.state = state
        self.repeatItem = repeatItem
        self.repeatIndex = repeatIndex
        self.repeatBasePath = repeatBasePath
        self.functions = functions
        self.directives = directives
    }
}

/// A function a `$computed` expression calls with its resolved `args`.
public typealias ComputedFunction = @Sendable (JSONObject) throws -> JSONValue

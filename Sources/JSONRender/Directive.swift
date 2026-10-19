/// A custom `$`-prefixed dynamic value, like upstream `DirectiveDefinition`.
public struct DirectiveDefinition: Sendable {
    /// The key that triggers the directive, for example "$format".
    public var name: String
    /// A short description for AI prompts.
    public var description: String?
    /// A JSON Schema for the directive object. Informational: upstream uses it
    /// only for prompt generation and types.
    public var schema: JSONValue
    /// Resolves the directive object. May call ``PropExpression/resolve(_:in:)``
    /// on sub-values to compose with other expressions.
    public var resolve: @Sendable (JSONValue, ResolutionContext) throws -> JSONValue

    /// Keys handled by built-in prop expressions, which directives cannot shadow.
    static let builtInKeys: Set<String> = [
        "$state", "$item", "$index", "$bindState", "$bindItem", "$cond", "$computed", "$template",
    ]

    /// Defines a directive, like upstream `defineDirective`. Throws when the
    /// name does not start with "$" or collides with a built-in expression key.
    public init(
        name: String,
        description: String? = nil,
        schema: JSONValue = .undefined,
        resolve: @escaping @Sendable (JSONValue, ResolutionContext) throws -> JSONValue
    ) throws {
        guard JavaScript.startsWith(name, "$") else {
            throw JavaScriptError.error("Directive name must start with \"$\": got \"\(name)\"")
        }
        if Self.builtInKeys.contains(name) {
            throw JavaScriptError.error("Directive name \"\(name)\" conflicts with a built-in prop expression key")
        }
        self.name = name
        self.description = description
        self.schema = schema
        self.resolve = resolve
    }
}

/// Directives by name, in registration order, like upstream `DirectiveRegistry`.
public struct DirectiveRegistry: Sendable {
    private var order: [String] = []
    private var definitions: [ExactKey: DirectiveDefinition] = [:]

    /// Builds a registry, like upstream `createDirectiveRegistry`. A later
    /// definition with the same name replaces an earlier one and keeps its
    /// position, as `Map.set` does.
    public init(_ directives: [DirectiveDefinition]) {
        for directive in directives {
            if definitions.updateValue(directive, forKey: ExactKey(directive.name)) == nil {
                order.append(directive.name)
            }
        }
    }

    public var count: Int { order.count }

    /// Directive names in registration order.
    public var names: [String] { order }

    public subscript(name: String) -> DirectiveDefinition? { definitions[ExactKey(name)] }

    /// Finds the directive whose key the object has, like upstream
    /// `findDirective`. Throws when the object has more than one directive key.
    public func find(in object: JSONObject) throws -> DirectiveDefinition? {
        var match: DirectiveDefinition?
        for name in order where object.hasKey(name) {
            if let match {
                throw JavaScriptError.error(
                    "Ambiguous directive: object has multiple directive keys (\"\(match.name)\" and \"\(name)\")"
                )
            }
            match = definitions[ExactKey(name)]
        }
        return match
    }
}

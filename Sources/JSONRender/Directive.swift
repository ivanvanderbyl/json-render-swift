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

    /// Defines a directive, like upstream `defineDirective`. Throws when the
    /// name does not start with "$" or collides with a built-in expression key.
    public init(
        name: String,
        description: String? = nil,
        schema: JSONValue = .undefined,
        resolve: @escaping @Sendable (JSONValue, ResolutionContext) throws -> JSONValue
    ) throws {
        self.name = name
        self.description = description
        self.schema = schema
        self.resolve = resolve
    }
}

/// Directives by name, in registration order, like upstream `DirectiveRegistry`.
public struct DirectiveRegistry: Sendable {
    /// Builds a registry, like upstream `createDirectiveRegistry`. A later
    /// definition with the same name replaces an earlier one.
    public init(_ directives: [DirectiveDefinition]) {}

    public var count: Int { 0 }

    public subscript(name: String) -> DirectiveDefinition? { nil }

    /// Finds the directive whose key the object has, like upstream
    /// `findDirective`. Throws when the object has more than one directive key.
    public func find(in object: JSONObject) throws -> DirectiveDefinition? { nil }
}

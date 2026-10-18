/// A component a catalog offers, like an upstream catalog component entry.
public struct ComponentDefinition: Sendable {
    /// The props schema, or nil when the component takes no declared props.
    public var props: JSONSchema?
    /// "default" for children, plus any named slots. Nil when the definition
    /// declares no slots, which turns off upstream's slot name warnings.
    public var slots: [String]?
    /// Event names the component emits, such as "press".
    public var events: [String]
    public var description: String?
    /// Example props for prompts. Kept for parity.
    public var example: JSONValue

    public init(props: JSONSchema? = nil, slots: [String]? = nil, events: [String] = [], description: String? = nil, example: JSONValue = .undefined) {
        self.props = props
        self.slots = slots
        self.events = events
        self.description = description
        self.example = example
    }
}

/// An action a catalog declares, like an upstream catalog action entry.
public struct ActionDefinition: Sendable {
    public var params: JSONSchema?
    public var description: String?

    public init(params: JSONSchema? = nil, description: String? = nil) {
        self.params = params
        self.description = description
    }
}

/// The components and actions a spec may use, like upstream `defineCatalog`.
///
/// ``validate(_:)`` decides exactly what upstream `catalog.validate` decides,
/// including its limits: element props are checked against a component's
/// props schema only when the catalog has a single component with props;
/// otherwise props only need to be an object. Unknown element fields such as
/// `on` and `watch` are accepted and dropped from the parsed data.
public struct Catalog: Sendable {
    public let schema: RendererSchema
    public let components: [String: ComponentDefinition]
    public let actions: [String: ActionDefinition]
    /// Component names in JavaScript key order.
    public let componentNames: [String]
    /// Action names in JavaScript key order.
    public let actionNames: [String]
    /// The schema specs must match, like upstream `catalog.zodSchema()`.
    public let specSchema: JSONSchema

    public init(
        schema: RendererSchema,
        components: KeyValuePairs<String, ComponentDefinition>,
        actions: KeyValuePairs<String, ActionDefinition> = [:]
    ) {
        self.init(
            schema: schema,
            orderedComponents: components.map { ($0.key, $0.value) },
            orderedActions: actions.map { ($0.key, $0.value) }
        )
    }

    init(schema: RendererSchema, orderedComponents: [(String, ComponentDefinition)], orderedActions: [(String, ActionDefinition)]) {
        self.schema = schema
        self.components = Dictionary(orderedComponents, uniquingKeysWith: { $1 })
        self.actions = Dictionary(orderedActions, uniquingKeysWith: { $1 })
        componentNames = Self.javaScriptOrder(orderedComponents.map(\.0))
        actionNames = Self.javaScriptOrder(orderedActions.map(\.0))
        let builder = SpecSchemaBuilder(componentNames: componentNames, components: self.components, actionNames: actionNames)
        specSchema = JSONSchema(root: builder.node(for: schema.spec))
    }

    /// Loads a catalog exported from TypeScript with `exportCatalog` (see
    /// Conformance/src/export-catalog.mjs): `{ "components": { name: { "props":
    /// <JSON Schema>, "slots", "events", "description", "example" } },
    /// "actions": { name: { "params": <JSON Schema>, "description" } } }`.
    public init(manifest: JSONValue, schema: RendererSchema = .react) throws {
        var components: [(String, ComponentDefinition)] = []
        for (name, entry) in manifest["components"].objectValue ?? [:] {
            components.append((name, ComponentDefinition(
                props: try entry["props"].isUndefined ? nil : JSONSchema(entry["props"]),
                slots: entry["slots"].arrayValue?.compactMap(\.stringValue),
                events: (entry["events"].arrayValue ?? []).compactMap(\.stringValue),
                description: entry["description"].stringValue,
                example: entry["example"]
            )))
        }
        var actions: [(String, ActionDefinition)] = []
        for (name, entry) in manifest["actions"].objectValue ?? [:] {
            actions.append((name, ActionDefinition(
                params: try entry["params"].isUndefined ? nil : JSONSchema(entry["params"]),
                description: entry["description"].stringValue
            )))
        }
        self.init(schema: schema, orderedComponents: components, orderedActions: actions)
    }

    /// Validates a spec, like upstream `catalog.validate`.
    public func validate(_ spec: JSONValue) -> SchemaResult {
        specSchema.validate(spec)
    }

    /// `Object.keys` order: array-index names first in numeric order.
    private static func javaScriptOrder(_ names: [String]) -> [String] {
        var object = JSONObject()
        for name in names { object[name] = .null }
        return object.keys
    }
}

/// Builds the spec schema from a renderer schema and catalog, like upstream
/// `buildZodType`.
private struct SpecSchemaBuilder {
    let componentNames: [String]
    let components: [String: ComponentDefinition]
    let actionNames: [String]

    func node(for type: SchemaType) -> SchemaNode {
        let node = SchemaNode()
        switch (type.kind, type.inner) {
        case (.string, _):
            node.types = ["string"]
        case (.number, _):
            node.types = ["number"]
        case (.boolean, _):
            node.types = ["boolean"]
        case let (.array, .type(item)?):
            node.types = ["array"]
            node.items = self.node(for: item)
        case let (.object, .shape(fields)?):
            node.types = ["object"]
            node.hasProperties = true
            node.properties = fields.map { ($0.key, self.node(for: $0.value)) }
            node.required = fields.filter { !$0.value.isOptional }.map(\.key)
        case let (.record, .type(value)?):
            node.types = ["object"]
            node.propertyNames = Self.stringNode()
            node.additional = .schema(self.node(for: value))
        case let (.ref, .path(path)?):
            let keys = self.keys(at: path)
            node.types = ["string"]
            if keys.count == 1 {
                node.constValue = .string(keys[0])
            } else if keys.count > 1 {
                node.enumValues = keys.map(JSONValue.string)
            }
        case let (.propsOf, .path(path)?):
            let schemas = path == "catalog.components" ? componentNames.compactMap { components[$0]?.props } : []
            if schemas.count == 1 { return .embedding(schemas[0]) }
            // Several components: props only need to be an object.
            node.types = ["object"]
            node.propertyNames = Self.stringNode()
            node.additional = .schema(.anything())
        default:
            node.acceptsAnything = true
        }
        return node
    }

    private func keys(at path: String) -> [String] {
        switch path {
        case "catalog.components": componentNames
        case "catalog.actions": actionNames
        default: []
        }
    }

    private static func stringNode() -> SchemaNode {
        let node = SchemaNode()
        node.types = ["string"]
        return node
    }
}

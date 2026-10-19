/// Why a JSON Schema could not be read as a spec schema.
public enum SpecJSONSchemaError: Error, Equatable {
    /// No object schema with `root` and `elements` properties was found.
    case noSpec
    /// The `elements` schema names no element types: its entries need a
    /// `type` property with a `const` or `enum`.
    case noElementTypes
}

/// A JSON Schema a host exports for its specs, used as a catalog.
///
/// Hosts often export one schema for a whole document, for example with
/// zod's `toJSONSchema` on a schema whose elements are a union of one object
/// per component type. This type finds the spec in that schema (an object
/// with `root` and `elements` properties, at the top or in a property), reads
/// each element type and its `props` schema from the union, and validates
/// documents against the whole schema, so per-type props, required fields
/// and limits all apply.
///
/// A schema-valid document is only well formed: graph checks such as cycles
/// and unreachable elements are separate (see ``SpecValidator``).
public struct SpecJSONSchema: Sendable {
    /// The schema document.
    public let document: JSONValue
    /// The compiled schema of the whole document.
    public let schema: JSONSchema
    /// Property names from the document to the spec; empty when the document is the spec.
    public let specPath: [String]
    /// Element types in JavaScript key order.
    public let componentNames: [String]
    /// Each element type's definition, with its props schema.
    public let components: [String: ComponentDefinition]
    private let ordered: [(String, ComponentDefinition)]

    public init(_ document: JSONValue) throws {
        self.document = document
        schema = try JSONSchema(document)
        guard let (path, spec) = Self.findSpec(in: document, path: [], depth: 0) else { throw SpecJSONSchemaError.noSpec }
        specPath = path

        let element = spec["properties"]["elements"]["additionalProperties"]
        let branches = element["anyOf"].arrayValue?.elements ?? element["oneOf"].arrayValue?.elements ?? [element]
        var ordered: [(String, ComponentDefinition)] = []
        for branch in branches {
            let type = branch["properties"]["type"]
            let names: [String] = if case let .string(name) = type["const"] {
                [name]
            } else {
                type["enum"].arrayValue?.compactMap(\.stringValue) ?? []
            }
            let props = branch["properties"]["props"]
            let definition = ComponentDefinition(
                props: props.isUndefined ? nil : try JSONSchema(props),
                description: branch["description"].stringValue
            )
            for name in names where !ordered.contains(where: { $0.0 == name }) {
                ordered.append((name, definition))
            }
        }
        guard !ordered.isEmpty else { throw SpecJSONSchemaError.noElementTypes }
        self.ordered = ordered
        components = Dictionary(ordered, uniquingKeysWith: { first, _ in first })
        componentNames = Catalog(schema: .react, orderedComponents: ordered, orderedActions: []).componentNames
    }

    /// Validates a document against the whole schema.
    public func validate(_ value: JSONValue) -> SchemaResult {
        schema.validate(value)
    }

    /// The spec in a document, or nil when the document is not valid. Like
    /// zod's `safeParse`, the spec is the parsed data.
    public func spec(in value: JSONValue) -> Spec? {
        let result = validate(value)
        guard result.success else { return nil }
        var node = result.data
        for key in specPath { node = node[key] }
        return node.objectValue.map { Spec($0) }
    }

    /// A catalog of the element types, for a registry and for the renderer's
    /// catalog checks.
    public func catalog(schema: RendererSchema = .react) -> Catalog {
        Catalog(schema: schema, orderedComponents: ordered, orderedActions: [])
    }

    private static func findSpec(in node: JSONValue, path: [String], depth: Int) -> ([String], JSONValue)? {
        let properties = node["properties"]
        if !properties["root"].isUndefined, !properties["elements"].isUndefined { return (path, node) }
        guard depth < 4, case let .object(children) = properties else { return nil }
        for (key, child) in children.entries {
            if let found = findSpec(in: child, path: path + [key], depth: depth + 1) { return found }
        }
        return nil
    }
}

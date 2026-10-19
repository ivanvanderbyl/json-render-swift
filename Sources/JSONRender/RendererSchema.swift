/// One field type in a renderer schema, like upstream `SchemaType`.
public struct SchemaType: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case string, number, boolean, array, object, record, any, zod, ref, propsOf, map
    }

    public indirect enum Inner: Sendable, Equatable {
        /// The element type of an array or the value type of a record.
        case type(SchemaType)
        /// The fields of an object or of each map entry, in order.
        case shape([Field])
        /// The catalog path of a `ref` or `propsOf`, such as "catalog.components".
        case path(String)
    }

    public struct Field: Sendable, Equatable {
        public var key: String
        public var value: SchemaType
    }

    public var kind: Kind
    public var inner: Inner?
    /// Upstream `optional`: the field may be missing.
    public var isOptional: Bool

    public init(kind: Kind, inner: Inner? = nil, isOptional: Bool = false) {
        self.kind = kind
        self.inner = inner
        self.isOptional = isOptional
    }

    public static let string = SchemaType(kind: .string)
    public static let number = SchemaType(kind: .number)
    public static let boolean = SchemaType(kind: .boolean)
    public static let any = SchemaType(kind: .any)
    /// A placeholder for a catalog-provided schema (upstream `s.zod()`).
    public static let zod = SchemaType(kind: .zod)

    public static func array(_ item: SchemaType) -> SchemaType { SchemaType(kind: .array, inner: .type(item)) }
    public static func record(_ value: SchemaType) -> SchemaType { SchemaType(kind: .record, inner: .type(value)) }
    public static func object(_ shape: KeyValuePairs<String, SchemaType>) -> SchemaType {
        SchemaType(kind: .object, inner: .shape(shape.map { Field(key: $0.key, value: $0.value) }))
    }
    public static func map(_ entryShape: KeyValuePairs<String, SchemaType>) -> SchemaType {
        SchemaType(kind: .map, inner: .shape(entryShape.map { Field(key: $0.key, value: $0.value) }))
    }
    /// The keys of a catalog entry, such as the component names.
    public static func ref(_ path: String) -> SchemaType { SchemaType(kind: .ref, inner: .path(path)) }
    /// The props of the catalog entries at a path.
    public static func propsOf(_ path: String) -> SchemaType { SchemaType(kind: .propsOf, inner: .path(path)) }

    /// The same type, marked optional.
    public func optional() -> SchemaType {
        var copy = self
        copy.isOptional = true
        return copy
    }
}

/// An action every renderer handles itself, like upstream `BuiltInAction`.
public struct BuiltInAction: Sendable, Equatable {
    public var name: String
    public var description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

/// The grammar of specs and catalogs for a renderer, like upstream
/// `defineSchema`.
public struct RendererSchema: Sendable {
    /// What a spec looks like.
    public var spec: SchemaType
    /// What a catalog provides.
    public var catalog: SchemaType
    /// Rules for AI prompts. Kept for parity; this package does not generate prompts.
    public var defaultRules: [String]
    /// Actions the runtime always handles.
    public var builtInActions: [BuiltInAction]

    public init(spec: SchemaType, catalog: SchemaType, defaultRules: [String] = [], builtInActions: [BuiltInAction] = []) {
        self.spec = spec
        self.catalog = catalog
        self.defaultRules = defaultRules
        self.builtInActions = builtInActions
    }

    /// Creates a catalog from this schema, like upstream `schema.createCatalog`.
    public func createCatalog(
        components: KeyValuePairs<String, ComponentDefinition>,
        actions: KeyValuePairs<String, ActionDefinition> = [:]
    ) -> Catalog {
        Catalog(schema: self, components: components, actions: actions)
    }

    /// The `@json-render/react` schema: elements have `type`, `props`,
    /// `children`, and optional `slots`, `visible` and `repeat`. Prompt rules
    /// are not carried over because this package does not generate prompts.
    public static let react = RendererSchema(
        spec: .object([
            "root": .string,
            "elements": .record(.object([
                "type": .ref("catalog.components"),
                "props": .propsOf("catalog.components"),
                "children": .array(.string),
                "slots": .record(.array(.string)).optional(),
                "visible": .any.optional(),
                "repeat": .any.optional(),
            ])),
        ]),
        catalog: .object([
            "components": .map(["props": .zod, "slots": .array(.string), "description": .string, "example": .any]),
            "actions": .map(["params": .zod, "description": .string]),
        ]),
        builtInActions: [
            BuiltInAction(
                name: "setState",
                description: "Update a value in the state model at the given statePath. Params: { statePath: string, value: any }"
            ),
            BuiltInAction(
                name: "pushState",
                description: #"Append an item to an array in state. Params: { statePath: string, value: any, clearStatePath?: string }. Value can contain {"$state":"/path"} refs and "$id" for auto IDs."#
            ),
            BuiltInAction(
                name: "removeState",
                description: "Remove an item from an array in state by index. Params: { statePath: string, index: number }"
            ),
            BuiltInAction(
                name: "validateForm",
                description: "Validate all registered form fields and write the result to state. Params: { statePath?: string }. Defaults to /formValidation. Result: { valid: boolean, errors: Record<string, string[]> }."
            ),
        ]
    )

    /// The `@json-render/react-native` schema: like ``react`` without `slots`.
    public static let reactNative = RendererSchema(
        spec: .object([
            "root": .string,
            "elements": .record(.object([
                "type": .ref("catalog.components"),
                "props": .propsOf("catalog.components"),
                "children": .array(.string),
                "visible": .any.optional(),
                "repeat": .any.optional(),
            ])),
        ]),
        catalog: .object([
            "components": .map(["props": .zod, "slots": .array(.string), "description": .string, "example": .any]),
            "actions": .map(["params": .zod, "description": .string]),
        ])
    )
}

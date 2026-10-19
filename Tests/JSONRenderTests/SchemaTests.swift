import Testing
@testable import JSONRender

// Ports upstream tests from packages/core/src/schema.test.ts and
// packages/core/src/repeat-schema-parity.test.ts (json-render 0.21.1).
//
// Not applicable, because this port leaves out AI prompt generation and JSON
// Schema export for LLM structured output:
// N/A: "accepts promptTemplate option": prompt templates only shape AI prompts.
// N/A: every "catalog.prompt" case (19): AI prompt generation is out of scope.
// N/A: every "catalog.jsonSchema" case (8): exporting JSON Schema for LLM
//      structured output is out of scope; catalogs are imported from JSON Schema.

/// The shared test schema from upstream schema.test.ts (mirrors the React schema).
let testSchema = RendererSchema(
    spec: .object([
        "root": .string,
        "elements": .record(.object([
            "type": .ref("catalog.components"),
            "props": .propsOf("catalog.components"),
            "children": .array(.string),
            "slots": .record(.array(.string)).optional(),
            "visible": .any.optional(),
        ])),
    ]),
    catalog: .object([
        "components": .map(["props": .zod, "slots": .array(.string), "description": .string, "example": .any]),
        "actions": .map(["description": .string]),
    ])
)

private func objectProps(_ properties: [String: String]) throws -> JSONSchema {
    var schemaProperties = JSONObject()
    for (key, type) in properties.sorted(by: { $0.key < $1.key }) { schemaProperties[key] = ["type": .string(type)] }
    return try JSONSchema([
        "type": "object",
        "properties": .object(schemaProperties),
        "required": .array(JSONArray(properties.keys.sorted().map(JSONValue.string))),
    ])
}

@Suite("schema.test.ts › defineSchema")
struct SchemaDefineSchemaTests {
    @Test("creates a schema with spec and catalog definition")
    func createsSchema() {
        let schema = RendererSchema(spec: .object(["root": .string]), catalog: .object(["components": .map(["props": .zod])]))
        #expect(schema.spec.kind == .object)
        #expect(schema.catalog.kind == .object)
    }

    @Test("accepts defaultRules option")
    func acceptsDefaultRules() {
        let schema = RendererSchema(
            spec: .object(["root": .string]),
            catalog: .object(["components": .map(["props": .zod])]),
            defaultRules: ["Rule A", "Rule B"]
        )
        #expect(schema.defaultRules == ["Rule A", "Rule B"])
    }

    @Test("exposes createCatalog method")
    func exposesCreateCatalog() {
        let schema = RendererSchema(spec: .object(["root": .string]), catalog: .object(["components": .map(["props": .zod])]))
        let catalog = schema.createCatalog(components: [:])
        #expect(catalog.componentNames.isEmpty)
    }
}

@Suite("schema.test.ts › defineCatalog")
struct SchemaDefineCatalogTests {
    @Test("creates catalog with componentNames and actionNames")
    func createsCatalogWithNames() throws {
        let catalog = Catalog(
            schema: testSchema,
            components: [
                "Text": ComponentDefinition(props: try objectProps(["content": "string"]), slots: [], description: "Display text"),
                "Button": ComponentDefinition(props: try objectProps(["label": "string"]), slots: [], description: "A clickable button"),
            ],
            actions: [
                "navigate": ActionDefinition(description: "Navigate to URL"),
                "submit": ActionDefinition(description: "Submit form"),
            ]
        )
        #expect(catalog.componentNames == ["Text", "Button"])
        #expect(catalog.actionNames == ["navigate", "submit"])
    }

    @Test("handles empty components and actions")
    func handlesEmptyCatalog() {
        let catalog = Catalog(schema: testSchema, components: [:], actions: [:])
        #expect(catalog.componentNames.isEmpty)
        #expect(catalog.actionNames.isEmpty)
    }

    @Test("is equivalent to schema.createCatalog")
    func equivalentToCreateCatalog() throws {
        let card = ComponentDefinition(props: try objectProps(["title": "string"]), slots: ["default"], description: "A card")
        let a = Catalog(schema: testSchema, components: ["Card": card], actions: [:])
        let b = testSchema.createCatalog(components: ["Card": card], actions: [:])
        #expect(a.componentNames == b.componentNames)
        #expect(a.actionNames == b.actionNames)
    }

    @Test("exposes the schema on the catalog")
    func exposesSchema() {
        let catalog = Catalog(schema: testSchema, components: [:], actions: [:])
        #expect(catalog.schema.spec == testSchema.spec)
        #expect(catalog.schema.catalog == testSchema.catalog)
    }

    @Test("exposes catalog data")
    func exposesData() throws {
        let catalog = Catalog(
            schema: testSchema,
            components: ["Text": ComponentDefinition(props: try objectProps(["content": "string"]), slots: [], description: "")]
        )
        #expect(catalog.components["Text"]?.slots == [])
        #expect(catalog.components["Text"]?.description == "")
    }
}

@Suite("schema.test.ts › catalog.validate")
struct SchemaCatalogValidateTests {
    let catalog: Catalog

    init() throws {
        catalog = Catalog(
            schema: testSchema,
            components: [
                "Text": ComponentDefinition(props: try objectProps(["content": "string"]), slots: [], description: ""),
                "Card": ComponentDefinition(props: try objectProps(["title": "string"]), slots: ["default"], description: ""),
            ],
            actions: [:]
        )
    }

    @Test("returns data assignable to Spec")
    func returnsSpecData() throws {
        let result = catalog.validate(["root": "card-1", "elements": ["card-1": ["type": "Card", "props": ["title": "Hello"], "children": []]]])
        #expect(result.success)
        let spec = Spec(try #require(result.data.objectValue))
        #expect(spec.root == "card-1")
    }

    @Test("validates a valid spec")
    func validatesValidSpec() {
        let spec: JSONValue = [
            "root": "card-1",
            "elements": [
                "card-1": ["type": "Card", "props": ["title": "Hello"], "children": ["text-1"]],
                "text-1": ["type": "Text", "props": ["content": "World"], "children": []],
            ],
        ]
        let result = catalog.validate(spec)
        #expect(result.success)
        #expect(result.data == spec)
    }

    @Test("accepts elements without visible regardless of zod version (z.any() keys became nonoptional in zod 4.4)")
    func acceptsMissingVisible() {
        let result = catalog.validate(["root": "text-1", "elements": ["text-1": ["type": "Text", "props": ["content": "Hello"], "children": []]]])
        #expect(result.success)
    }

    @Test("still requires children on every element")
    func requiresChildren() {
        let result = catalog.validate(["root": "text-1", "elements": ["text-1": ["type": "Text", "props": ["content": "Hello"]]]])
        #expect(!result.success)
    }

    @Test("rejects spec with wrong root type")
    func rejectsWrongRootType() {
        let result = catalog.validate(["root": 123, "elements": [:]])
        #expect(!result.success)
        #expect(!result.issues.isEmpty)
    }

    @Test("rejects spec with missing root")
    func rejectsMissingRoot() {
        let result = catalog.validate(["elements": [:]])
        #expect(!result.success)
        #expect(!result.issues.isEmpty)
    }

    @Test("rejects spec with invalid component type")
    func rejectsUnknownType() {
        let result = catalog.validate(["root": "x", "elements": ["x": ["type": "NonExistent", "props": [:], "children": []]]])
        #expect(!result.success)
    }

    @Test("returns data on success")
    func returnsData() {
        let result = catalog.validate(["root": "t", "elements": ["t": ["type": "Text", "props": ["content": "hi"], "children": []]]])
        #expect(result.success)
        #expect(!result.data.isUndefined)
        #expect(result.data["root"] == "t")
    }
}

@Suite("schema.test.ts › catalog.zodSchema")
struct SchemaCatalogZodSchemaTests {
    @Test("returns a Zod schema that validates valid specs")
    func validatesValidSpecs() throws {
        let catalog = Catalog(
            schema: testSchema,
            components: ["Text": ComponentDefinition(props: try objectProps(["content": "string"]), slots: [], description: "")]
        )
        let result = catalog.specSchema.validate(["root": "t", "elements": ["t": ["type": "Text", "props": ["content": "hi"], "children": []]]])
        #expect(result.success)
    }

    @Test("returns a Zod schema that rejects invalid specs")
    func rejectsInvalidSpecs() throws {
        let catalog = Catalog(
            schema: testSchema,
            components: ["Text": ComponentDefinition(props: try JSONSchema(["type": "object", "properties": [:]]), slots: [], description: "")]
        )
        #expect(!catalog.specSchema.validate(["root": 42]).success)
    }
}

@Suite("repeat-schema-parity.test.ts › renderer schema repeat parity")
struct SchemaRepeatParityTests {
    // N/A: the image, ink, react-email, react-pdf, solid, svelte and vue
    // entries: those renderers are not part of this port.
    @Test("%s declares repeat as an optional element field", arguments: [
        ("react", RendererSchema.react),
        ("react-native", RendererSchema.reactNative),
    ])
    func declaresOptionalRepeat(name: String, schema: RendererSchema) throws {
        guard case let .shape(spec)? = schema.spec.inner,
              case let .type(elements)? = spec.first(where: { $0.key == "elements" })?.value.inner,
              case let .shape(element)? = elements.inner
        else {
            Issue.record("\(name) has an unexpected spec shape")
            return
        }
        let repeatField = try #require(element.first { $0.key == "repeat" }?.value)
        #expect(repeatField.kind == .any)
        #expect(repeatField.isOptional)
    }
}

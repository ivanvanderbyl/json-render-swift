import Testing
@testable import JSONRender

// Loading a catalog from a JSON Schema a host exports for whole specs, or for
// documents that hold a spec, such as one made with zod's toJSONSchema from a
// schema whose elements are a union discriminated by `type`.

@Suite("Spec JSON Schema")
struct SpecJSONSchemaTests {
    /// An element branch: `type` fixed to a name, with its own props schema.
    static func element(_ type: JSONValue, props: JSONValue) -> JSONValue {
        [
            "type": "object",
            "properties": ["type": type, "props": props, "children": ["type": "array", "items": ["type": "string"]]],
            "required": ["type", "props"],
            "additionalProperties": false,
        ]
    }

    static let textProps: JSONValue = [
        "type": "object", "properties": ["text": ["type": "string"]], "required": ["text"], "additionalProperties": false,
    ]

    static let spec: JSONValue = [
        "type": "object",
        "properties": [
            "root": ["type": "string"],
            "elements": [
                "type": "object",
                "additionalProperties": ["anyOf": [
                    element(["type": "string", "const": "Text"], props: textProps),
                    element(["type": "string", "enum": ["Row", "Column"]], props: ["type": "object", "properties": [:]]),
                ]],
            ],
        ],
        "required": ["root", "elements"],
    ]

    @Test("finds element types and props schemas in a spec schema")
    func findsComponents() throws {
        let loaded = try SpecJSONSchema(Self.spec)
        #expect(loaded.specPath == [])
        #expect(loaded.componentNames == ["Text", "Row", "Column"])
        let text = try #require(loaded.components["Text"]?.props)
        #expect(text.validate(["text": "hi"]).success)
        #expect(!text.validate(["text": 1]).success)
        #expect(loaded.components["Row"]?.props != nil)
    }

    @Test("finds a spec held in a property of the document")
    func findsNestedSpec() throws {
        let document: JSONValue = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "properties": ["version": ["const": "v1"], "spec": Self.spec],
            "required": ["version", "spec"],
            "additionalProperties": false,
        ]
        let loaded = try SpecJSONSchema(document)
        #expect(loaded.specPath == ["spec"])

        let valid: JSONValue = ["version": "v1", "spec": ["root": "t", "elements": ["t": ["type": "Text", "props": ["text": "hi"]]]]]
        #expect(loaded.validate(valid).success)
        #expect(loaded.spec(in: valid)?.root == "t")

        // The whole document is checked, so a props error in one branch fails.
        let wrongProps: JSONValue = ["version": "v1", "spec": ["root": "t", "elements": ["t": ["type": "Text", "props": ["text": 1]]]]]
        #expect(!loaded.validate(wrongProps).success)
        #expect(loaded.spec(in: wrongProps) == nil)
        #expect(loaded.spec(in: ["version": "v2", "spec": valid["spec"]]) == nil)
    }

    @Test("builds a catalog of the element types")
    func buildsCatalog() throws {
        let catalog = try SpecJSONSchema(Self.spec).catalog()
        #expect(catalog.componentNames == ["Text", "Row", "Column"])
        #expect(catalog.validate(["root": "t", "elements": ["t": ["type": "Row", "props": [:], "children": []]]]).success)
        #expect(!catalog.validate(["root": "t", "elements": ["t": ["type": "Grid", "props": [:], "children": []]]]).success)
    }

    @Test("a schema without a spec is rejected")
    func rejectsSchemaWithoutSpec() {
        #expect(throws: SpecJSONSchemaError.noSpec) {
            try SpecJSONSchema(["type": "object", "properties": ["root": ["type": "string"]]])
        }
        #expect(throws: SpecJSONSchemaError.noElementTypes) {
            try SpecJSONSchema(["type": "object", "properties": ["root": ["type": "string"], "elements": ["type": "object"]]])
        }
    }
}

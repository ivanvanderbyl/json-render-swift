import Testing
@testable import JSONRender

/// Catalogs exported from TypeScript (see Conformance/src/export-catalog.mjs):
/// the Swift catalog built from the exported manifest must have the same
/// component and action names, and accept and reject the same specs with the
/// same data and issues as upstream catalog.validate().
@Suite("Conformance: catalogs")
struct CatalogConformanceTests {
    @Test(arguments: Golden.cases("catalog"))
    func matchesUpstream(_ golden: GoldenCase) throws {
        let schema: RendererSchema = switch golden.input["schema"].stringValue {
        case "react": .react
        case "react-native": .reactNative
        default: testSchema
        }
        let catalog = try Catalog(manifest: golden.output["manifest"], schema: schema)
        #expect(.array(JSONArray(catalog.componentNames.map(JSONValue.string))) == golden.output["componentNames"])
        #expect(.array(JSONArray(catalog.actionNames.map(JSONValue.string))) == golden.output["actionNames"])
        let specs = golden.input["specs"].arrayValue ?? []
        let results = golden.output["results"].arrayValue ?? []
        try #require(specs.count == results.count)
        for (index, (raw, expected)) in zip(specs, results).enumerated() {
            try withDivergence(golden, value: index) {
                let result = catalog.validate(Tagged.decode(raw))
                var actual: JSONObject = ["success": .bool(result.success)]
                if result.success {
                    actual["data"] = Tagged.encode(result.data)
                } else {
                    actual["issues"] = .array(JSONArray(result.issues.map { issue in
                        ["code": .string(issue.code), "path": .array(JSONArray(issue.path)), "message": .string(issue.message)]
                    }))
                }
                #expect(Tagged.matches(expected, .object(actual)), "spec \(index): upstream \(expected), Swift \(actual)")
            }
        }
    }
}

/// The test schema from upstream schema.test.ts, shared with the catalog suite.
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

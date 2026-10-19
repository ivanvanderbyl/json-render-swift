import Testing
@testable import JSONRender
@testable import JSONRenderStandard

/// The React Native standard catalog against upstream
/// (Conformance/corpus/standard-catalog.json).
@Suite("Conformance: standard catalog")
struct StandardCatalogConformanceTests {
    @Test(arguments: Golden.cases("standard-catalog"))
    func matchesUpstream(_ golden: GoldenCase) throws {
        let input = Tagged.decode(golden.input)
        let catalog = StandardCatalog.catalog
        let actual: JSONValue
        switch input["op"].stringValue {
        case "manifest":
            actual = [
                "manifest": try JSONValue(parsing: StandardCatalogManifest.json),
                "componentNames": .array(JSONArray(catalog.componentNames.map(JSONValue.string))),
                "actionNames": .array(JSONArray(catalog.actionNames.map(JSONValue.string))),
            ]
        case "props":
            let schema = try #require(catalog.components[input["component"].stringValue ?? ""]?.props)
            actual = verdict(schema.validate(input["value"]))
        case "params":
            let schema = try #require(catalog.actions[input["action"].stringValue ?? ""]?.params)
            actual = verdict(schema.validate(input["value"]))
        default:
            actual = verdict(catalog.validate(input["spec"]))
        }
        withDivergence(golden) {
            #expect(Tagged.matches(golden.output, actual), "upstream \(golden.output)\nSwift    \(actual)")
        }
    }

    private func verdict(_ result: SchemaResult) -> JSONValue {
        var output: JSONObject = ["success": .bool(result.success)]
        if result.success {
            output["data"] = Tagged.encode(result.data)
        } else {
            output["issues"] = .array(JSONArray(result.issues.map { issue in
                ["code": .string(issue.code), "path": .array(JSONArray(issue.path)), "message": .string(issue.message)]
            }))
        }
        return .object(output)
    }
}

import Testing
@testable import JSONRender

/// zod schemas exported with `z.toJSONSchema(schema, { io: "input" })`: the
/// Swift validator must import each exported schema and reach zod's verdict,
/// output data and issues (code, path and message) for every sample value.
@Suite("Conformance: zod schemas imported from JSON Schema")
struct SchemaConformanceTests {
    @Test(arguments: Golden.cases("schemas"))
    func matchesZod(_ golden: GoldenCase) throws {
        let schema = try JSONSchema(golden.output["jsonSchema"])
        let values = golden.input["values"].arrayValue ?? []
        let results = golden.output["results"].arrayValue ?? []
        try #require(values.count == results.count)
        for (index, (raw, expected)) in zip(values, results).enumerated() {
            let value = Tagged.decode(raw)
            try withDivergence(golden, value: index) {
                let result = schema.validate(value)
                var actual: JSONObject = ["success": .bool(result.success)]
                if result.success {
                    actual["data"] = Tagged.encode(result.data)
                } else {
                    actual["issues"] = .array(JSONArray(result.issues.map { issue in
                        ["code": .string(issue.code), "path": .array(JSONArray(issue.path)), "message": .string(issue.message)]
                    }))
                }
                #expect(Tagged.matches(expected, .object(actual)), "value \(value): zod \(expected), Swift \(actual)")
            }
        }
    }
}

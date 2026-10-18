import Testing
@testable import JSONRender

/// JavaScript conversions json-render depends on, checked against values the
/// Node engine produced (Conformance/corpus/js-semantics.json).
@Suite("Conformance: JavaScript semantics")
struct JavaScriptSemanticsTests {
    @Test(arguments: Golden.cases("js-semantics"))
    func matchesNode(_ golden: GoldenCase) throws {
        let input = Tagged.decode(golden.input["input"])
        let op = try #require(golden.input["op"].stringValue)
        let actual = Tagged.capture {
            switch op {
            case "numberToString", "toString":
                return .string(input.javaScriptString)
            case "stringToNumber":
                return .number(JavaScript.stringToNumber(input.stringValue ?? ""))
            case "stringify":
                return input.stringified().map(JSONValue.string) ?? .undefined
            case "parseStringify":
                let parsed = try JSONValue(parsing: input.stringValue ?? "")
                return [
                    "stringified": parsed.stringified().map(JSONValue.string) ?? .undefined,
                    "keys": parsed.objectValue.map { .array(JSONArray($0.keys.map(JSONValue.string))) }
                        ?? parsed.arrayValue.map { .array(JSONArray($0.indices.map { .string(String($0)) })) }
                        ?? .null,
                ]
            case "truthy":
                return .bool(input.isTruthy)
            case "trim":
                return .string(JavaScript.trim(input.stringValue ?? ""))
            case "length":
                return .number(Double(JavaScript.length(input.stringValue ?? "")))
            case "lessThan":
                return .bool(JavaScript.lessThan(input[0].stringValue ?? "", input[1].stringValue ?? ""))
            case "typeOf":
                return .string(input.typeOf)
            case "entries":
                return .array(JSONArray(try JavaScript.entries(input).map { [.string($0.key), $0.value] }))
            default:
                Issue.record("unknown op \(op)")
                return .undefined
            }
        }
        if golden.output["threw"].stringValue != nil {
            #expect(actual["threw"].stringValue != nil, "expected a throw, got \(actual)")
        } else {
            #expect(actual == golden.output)
        }
    }
}

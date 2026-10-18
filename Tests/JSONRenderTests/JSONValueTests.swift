import Testing
@testable import JSONRender

// JSONValue models a JavaScript value as json-render sees it. These tests cover
// behaviour the conformance goldens cannot express: reference identity for
// `===`, copy-on-write, and the parser the golden loader itself relies on.

@Suite("JSONValue")
struct JSONValueTests {
    @Test("parses nested JSON and orders keys the way JavaScript does")
    func parsesWithJavaScriptKeyOrder() throws {
        let value = try JSONValue(parsing: #"{"b":1,"2":[true,null,"x"],"a":{"c":-1.5e2}}"#)
        let object = try #require(value.objectValue)
        #expect(object.keys == ["2", "b", "a"])
        #expect(value["2"] == [true, nil, "x"])
        #expect(value["a"]["c"] == -150)
        #expect(value["missing"] == .undefined)
    }

    @Test("rejects malformed JSON")
    func rejectsMalformedJSON() {
        #expect(throws: JSONParseError.self) { try JSONValue(parsing: "[1,]") }
        #expect(throws: JSONParseError.self) { try JSONValue(parsing: "") }
    }

    @Test("stringifies like JSON.stringify")
    func stringifies() {
        let value: JSONValue = ["a": .undefined, "b": [1, .undefined, 2.5], "c": "q\"\n"]
        #expect(value.stringified() == #"{"b":[1,null,2.5],"c":"q\"\n"}"#)
        #expect(JSONValue.undefined.stringified() == nil)
    }

    @Test("strict equality compares objects and arrays by reference")
    func strictEqualityUsesIdentity() {
        let object: JSONValue = ["a": 1]
        let sameReference = object
        let lookalike: JSONValue = ["a": 1]
        #expect(object.strictEquals(sameReference))
        #expect(!object.strictEquals(lookalike))
        #expect(object == lookalike)
        #expect(JSONValue.number(.nan).strictEquals(.number(.nan)) == false)
        #expect(JSONValue.number(0).strictEquals(.number(-0.0)))
        #expect(JSONValue.string("e\u{301}").strictEquals("\u{e9}") == false)
    }

    @Test("mutating a shared object gives the copy a new identity")
    func copyOnWriteChangesIdentity() {
        let original: JSONValue = ["a": 1]
        var copy = original
        copy["b"] = 2
        #expect(!copy.strictEquals(original))
        #expect(original["b"] == .undefined)
        #expect(copy["b"] == 2)
    }

    @Test("object keys are distinct by UTF-16 code units, not canonical equivalence")
    func keysAreExactStrings() {
        var object = JSONObject()
        object["\u{e9}"] = 1
        object["e\u{301}"] = 2
        #expect(object.count == 2)
    }
}

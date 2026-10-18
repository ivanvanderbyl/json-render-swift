import Testing
@testable import JSONRender

// Ports upstream tests from packages/core/src/types.test.ts (json-render 0.21.1).
// Suite and test names match the upstream describe and it names.

@Suite("types.test.ts › findFormValue")
struct FindFormValueTests {
    static let dottedValues: [(String, String)] = [
        ("email", "john.doe@example.com"),
        ("url", "https://example.com"),
        ("version", "1.2.3"),
    ]

    @Test("keeps a direct %s literal", arguments: dottedValues)
    func keepsDirectLiteral(field: String, value: String) {
        #expect(FormValue.find(field, params: [field: .string(value)], state: [field: "state"]) == .string(value))
    }

    @Test("keeps a dotted-key %s literal", arguments: dottedValues)
    func keepsDottedKeyLiteral(field: String, value: String) {
        let found = FormValue.find(field, params: ["form.\(field)": .string(value)], state: ["form.\(field)": "state"])
        #expect(found == .string(value))
    }

    @Test("treats a raw dotted parameter value as literal, even with matching state")
    func rawDottedParameterIsLiteral() {
        #expect(FormValue.find("email", params: ["email": "form.email"]) == "form.email")
        #expect(FormValue.find("email", params: ["email": "form.email"], state: ["form.email": "state email"]) == "form.email")
    }

    @Test("prefers a direct parameter over dotted parameters and state")
    func prefersDirectParameter() {
        let found = FormValue.find(
            "email",
            params: ["email": "direct", "form.email": "dotted"],
            state: ["email": "state", "form.email": "dotted state"]
        )
        #expect(found == "direct")
    }

    @Test("prefers a dotted parameter over state and skips undefined direct params")
    func prefersDottedParameter() {
        let found = FormValue.find("email", params: ["email": .undefined, "form.email": "dotted"], state: ["form.email": "state"])
        #expect(found == "dotted")
    }

    @Test("keeps the first matching dotted parameter key, even if undefined")
    func keepsFirstDottedKey() {
        let found = FormValue.find("email", params: ["form.email": .undefined, "other.email": "later"], state: ["email": "state"])
        #expect(found == .undefined)
    }

    @Test("finds exact and dotted flat state keys")
    func findsFlatStateKeys() {
        #expect(FormValue.find("email", state: ["email": "exact"]) == "exact")
        #expect(FormValue.find("email", state: ["form.email": "dotted state"]) == "dotted state")
        #expect(FormValue.find("email", state: ["email": "first", "form.email": "second"]) == "first")
    }

    @Test("finds nested state with slash paths but not bare field names")
    func findsNestedSlashPaths() {
        let state: JSONObject = ["form": ["email": "nested@example.com"]]
        #expect(FormValue.find("/form/email", state: state) == "nested@example.com")
        #expect(FormValue.find("form/email", state: state) == "nested@example.com")
        #expect(FormValue.find("email", state: state) == .undefined)
    }

    @Test("ignores nonmatching keys and returns undefined for omitted inputs")
    func ignoresNonmatchingKeys() {
        #expect(FormValue.find("email", params: ["emailAddress": "other"], state: [:]) == .undefined)
        #expect(FormValue.find("email") == .undefined)
    }

    @Test("preserves a direct %s value", arguments: ["", 0, false, nil] as [JSONValue])
    func preservesDirectFalsyValue(value: JSONValue) {
        #expect(FormValue.find("email", params: ["email": value], state: ["email": "state"]) == value)
    }
}

@Suite("types.test.ts › getByPath")
struct GetByPathTests {
    @Test("gets nested values with JSON pointer paths")
    func getsNestedValues() {
        let data: JSONValue = ["user": ["name": "John", "scores": [10, 20, 30]]]
        #expect(data.value(atPath: "/user/name") == "John")
        #expect(data.value(atPath: "/user/scores/0") == 10)
        #expect(data.value(atPath: "/user/scores/1") == 20)
    }

    @Test("returns root object for empty or root path")
    func returnsRoot() {
        let data: JSONValue = ["value": 42]
        #expect(data.value(atPath: "/").strictEquals(data))
        #expect(data.value(atPath: "").strictEquals(data))
    }

    @Test("returns undefined for missing paths")
    func returnsUndefinedForMissing() {
        let data: JSONValue = ["user": ["name": "John"]]
        #expect(data.value(atPath: "/user/missing") == .undefined)
        #expect(data.value(atPath: "/nonexistent/path") == .undefined)
    }

    @Test("handles paths without leading slash")
    func handlesPathsWithoutLeadingSlash() {
        let data: JSONValue = ["user": ["name": "John"]]
        #expect(data.value(atPath: "user/name") == "John")
    }

    @Test("returns undefined when traversing through non-object")
    func returnsUndefinedThroughNonObject() {
        let data: JSONValue = ["value": "string"]
        #expect(data.value(atPath: "/value/nested") == .undefined)
    }

    @Test("handles null values in path")
    func handlesNullInPath() {
        let data: JSONValue = ["user": nil]
        #expect(data.value(atPath: "/user/name") == .undefined)
    }
}

@Suite("types.test.ts › resolveRepeatStatePath")
struct ResolveRepeatStatePathTests {
    @Test("preserves string paths exactly")
    func preservesStringPaths() throws {
        #expect(try RepeatScope.resolveStatePath("/items") == "/items")
        #expect(try RepeatScope.resolveStatePath("items") == "items")
    }

    @Test("resolves $item paths against the enclosing item path")
    func resolvesItemPaths() throws {
        #expect(try RepeatScope.resolveStatePath(["$item": "subitems"], base: "/groups/0") == "/groups/0/subitems")
        #expect(try RepeatScope.resolveStatePath(["$item": "/subitems"], base: "/groups/0") == "/groups/0/subitems")
    }

    @Test("resolves an empty $item path to the enclosing item")
    func resolvesEmptyItemPath() throws {
        #expect(try RepeatScope.resolveStatePath(["$item": ""], base: "/groups/0") == "/groups/0")
        #expect(try RepeatScope.resolveStatePath(["$item": "/"], base: "/groups/0") == "/groups/0")
    }

    @Test("does not resolve $item outside repeat scope")
    func doesNotResolveOutsideScope() throws {
        #expect(try RepeatScope.resolveStatePath(["$item": "items"]) == nil)
    }

    @Test("builds item paths without duplicate root separators")
    func buildsItemPaths() {
        #expect(RepeatScope.itemStatePath("/items", index: 2) == "/items/2")
        #expect(RepeatScope.itemStatePath("/", index: 2) == "/2")
        #expect(RepeatScope.itemStatePath("items", index: 2) == "items/2")
    }
}

@Suite("types.test.ts › setByPath")
struct SetByPathTests {
    @Test("sets value at existing path")
    func setsExistingPath() {
        var data: JSONValue = ["user": ["name": "John"]]
        data.setValue("Alice", atPath: "/user/name")
        #expect(data["user"]["name"] == "Alice")
    }

    @Test("creates intermediate objects for deep paths")
    func createsIntermediates() {
        var data: JSONValue = [:]
        data.setValue("deep", atPath: "/a/b/c")
        #expect(data["a"]["b"]["c"] == "deep")
    }

    @Test("handles paths without leading slash")
    func handlesPathsWithoutLeadingSlash() {
        var data: JSONValue = [:]
        data.setValue("John", atPath: "user/name")
        #expect(data["user"]["name"] == "John")
    }

    @Test("overwrites existing values")
    func overwrites() {
        var data: JSONValue = ["count": 5]
        data.setValue(10, atPath: "/count")
        #expect(data["count"] == 10)
    }

    @Test("handles array-like paths")
    func handlesArrayLikePaths() {
        var data: JSONValue = ["items": [:]]
        data.setValue("first", atPath: "/items/0")
        #expect(data["items"]["0"] == "first")
    }
}

@Suite("types.test.ts › resolveDynamicValue")
struct ResolveDynamicValueTests {
    @Test("resolves literal string values")
    func resolvesStrings() throws {
        #expect(try DynamicValue.resolve("hello", state: [:]) == "hello")
    }

    @Test("resolves literal number values")
    func resolvesNumbers() throws {
        #expect(try DynamicValue.resolve(42, state: [:]) == 42)
    }

    @Test("resolves literal boolean values")
    func resolvesBooleans() throws {
        #expect(try DynamicValue.resolve(true, state: [:]) == true)
        #expect(try DynamicValue.resolve(false, state: [:]) == false)
    }

    @Test("resolves $state references")
    func resolvesStateReferences() throws {
        #expect(try DynamicValue.resolve(["$state": "/user/name"], state: ["user": ["name": "Alice"]]) == "Alice")
    }

    @Test("returns undefined for missing $state references")
    func returnsUndefinedForMissingReference() throws {
        #expect(try DynamicValue.resolve(["$state": "/missing"], state: ["user": ["name": "Alice"]]) == .undefined)
    }

    @Test("returns undefined for null value")
    func returnsUndefinedForNull() throws {
        #expect(try DynamicValue.resolve(nil, state: [:]) == .undefined)
    }

    @Test("returns undefined for undefined value")
    func returnsUndefinedForUndefined() throws {
        #expect(try DynamicValue.resolve(.undefined, state: [:]) == .undefined)
    }
}

@Suite("types.test.ts › JSON Pointer escaping (RFC 6901)")
struct JSONPointerEscapingTests {
    @Test("getByPath unescapes ~1 to /")
    func getUnescapesSlash() {
        let data: JSONValue = ["a/b": ["c": 42]]
        #expect(data.value(atPath: "/a~1b/c") == 42)
    }

    @Test("getByPath unescapes ~0 to ~")
    func getUnescapesTilde() {
        let data: JSONValue = ["a~b": 99]
        #expect(data.value(atPath: "/a~0b") == 99)
    }

    @Test("getByPath handles combined ~0 and ~1 escaping")
    func getHandlesCombinedEscapes() {
        let data: JSONValue = ["a~/b": "found"]
        #expect(data.value(atPath: "/a~0~1b") == "found")
    }

    @Test("setByPath unescapes ~1 to / in keys")
    func setUnescapesSlash() {
        var data: JSONValue = [:]
        data.setValue("value", atPath: "/a~1b")
        #expect(data["a/b"] == "value")
    }

    @Test("setByPath unescapes ~0 to ~ in keys")
    func setUnescapesTilde() {
        var data: JSONValue = [:]
        data.setValue("value", atPath: "/a~0b")
        #expect(data["a~b"] == "value")
    }

    @Test("getByPath reads array elements properly")
    func getReadsArrayElements() {
        let data: JSONValue = ["items": [10, 20, 30]]
        #expect(data.value(atPath: "/items/0") == 10)
        #expect(data.value(atPath: "/items/2") == 30)
    }
}

@Suite("types.test.ts › addByPath")
struct AddByPathTests {
    @Test("adds a property to an object")
    func addsProperty() {
        var data: JSONValue = ["a": 1]
        data.addValue(2, atPath: "/b")
        #expect(data["b"] == 2)
    }

    @Test("replaces an existing object property (add semantics)")
    func replacesExistingProperty() {
        var data: JSONValue = ["a": 1]
        data.addValue(99, atPath: "/a")
        #expect(data["a"] == 99)
    }

    @Test("inserts into an array at a specific index")
    func insertsIntoArray() {
        var data: JSONValue = ["arr": [1, 2, 3]]
        data.addValue(99, atPath: "/arr/1")
        #expect(data["arr"] == [1, 99, 2, 3])
    }

    @Test("appends to an array with - (end-of-array)")
    func appendsWithDash() {
        var data: JSONValue = ["arr": [1, 2]]
        data.addValue(3, atPath: "/arr/-")
        #expect(data["arr"] == [1, 2, 3])
    }

    @Test("inserts at index 0 of an array")
    func insertsAtZero() {
        var data: JSONValue = ["arr": ["b", "c"]]
        data.addValue("a", atPath: "/arr/0")
        #expect(data["arr"] == ["a", "b", "c"])
    }

    @Test("creates intermediate objects")
    func createsIntermediates() {
        var data: JSONValue = [:]
        data.addValue("deep", atPath: "/x/y/z")
        #expect(data["x"]["y"]["z"] == "deep")
    }
}

@Suite("types.test.ts › removeByPath")
struct RemoveByPathTests {
    @Test("deletes an object property")
    func deletesProperty() {
        var data: JSONValue = ["a": 1, "b": 2]
        data.removeValue(atPath: "/a")
        #expect(data == ["b": 2])
        #expect(data.objectValue?.hasKey("a") == false)
    }

    @Test("removes an element from an array by index")
    func removesArrayElement() {
        var data: JSONValue = ["arr": [1, 2, 3]]
        data.removeValue(atPath: "/arr/1")
        #expect(data["arr"] == [1, 3])
    }

    @Test("removes nested properties")
    func removesNested() {
        var data: JSONValue = ["user": ["name": "John", "age": 30]]
        data.removeValue(atPath: "/user/age")
        #expect(data["user"] == ["name": "John"])
    }

    @Test("is a no-op for non-existent paths")
    func noOpForMissing() {
        var data: JSONValue = ["a": 1]
        data.removeValue(atPath: "/b/c/d")
        #expect(data == ["a": 1])
    }
}

@Suite("types.test.ts › applySpecStreamPatch")
struct ApplySpecStreamPatchTests {
    private func apply(_ patch: JSONValue, to object: JSONValue) throws -> JSONValue {
        var object = object
        try SpecStream.apply(JSONPatch(patch.objectValue!), to: &object)
        return object
    }

    @Test("add operation › adds a new object property")
    func addsProperty() throws {
        let object = try apply(["op": "add", "path": "/name", "value": "Alice"], to: [:])
        #expect(object["name"] == "Alice")
    }

    @Test("add operation › adds nested properties creating intermediates")
    func addsNested() throws {
        let object = try apply(["op": "add", "path": "/user/name", "value": "Bob"], to: [:])
        #expect(object["user"]["name"] == "Bob")
    }

    @Test("add operation › inserts into array at index")
    func insertsAtIndex() throws {
        let object = try apply(["op": "add", "path": "/items/1", "value": 2], to: ["items": [1, 3]])
        #expect(object["items"] == [1, 2, 3])
    }

    @Test("add operation › appends to array with -")
    func appendsWithDash() throws {
        let object = try apply(["op": "add", "path": "/items/-", "value": 3], to: ["items": [1, 2]])
        #expect(object["items"] == [1, 2, 3])
    }

    @Test("remove operation › removes an object property")
    func removesProperty() throws {
        let object = try apply(["op": "remove", "path": "/age"], to: ["name": "Alice", "age": 30])
        #expect(object == ["name": "Alice"])
        #expect(object.objectValue?.hasKey("age") == false)
    }

    @Test("remove operation › removes from array by index")
    func removesFromArray() throws {
        let object = try apply(["op": "remove", "path": "/items/1"], to: ["items": ["a", "b", "c"]])
        #expect(object["items"] == ["a", "c"])
    }

    @Test("replace operation › replaces an existing value")
    func replacesValue() throws {
        let object = try apply(["op": "replace", "path": "/name", "value": "Bob"], to: ["name": "Alice"])
        #expect(object["name"] == "Bob")
    }

    @Test("replace operation › replaces nested values")
    func replacesNested() throws {
        let object = try apply(["op": "replace", "path": "/user/name", "value": "Bob"], to: ["user": ["name": "Alice"]])
        #expect(object["user"]["name"] == "Bob")
    }

    @Test("move operation › moves a value from one path to another")
    func movesValue() throws {
        let object = try apply(["op": "move", "path": "/c", "from": "/a"], to: ["a": 1, "b": 2])
        #expect(object == ["b": 2, "c": 1])
        #expect(object.objectValue?.hasKey("a") == false)
    }

    @Test("move operation › moves nested values")
    func movesNested() throws {
        let object = try apply(
            ["op": "move", "path": "/target/val", "from": "/source/val"],
            to: ["source": ["val": 42], "target": [:]]
        )
        #expect(object["target"]["val"] == 42)
        #expect(object["source"].objectValue?.hasKey("val") == false)
    }

    @Test("move operation › is a no-op if from is missing")
    func moveNoOpWithoutFrom() throws {
        let object = try apply(["op": "move", "path": "/b"], to: ["a": 1])
        #expect(object == ["a": 1])
    }

    @Test("copy operation › copies a value from one path to another")
    func copiesValue() throws {
        let object = try apply(["op": "copy", "path": "/b", "from": "/a"], to: ["a": 1])
        #expect(object == ["a": 1, "b": 1])
    }

    @Test("copy operation › copies complex values")
    func copiesComplexValues() throws {
        let object = try apply(
            ["op": "copy", "path": "/dest", "from": "/source/nested"],
            to: ["source": ["nested": ["value": 42]]]
        )
        #expect(object["dest"] == ["value": 42])
        #expect(object["source"]["nested"] == ["value": 42])
    }

    @Test("copy operation › is a no-op if from is missing")
    func copyNoOpWithoutFrom() throws {
        let object = try apply(["op": "copy", "path": "/b"], to: ["a": 1])
        #expect(object == ["a": 1])
    }

    @Test("test operation › succeeds when values match")
    func testSucceedsForMatch() {
        #expect(throws: Never.self) { try apply(["op": "test", "path": "/name", "value": "Alice"], to: ["name": "Alice"]) }
    }

    @Test("test operation › succeeds for matching objects")
    func testSucceedsForObjects() {
        #expect(throws: Never.self) {
            try apply(["op": "test", "path": "/user", "value": ["name": "Alice", "age": 30]], to: ["user": ["name": "Alice", "age": 30]])
        }
    }

    @Test("test operation › succeeds for matching arrays")
    func testSucceedsForArrays() {
        #expect(throws: Never.self) { try apply(["op": "test", "path": "/items", "value": [1, 2, 3]], to: ["items": [1, 2, 3]]) }
    }

    @Test("test operation › throws when values do not match")
    func testThrowsForMismatch() {
        #expect(throws: JavaScriptError.error(#"Test operation failed: value at "/name" does not match"#)) {
            try apply(["op": "test", "path": "/name", "value": "Bob"], to: ["name": "Alice"])
        }
    }

    @Test("test operation › throws when path does not exist")
    func testThrowsForMissingPath() {
        #expect(throws: JavaScriptError.self) { try apply(["op": "test", "path": "/missing", "value": "anything"], to: [:]) }
    }
}

@Suite("types.test.ts › compileSpecStream")
struct CompileSpecStreamTests {
    @Test("compiles a series of add patches")
    func compilesAdds() throws {
        let stream = """
        {"op":"add","path":"/name","value":"Alice"}
        {"op":"add","path":"/age","value":30}
        """
        #expect(try SpecStream.compile(stream) == ["name": "Alice", "age": 30])
    }

    @Test("handles remove operations")
    func handlesRemove() throws {
        let stream = """
        {"op":"add","path":"/a","value":1}
        {"op":"add","path":"/b","value":2}
        {"op":"remove","path":"/a"}
        """
        let result = try SpecStream.compile(stream)
        #expect(result == ["b": 2])
        #expect(!result.hasKey("a"))
    }

    @Test("handles replace operations")
    func handlesReplace() throws {
        let stream = """
        {"op":"add","path":"/name","value":"Alice"}
        {"op":"replace","path":"/name","value":"Bob"}
        """
        #expect(try SpecStream.compile(stream) == ["name": "Bob"])
    }

    @Test("handles move operations")
    func handlesMove() throws {
        let stream = """
        {"op":"add","path":"/old","value":"data"}
        {"op":"move","path":"/new","from":"/old"}
        """
        #expect(try SpecStream.compile(stream) == ["new": "data"])
    }

    @Test("handles copy operations")
    func handlesCopy() throws {
        let stream = """
        {"op":"add","path":"/original","value":"data"}
        {"op":"copy","path":"/duplicate","from":"/original"}
        """
        #expect(try SpecStream.compile(stream) == ["original": "data", "duplicate": "data"])
    }

    @Test("skips empty lines")
    func skipsEmptyLines() throws {
        let stream = """
        {"op":"add","path":"/a","value":1}

        {"op":"add","path":"/b","value":2}
        """
        #expect(try SpecStream.compile(stream) == ["a": 1, "b": 2])
    }

    @Test("uses initial value")
    func usesInitialValue() throws {
        #expect(try SpecStream.compile(#"{"op":"add","path":"/b","value":2}"#, initial: ["a": 1]) == ["a": 1, "b": 2])
    }
}

@Suite("types.test.ts › createSpecStreamCompiler")
struct SpecStreamCompilerTests {
    @Test("processes chunks incrementally")
    func processesChunks() throws {
        let compiler = SpecStreamCompiler()
        let (result, newPatches) = try compiler.push(#"{"op":"add","path":"/name","value":"Alice"}"# + "\n")
        #expect(newPatches.count == 1)
        #expect(result == ["name": "Alice"])
    }

    @Test("handles partial lines across chunks")
    func handlesPartialLines() throws {
        let compiler = SpecStreamCompiler()
        let first = try compiler.push(#"{"op":"add","path":"/na"#)
        #expect(first.newPatches.isEmpty)
        let second = try compiler.push(#"me","value":"Alice"}"# + "\n")
        #expect(second.newPatches.count == 1)
        #expect(second.result == ["name": "Alice"])
    }

    @Test("processes remaining buffer on getResult")
    func processesRemainingBuffer() throws {
        let compiler = SpecStreamCompiler()
        try compiler.push(#"{"op":"add","path":"/name","value":"Alice"}"#)
        #expect(try compiler.result() == ["name": "Alice"])
    }

    @Test("resets to clean state")
    func resets() throws {
        let compiler = SpecStreamCompiler()
        try compiler.push(#"{"op":"add","path":"/name","value":"Alice"}"# + "\n")
        compiler.reset()
        #expect(try compiler.result() == [:])
    }

    @Test("tracks all applied patches")
    func tracksPatches() throws {
        let compiler = SpecStreamCompiler()
        try compiler.push(#"{"op":"add","path":"/a","value":1}"# + "\n")
        try compiler.push(#"{"op":"add","path":"/b","value":2}"# + "\n")
        let patches = compiler.patches
        #expect(patches.count == 2)
        #expect(patches[0].op == "add")
        #expect(patches[1].op == "add")
    }

    @Test("handles all RFC 6902 operations")
    func handlesAllOperations() throws {
        let compiler = SpecStreamCompiler()
        try compiler.push(#"{"op":"add","path":"/x","value":1}"# + "\n")
        try compiler.push(#"{"op":"add","path":"/y","value":2}"# + "\n")
        try compiler.push(#"{"op":"move","path":"/z","from":"/x"}"# + "\n")
        try compiler.push(#"{"op":"copy","path":"/w","from":"/y"}"# + "\n")
        try compiler.push(#"{"op":"remove","path":"/y"}"# + "\n")
        #expect(try compiler.result() == ["z": 1, "w": 2])
    }
}

@Suite("types.test.ts › applySpecPatch")
struct ApplySpecPatchTests {
    @Test("sets the root element")
    func setsRoot() throws {
        var spec = Spec(root: "", elements: [:])
        try spec.apply(JSONPatch(op: "add", path: "/root", value: "main"))
        #expect(spec.root == "main")
    }

    @Test("adds an element to the elements map")
    func addsElement() throws {
        var spec = Spec(root: "main", elements: [:])
        try spec.apply(JSONPatch(op: "add", path: "/elements/main", value: ["type": "Card", "props": ["title": "Hello"], "children": []]))
        #expect(spec.elements["main"] == ["type": "Card", "props": ["title": "Hello"], "children": []])
    }

    @Test("replaces an existing element")
    func replacesElementProp() throws {
        var spec = Spec(root: "main", elements: ["main": ["type": "Card", "props": ["title": "Old"], "children": []]])
        try spec.apply(JSONPatch(op: "replace", path: "/elements/main/props/title", value: "New"))
        #expect(spec.elements["main"]?["props"]["title"] == "New")
    }

    @Test("removes an element")
    func removesElement() throws {
        var spec = Spec(root: "main", elements: [
            "main": ["type": "Card", "props": [:], "children": []],
            "child": ["type": "Text", "props": [:], "children": []],
        ])
        try spec.apply(JSONPatch(op: "remove", path: "/elements/child"))
        #expect(spec.elements["child"] == nil)
        #expect(spec.elements["main"] != nil)
    }

    @Test("adds state data")
    func addsState() throws {
        var spec = Spec(root: "main", elements: [:])
        try spec.apply(JSONPatch(op: "add", path: "/state", value: ["count": 0]))
        #expect(spec.state == ["count": 0])
    }

    // "returns the mutated spec" is not applicable: Spec.apply is a mutating
    // method on a value type, so there is no returned reference to compare.
}

@Suite("types.test.ts › createMixedStreamParser")
struct MixedStreamParserTests {
    final class Recorder {
        var patches: [JSONPatch] = []
        var texts: [String] = []
        lazy var parser = MixedStreamParser(
            onPatch: { [unowned self] in self.patches.append($0) },
            onText: { [unowned self] in self.texts.append($0) }
        )
    }

    @Test("classifies JSONL lines as patches")
    func classifiesPatches() {
        let recorder = Recorder()
        recorder.parser.push(#"{"op":"add","path":"/root","value":"main"}"# + "\n")
        #expect(recorder.patches.count == 1)
        #expect(recorder.patches.first?.op == "add")
        #expect(recorder.patches.first?.path == "/root")
        #expect(recorder.texts.isEmpty)
    }

    @Test("classifies non-JSONL lines as text")
    func classifiesText() {
        let recorder = Recorder()
        recorder.parser.push("Hello, here is your UI:\n")
        #expect(recorder.texts == ["Hello, here is your UI:"])
        #expect(recorder.patches.isEmpty)
    }

    @Test("handles mixed text and JSONL")
    func handlesMixed() {
        let recorder = Recorder()
        recorder.parser.push("Here is the dashboard:\n" + #"{"op":"add","path":"/root","value":"dash"}"# + "\n")
        #expect(recorder.texts == ["Here is the dashboard:"])
        #expect(recorder.patches.count == 1)
        #expect(recorder.patches.first?.path == "/root")
    }

    @Test("buffers partial lines across chunks")
    func buffersPartialLines() {
        let recorder = Recorder()
        recorder.parser.push(#"{"op":"add","path":"/ro"#)
        #expect(recorder.patches.isEmpty)
        recorder.parser.push(#"ot","value":"main"}"# + "\n")
        #expect(recorder.patches.count == 1)
        #expect(recorder.patches.first?.path == "/root")
    }

    @Test("flushes remaining buffer on flush()")
    func flushesPatchBuffer() {
        let recorder = Recorder()
        recorder.parser.push(#"{"op":"add","path":"/root","value":"main"}"#)
        #expect(recorder.patches.isEmpty)
        recorder.parser.flush()
        #expect(recorder.patches.count == 1)
    }

    @Test("flushes text buffer on flush()")
    func flushesTextBuffer() {
        let recorder = Recorder()
        recorder.parser.push("Some trailing text")
        #expect(recorder.texts.isEmpty)
        recorder.parser.flush()
        #expect(recorder.texts == ["Some trailing text"])
    }

    @Test("skips empty lines")
    func skipsEmptyLines() {
        let recorder = Recorder()
        recorder.parser.push("\n\n\n")
        #expect(recorder.patches.isEmpty)
        #expect(recorder.texts.isEmpty)
    }

    @Test("fence mode › parses patches inside ```spec fence")
    func parsesFencedPatches() {
        let recorder = Recorder()
        recorder.parser.push("Hello\n")
        recorder.parser.push("```spec\n")
        recorder.parser.push(#"{"op":"add","path":"/root","value":"main"}"# + "\n")
        recorder.parser.push("```\n")
        recorder.parser.push("Goodbye\n")
        recorder.parser.flush()
        #expect(recorder.patches.count == 1)
        #expect(recorder.patches.first?.op == "add")
        #expect(recorder.texts.contains("Hello"))
        #expect(recorder.texts.contains("Goodbye"))
    }

    @Test("fence mode › fence delimiters are not emitted as text or patches")
    func fenceDelimitersAreSwallowed() {
        let recorder = Recorder()
        recorder.parser.push("```spec\n")
        recorder.parser.push(#"{"op":"add","path":"/root","value":"r"}"# + "\n")
        recorder.parser.push("```\n")
        recorder.parser.flush()
        #expect(recorder.patches.count == 1)
        #expect(recorder.texts.isEmpty)
    }
}

@Suite("types.test.ts › nestedToFlat")
struct NestedToFlatTests {
    @Test("converts a single node with no children")
    func convertsSingleNode() {
        let spec = Spec(nested: ["type": "Text", "props": ["content": "Hello"]])
        #expect(spec.root == "el-0")
        #expect(spec.elements["el-0"] == ["type": "Text", "props": ["content": "Hello"], "children": []])
    }

    @Test("converts a tree with children")
    func convertsTree() {
        let spec = Spec(nested: [
            "type": "Card",
            "props": ["title": "Hello"],
            "children": [
                ["type": "Text", "props": ["content": "World"], "children": []],
                ["type": "Button", "props": ["label": "Click"]],
            ],
        ])
        #expect(spec.root == "el-0")
        #expect(spec.elements.count == 3)
        #expect(spec.elements["el-0"]?["type"] == "Card")
        #expect(spec.elements["el-0"]?["children"] == ["el-1", "el-2"])
        #expect(spec.elements["el-1"]?["type"] == "Text")
        #expect(spec.elements["el-1"]?["children"] == [])
        #expect(spec.elements["el-2"]?["type"] == "Button")
        #expect(spec.elements["el-2"]?["children"] == [])
    }

    @Test("converts nested named slots to flat element references")
    func convertsSlots() {
        let spec = Spec(nested: [
            "type": "Layout",
            "props": [:],
            "children": [["type": "Text", "props": ["content": "Main"]]],
            "slots": [
                "header": [["type": "Heading", "props": ["text": "Header"]]],
                "footer": [["type": "Button", "props": ["label": "Continue"]]],
            ],
        ])
        #expect(spec.elements.count == 4)
        #expect(spec.elements["el-0"]?["children"] == ["el-1"])
        #expect(spec.elements["el-0"]?["slots"] == ["header": ["el-2"], "footer": ["el-3"]])
        #expect(spec.elements["el-2"]?["type"] == "Heading")
        #expect(spec.elements["el-3"]?["type"] == "Button")
    }

    @Test("hoists state from root node")
    func hoistsRootState() {
        let spec = Spec(nested: ["type": "Card", "props": ["title": "Hello"], "children": [], "state": ["count": 0, "items": []]])
        #expect(spec.state == ["count": 0, "items": []])
        #expect(spec.elements["el-0"]?["state"] == .undefined)
    }

    @Test("preserves extra fields like visible and on")
    func preservesExtraFields() {
        let spec = Spec(nested: [
            "type": "Panel",
            "props": [:],
            "visible": ["$state": "/showPanel"],
            "on": ["press": ["action": "setState", "params": ["statePath": "/x", "value": 1]]],
            "children": [],
        ])
        #expect(spec.elements["el-0"]?["visible"] == ["$state": "/showPanel"])
        #expect(spec.elements["el-0"]?["on"] == ["press": ["action": "setState", "params": ["statePath": "/x", "value": 1]]])
    }

    @Test("handles deeply nested trees")
    func handlesDeepTrees() {
        let spec = Spec(nested: [
            "type": "A", "props": [:],
            "children": [["type": "B", "props": [:], "children": [["type": "C", "props": [:], "children": [["type": "D", "props": [:]]]]]]],
        ])
        #expect(spec.elements.count == 4)
        #expect(spec.elements["el-0"]?["children"] == ["el-1"])
        #expect(spec.elements["el-1"]?["children"] == ["el-2"])
        #expect(spec.elements["el-2"]?["children"] == ["el-3"])
        #expect(spec.elements["el-3"]?["children"] == [])
    }

    @Test("returns empty elements for empty children array")
    func handlesEmptyChildren() {
        let spec = Spec(nested: ["type": "Empty", "props": [:], "children": []])
        #expect(spec.elements.count == 1)
        #expect(spec.elements["el-0"]?["children"] == [])
    }

    @Test("does not hoist state from non-root nodes")
    func doesNotHoistChildState() {
        let spec = Spec(nested: ["type": "Root", "props": [:], "children": [["type": "Child", "props": [:], "state": ["shouldNotHoist": true]]]])
        #expect(spec.state == .undefined)
        #expect(spec.elements["el-1"]?["state"] == .undefined)
    }
}

@Suite("types.test.ts › createJsonRenderTransform")
struct JSONRenderTransformTests {
    /// Pushes one text block through the transform and collects the output.
    private func transformText(_ text: String) -> [JSONObject] {
        let transform = JSONRenderTransform()
        var chunks: [JSONObject] = []
        chunks += transform.transform(["type": "text-start", "id": "t1"])
        chunks += transform.transform(["type": "text-delta", "id": "t1", "delta": .string(text)])
        chunks += transform.transform(["type": "text-end", "id": "t1"])
        chunks += transform.finish()
        return chunks
    }

    private func text(_ chunks: [JSONObject]) -> String {
        chunks.filter { $0["type"] == "text-delta" }.compactMap { $0["delta"]?.stringValue }.joined()
    }

    private func specChunks(_ chunks: [JSONObject]) -> [JSONObject] {
        chunks.filter { $0["type"] == .string(SpecDataPart.type) }
    }

    @Test("passes prose text through as text-delta")
    func passesProse() {
        #expect(text(transformText("Hello world\n")).contains("Hello world"))
    }

    @Test("classifies valid JSONL patches as data-spec (heuristic mode)")
    func classifiesPatches() {
        let spec = specChunks(transformText(#"{"op":"add","path":"/root","value":"main"}"# + "\n"))
        #expect(spec.count == 1)
        #expect(spec.first?["data"]?["type"] == "patch")
    }

    @Test("lines starting with { that are NOT patches are flushed as text")
    func flushesNonPatchBracesAsText() {
        let chunks = transformText(#"{"not":"a patch"}"# + "\n")
        #expect(specChunks(chunks).isEmpty)
        #expect(text(chunks).contains(#"{"not":"a patch"}"#))
    }

    @Test("parses content inside ```spec fence as patches")
    func parsesFence() {
        let input = [
            "Here is some UI:\n",
            "```spec\n",
            #"{"op":"add","path":"/root","value":"main"}"# + "\n",
            #"{"op":"add","path":"/elements/main","value":{"type":"Card","props":{},"children":[]}}"# + "\n",
            "```\n",
            "Done!\n",
        ].joined()
        let chunks = transformText(input)
        #expect(specChunks(chunks).count == 2)
        #expect(text(chunks).contains("Here is some UI:"))
        #expect(text(chunks).contains("Done!"))
        #expect(!text(chunks).contains("```spec"))
    }

    @Test("handles mixed text + heuristic patches in single stream")
    func handlesMixed() {
        let chunks = transformText("Some text\n" + #"{"op":"add","path":"/root","value":"r"}"# + "\nMore text\n")
        #expect(specChunks(chunks).count == 1)
        #expect(text(chunks).contains("Some text"))
        #expect(text(chunks).contains("More text"))
    }

    @Test("non-text chunks pass through unchanged")
    func passesOtherChunks() {
        let transform = JSONRenderTransform()
        let toolChunk: JSONObject = ["type": "tool-call", "toolCallId": "abc", "toolName": "test"]
        #expect(transform.transform(toolChunk) == [toolChunk])
    }

    @Test("flush behavior at end of stream")
    func flushesAtEnd() {
        let chunks = transformText(#"{"op":"add","path":"/root","value":"main"}"#)
        #expect(specChunks(chunks).count == 1)
    }

    @Test("splits text blocks around spec data (text-start/text-end pairs)")
    func splitsTextBlocks() throws {
        let chunks = transformText("Some text\n" + #"{"op":"add","path":"/root","value":"r"}"# + "\nMore text\n")
        #expect(chunks.filter { $0["type"] == "text-start" }.count == 2)
        #expect(chunks.filter { $0["type"] == "text-end" }.count == 2)
        #expect(specChunks(chunks).count == 1)
        let firstTextEnd = try #require(chunks.firstIndex { $0["type"] == "text-end" })
        let spec = try #require(chunks.firstIndex { $0["type"] == .string(SpecDataPart.type) })
        let secondTextStart = try #require(chunks.indices.first { $0 > spec && chunks[$0]["type"] == "text-start" })
        #expect(firstTextEnd < spec)
        #expect(spec < secondTextStart)
    }

    @Test("flush closes an open text block when stream ends without text-end")
    func flushClosesOpenBlock() {
        let transform = JSONRenderTransform()
        var chunks = transform.transform(["type": "text-start", "id": "t1"])
        chunks += transform.transform(["type": "text-delta", "id": "t1", "delta": "Hello world\n"])
        chunks += transform.finish()
        #expect(chunks.filter { $0["type"] == "text-end" }.count == 1)
        #expect(text(chunks).contains("Hello world"))
    }

    @Test("consecutive patches do not produce empty text blocks")
    func consecutivePatchesProduceNoEmptyBlocks() {
        let input = #"{"op":"add","path":"/root","value":"r"}"# + "\n"
            + #"{"op":"add","path":"/elements/r","value":{"type":"Card","props":{},"children":[]}}"# + "\n"
        let chunks = transformText(input)
        #expect(specChunks(chunks).count == 2)
        #expect(JavaScript.trim(text(chunks)) == "")
        #expect(chunks.filter { $0["type"] == "text-start" }.count <= 1)
        #expect(chunks.filter { $0["type"] == "text-end" }.count <= 1)
    }
}

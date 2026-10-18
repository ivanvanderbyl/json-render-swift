import Testing
@testable import JSONRender

// Ports upstream tests from packages/react/src/hooks.test.ts (json-render 0.21.1).

@Suite("hooks.test.ts › flatToTree")
struct FlatToTreeTests {
    @Test("converts array of elements to tree structure")
    func convertsElements() {
        let tree = Spec(flatElements: [
            ["key": "container", "type": "stack", "props": [:], "parentKey": nil],
            ["key": "text1", "type": "text", "props": ["content": "Hello"], "parentKey": "container"],
            ["key": "text2", "type": "text", "props": ["content": "World"], "parentKey": "container"],
        ])
        #expect(tree.root == "container")
        #expect(tree.elements.count == 3)
        #expect(tree.elements["container"] != nil)
        #expect(tree.elements["text1"] != nil)
        #expect(tree.elements["text2"] != nil)
    }

    @Test("builds parent-child relationships")
    func buildsRelationships() {
        let tree = Spec(flatElements: [
            ["key": "root", "type": "stack", "props": [:], "parentKey": nil],
            ["key": "child1", "type": "text", "props": [:], "parentKey": "root"],
            ["key": "child2", "type": "text", "props": [:], "parentKey": "root"],
        ])
        let children = tree.elements["root"]?["children"].arrayValue ?? []
        #expect(children.count == 2)
        #expect(children.contains("child1"))
        #expect(children.contains("child2"))
    }

    @Test("handles single root element")
    func handlesSingleRoot() {
        let tree = Spec(flatElements: [["key": "only", "type": "text", "props": ["content": "Single"], "parentKey": nil]])
        #expect(tree.root == "only")
        #expect(tree.elements.count == 1)
    }

    @Test("handles deeply nested elements")
    func handlesDeepNesting() {
        let tree = Spec(flatElements: [
            ["key": "level0", "type": "stack", "props": [:], "parentKey": nil],
            ["key": "level1", "type": "stack", "props": [:], "parentKey": "level0"],
            ["key": "level2", "type": "stack", "props": [:], "parentKey": "level1"],
            ["key": "level3", "type": "text", "props": [:], "parentKey": "level2"],
        ])
        #expect(tree.root == "level0")
        #expect(tree.elements["level0"]?["children"].arrayValue?.contains("level1") == true)
        #expect(tree.elements["level1"]?["children"].arrayValue?.contains("level2") == true)
        #expect(tree.elements["level2"]?["children"].arrayValue?.contains("level3") == true)
    }

    @Test("preserves element props")
    func preservesProps() {
        let tree = Spec(flatElements: [["key": "btn", "type": "button", "props": ["label": "Click me", "variant": "primary"], "parentKey": nil]])
        #expect(tree.elements["btn"]?["props"] == ["label": "Click me", "variant": "primary"])
    }

    @Test("preserves visibility conditions")
    func preservesVisibility() {
        let tree = Spec(flatElements: [["key": "conditional", "type": "text", "props": [:], "parentKey": nil, "visible": ["$state": "/isVisible"]]])
        #expect(tree.elements["conditional"]?["visible"] == ["$state": "/isVisible"])
    }

    @Test("handles elements with undefined parentKey as root")
    func handlesMissingParentKey() {
        let tree = Spec(flatElements: [["key": "root", "type": "stack", "props": [:]]])
        #expect(tree.elements["root"] != nil)
    }

    @Test("handles empty elements array")
    func handlesEmpty() {
        let tree = Spec(flatElements: [])
        #expect(tree.root == "")
        #expect(tree.elements.isEmpty)
    }

    @Test("handles multiple children correctly")
    func handlesMultipleChildren() {
        let tree = Spec(flatElements: [
            ["key": "parent", "type": "grid", "props": [:], "parentKey": nil],
            ["key": "a", "type": "card", "props": [:], "parentKey": "parent"],
            ["key": "b", "type": "card", "props": [:], "parentKey": "parent"],
            ["key": "c", "type": "card", "props": [:], "parentKey": "parent"],
            ["key": "d", "type": "card", "props": [:], "parentKey": "parent"],
        ])
        #expect(tree.elements["parent"]?["children"] == ["a", "b", "c", "d"])
    }
}

private func patchPart(_ patch: JSONValue) -> JSONObject {
    ["type": "data-spec", "data": ["type": "patch", "patch": patch]]
}

@Suite("hooks.test.ts › buildSpecFromParts")
struct BuildSpecFromPartsTests {
    @Test("returns null when no data-spec parts are present")
    func returnsNilWithoutSpecParts() throws {
        #expect(try MessageParts.spec(from: [["type": "text", "text": "Hello there"], ["type": "text", "text": "How can I help?"]]) == nil)
    }

    @Test("builds a spec from patch parts")
    func buildsFromPatches() throws {
        let spec = try #require(try MessageParts.spec(from: [
            patchPart(["op": "add", "path": "/root", "value": "main"]),
            patchPart(["op": "add", "path": "/elements/main", "value": ["type": "Card", "props": ["title": "Hello"], "children": []]]),
        ]))
        #expect(spec.root == "main")
        #expect(spec.elements["main"] == ["type": "Card", "props": ["title": "Hello"], "children": []])
    }

    @Test("handles flat spec parts")
    func handlesFlatParts() throws {
        let spec = try #require(try MessageParts.spec(from: [
            ["type": "data-spec", "data": ["type": "flat", "spec": ["root": "card-1", "elements": ["card-1": ["type": "Card", "props": [:], "children": []]]]]],
        ]))
        #expect(spec.root == "card-1")
        #expect(spec.elements["card-1"] != nil)
    }

    @Test("ignores non-spec parts")
    func ignoresOtherParts() throws {
        let spec = try #require(try MessageParts.spec(from: [
            ["type": "text", "text": "Some text"],
            patchPart(["op": "add", "path": "/root", "value": "main"]),
            ["type": "tool-invocation", "data": ["toolName": "search"]],
        ]))
        #expect(spec.root == "main")
    }

    @Test("applies patches incrementally")
    func appliesIncrementally() throws {
        let spec = try #require(try MessageParts.spec(from: [
            patchPart(["op": "add", "path": "/root", "value": "main"]),
            patchPart(["op": "add", "path": "/elements/main", "value": ["type": "Stack", "props": [:], "children": ["child"]]]),
            patchPart(["op": "add", "path": "/elements/child", "value": ["type": "Text", "props": ["content": "Hi"], "children": []]]),
        ]))
        #expect(spec.elements.count == 2)
        #expect(spec.elements["child"]?["props"]["content"] == "Hi")
    }

    @Test("handles nested spec parts via nestedToFlat")
    func handlesNestedParts() throws {
        let spec = try #require(try MessageParts.spec(from: [
            ["type": "data-spec", "data": ["type": "nested", "spec": [
                "type": "Card", "props": ["title": "Nested"],
                "children": [["type": "Text", "props": ["content": "Child"], "children": []]],
            ]]],
        ]))
        #expect(spec.root.isTruthy)
        #expect(spec.elements.count == 2)
        let root = try #require(spec.elements[spec.root.stringValue ?? ""])
        #expect(root["type"] == "Card")
        #expect(root["props"]["title"] == "Nested")
        #expect(root["children"].arrayValue?.count == 1)
        let child = try #require(spec.elements[root["children"][0].stringValue ?? ""])
        #expect(child["type"] == "Text")
        #expect(child["props"]["content"] == "Child")
    }

    @Test("preserves named slots in nested spec parts")
    func preservesNestedSlots() throws {
        let spec = try #require(try MessageParts.spec(from: [
            ["type": "data-spec", "data": ["type": "nested", "spec": [
                "type": "Layout", "props": [:],
                "slots": ["header": [["type": "Heading", "props": ["text": "Header"], "children": []]]],
            ]]],
        ]))
        let root = try #require(spec.elements[spec.root.stringValue ?? ""])
        #expect(root["slots"]["header"].arrayValue?.count == 1)
        #expect(spec.elements[root["slots"]["header"][0].stringValue ?? ""]?["type"] == "Heading")
    }

    @Test("handles mixed patch + flat + nested parts in sequence")
    func handlesMixedParts() throws {
        let spec = try #require(try MessageParts.spec(from: [
            patchPart(["op": "add", "path": "/root", "value": "main"]),
            patchPart(["op": "add", "path": "/elements/main", "value": ["type": "Stack", "props": [:], "children": []]]),
            ["type": "data-spec", "data": ["type": "flat", "spec": ["root": "card-1", "elements": ["card-1": ["type": "Card", "props": ["title": "Flat"], "children": []]]]]],
        ]))
        #expect(spec.root == "card-1")
        #expect(spec.elements["card-1"] != nil)
        #expect(spec.elements["card-1"]?["type"] == "Card")
    }

    @Test("returns empty elements map from empty parts list")
    func returnsNilForNoParts() throws {
        #expect(try MessageParts.spec(from: []) == nil)
    }
}

@Suite("hooks.test.ts › getTextFromParts")
struct TextFromPartsTests {
    @Test("extracts text from text parts")
    func extractsText() {
        #expect(MessageParts.text(from: [["type": "text", "text": "Hello"], ["type": "text", "text": "World"]]) == "Hello\n\nWorld")
    }

    @Test("returns empty string when no text parts")
    func returnsEmptyWithoutText() {
        #expect(MessageParts.text(from: [patchPart(["op": "add", "path": "/root", "value": "x"])]) == "")
    }

    @Test("ignores non-text parts")
    func ignoresOtherParts() {
        let parts: [JSONObject] = [
            ["type": "text", "text": "Before"], ["type": "data-spec", "data": [:]], ["type": "tool-invocation", "data": [:]], ["type": "text", "text": "After"],
        ]
        #expect(MessageParts.text(from: parts) == "Before\n\nAfter")
    }

    @Test("trims whitespace from text parts")
    func trimsWhitespace() {
        #expect(MessageParts.text(from: [["type": "text", "text": "  Hello  "], ["type": "text", "text": "  World  "]]) == "Hello\n\nWorld")
    }

    @Test("skips empty text parts")
    func skipsEmptyParts() {
        #expect(MessageParts.text(from: [["type": "text", "text": "Hello"], ["type": "text", "text": "   "], ["type": "text", "text": "World"]]) == "Hello\n\nWorld")
    }

    @Test("ignores text parts with non-string text field")
    func ignoresNonStringText() {
        let parts: [JSONObject] = [
            ["type": "text", "text": "Valid"], ["type": "text", "text": .undefined], ["type": "text", "text": 42], ["type": "text", "text": "Also valid"],
        ]
        #expect(MessageParts.text(from: parts) == "Valid\n\nAlso valid")
    }
}

// Ports upstream tests from packages/core/src/props.test.ts (json-render 0.21.1).
import Testing
@testable import JSONRender

// MARK: - resolvePropValue

@Suite("props.test.ts › resolvePropValue › literals")
struct PropExpressionLiteralTests {
    @Test("passes through strings")
    func passesThroughStrings() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve("hello", in: ctx) == "hello")
    }

    @Test("passes through numbers")
    func passesThroughNumbers() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(42, in: ctx) == 42)
    }

    @Test("passes through booleans")
    func passesThroughBooleans() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(true, in: ctx) == true)
        #expect(try PropExpression.resolve(false, in: ctx) == false)
    }

    @Test("passes through null")
    func passesThroughNull() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(.null, in: ctx) == .null)
    }

    @Test("passes through undefined")
    func passesThroughUndefined() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(.undefined, in: ctx) == .undefined)
    }
}

@Suite("props.test.ts › resolvePropValue › $state expressions")
struct PropExpressionStateTests {
    @Test("resolves a state path")
    func resolvesStatePath() throws {
        let ctx = ResolutionContext(state: ["user": ["name": "Alice"]])
        #expect(try PropExpression.resolve(["$state": "/user/name"], in: ctx) == "Alice")
    }

    @Test("returns undefined for missing state path")
    func returnsUndefinedForMissingPath() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(["$state": "/missing"], in: ctx) == .undefined)
    }

    @Test("resolves nested state path")
    func resolvesNestedPath() throws {
        let ctx = ResolutionContext(state: ["a": ["b": ["c": 42]]])
        #expect(try PropExpression.resolve(["$state": "/a/b/c"], in: ctx) == 42)
    }
}

@Suite("props.test.ts › resolvePropValue › $item expressions")
struct PropExpressionItemTests {
    @Test("resolves a field from the repeat item")
    func resolvesItemField() throws {
        let ctx = ResolutionContext(state: [:], repeatItem: ["title": "Hello", "id": "1"], repeatIndex: 0)
        #expect(try PropExpression.resolve(["$item": "title"], in: ctx) == "Hello")
    }

    @Test(#"resolves "/" to the whole item"#)
    func resolvesWholeItem() throws {
        let item: JSONValue = ["title": "Hello", "id": "1"]
        let ctx = ResolutionContext(state: [:], repeatItem: item, repeatIndex: 0)
        #expect(try PropExpression.resolve(["$item": ""], in: ctx).strictEquals(item))
    }

    @Test("resolves nested field from item")
    func resolvesNestedItemField() throws {
        let ctx = ResolutionContext(state: [:], repeatItem: ["user": ["name": "Bob"]], repeatIndex: 0)
        #expect(try PropExpression.resolve(["$item": "user/name"], in: ctx) == "Bob")
    }

    @Test("returns undefined when no repeat item in context")
    func returnsUndefinedWithoutRepeatItem() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(["$item": "title"], in: ctx) == .undefined)
    }

    @Test("returns undefined for missing field on item")
    func returnsUndefinedForMissingItemField() throws {
        let ctx = ResolutionContext(state: [:], repeatItem: ["title": "Hello"], repeatIndex: 0)
        #expect(try PropExpression.resolve(["$item": "missing"], in: ctx) == .undefined)
    }
}

@Suite("props.test.ts › resolvePropValue › $index expressions")
struct PropExpressionIndexTests {
    @Test("returns the current repeat index")
    func returnsRepeatIndex() throws {
        let ctx = ResolutionContext(state: [:], repeatItem: ["id": "1"], repeatIndex: 3)
        #expect(try PropExpression.resolve(["$index": true], in: ctx) == 3)
    }

    @Test("returns 0 for first item")
    func returnsZeroForFirstItem() throws {
        let ctx = ResolutionContext(state: [:], repeatItem: ["id": "1"], repeatIndex: 0)
        #expect(try PropExpression.resolve(["$index": true], in: ctx) == 0)
    }

    @Test("returns undefined when no repeat index in context")
    func returnsUndefinedWithoutRepeatIndex() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(["$index": true], in: ctx) == .undefined)
    }
}

@Suite("props.test.ts › resolvePropValue › $cond/$then/$else expressions")
struct PropExpressionCondTests {
    @Test("returns $then when condition is true")
    func returnsThenWhenTrue() throws {
        let ctx = ResolutionContext(state: ["active": true])
        let value: JSONValue = ["$cond": ["$state": "/active"], "$then": "blue", "$else": "gray"]
        #expect(try PropExpression.resolve(value, in: ctx) == "blue")
    }

    @Test("returns $else when condition is false")
    func returnsElseWhenFalse() throws {
        let ctx = ResolutionContext(state: ["active": false])
        let value: JSONValue = ["$cond": ["$state": "/active"], "$then": "blue", "$else": "gray"]
        #expect(try PropExpression.resolve(value, in: ctx) == "gray")
    }

    @Test("handles eq condition")
    func handlesEqCondition() throws {
        let ctx = ResolutionContext(state: ["tab": "home"])
        let value: JSONValue = [
            "$cond": ["$state": "/tab", "eq": "home"],
            "$then": "#007AFF",
            "$else": "#8E8E93",
        ]
        #expect(try PropExpression.resolve(value, in: ctx) == "#007AFF")
    }

    @Test("handles nested expression in $then/$else")
    func handlesNestedBranchExpression() throws {
        let ctx = ResolutionContext(state: ["isAdmin": true, "admin": ["greeting": "Hello Admin"]])
        let value: JSONValue = [
            "$cond": ["$state": "/isAdmin"],
            "$then": ["$state": "/admin/greeting"],
            "$else": "Welcome",
        ]
        #expect(try PropExpression.resolve(value, in: ctx) == "Hello Admin")
    }

    @Test("handles array condition (implicit AND)")
    func handlesArrayCondition() throws {
        let ctx = ResolutionContext(state: ["isAdmin": true, "feature": true])
        let value: JSONValue = [
            "$cond": [["$state": "/isAdmin"], ["$state": "/feature"]],
            "$then": "yes",
            "$else": "no",
        ]
        #expect(try PropExpression.resolve(value, in: ctx) == "yes")
    }
}

@Suite("props.test.ts › resolvePropValue › nested objects and arrays")
struct PropExpressionNestedTests {
    @Test("resolves expressions inside plain objects")
    func resolvesInsideObjects() throws {
        let ctx = ResolutionContext(state: ["color": "red", "size": 12])
        let result = try PropExpression.resolve(
            ["fill": ["$state": "/color"], "fontSize": ["$state": "/size"]],
            in: ctx
        )
        #expect(result == ["fill": "red", "fontSize": 12])
    }

    @Test("resolves expressions inside arrays")
    func resolvesInsideArrays() throws {
        let ctx = ResolutionContext(state: ["a": 1, "b": 2])
        let result = try PropExpression.resolve([["$state": "/a"], ["$state": "/b"], 3], in: ctx)
        #expect(result == [1, 2, 3])
    }

    @Test("resolves deeply nested expressions")
    func resolvesDeeplyNested() throws {
        let ctx = ResolutionContext(state: ["theme": ["primary": "#007AFF"]])
        let result = try PropExpression.resolve(
            ["style": ["color": ["$state": "/theme/primary"], "margin": 10]],
            in: ctx
        )
        #expect(result == ["style": ["color": "#007AFF", "margin": 10]])
    }
}

// MARK: - resolveElementProps

@Suite("props.test.ts › resolveElementProps")
struct PropExpressionElementPropsTests {
    @Test("resolves all props in an element")
    func resolvesAllProps() throws {
        let ctx = ResolutionContext(state: ["user": ["name": "Alice", "role": "admin"]])
        let props: JSONObject = [
            "label": ["$state": "/user/name"],
            "badge": ["$state": "/user/role"],
            "static": "always",
        ]
        #expect(try PropExpression.resolveProps(props, in: ctx) == [
            "label": "Alice",
            "badge": "admin",
            "static": "always",
        ])
    }

    @Test("resolves mixed expressions and literals")
    func resolvesMixedProps() throws {
        let ctx = ResolutionContext(state: ["active": true], repeatItem: ["title": "Item 1"], repeatIndex: 2)
        let props: JSONObject = [
            "title": ["$item": "title"],
            "index": ["$index": true],
            "color": [
                "$cond": ["$state": "/active"],
                "$then": "green",
                "$else": "gray",
            ],
            "width": 100,
        ]
        #expect(try PropExpression.resolveProps(props, in: ctx) == [
            "title": "Item 1",
            "index": 2,
            "color": "green",
            "width": 100,
        ])
    }

    @Test("returns empty object for empty props")
    func returnsEmptyForEmptyProps() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolveProps([:], in: ctx) == [:])
    }
}

// MARK: - $bindState / $bindItem expressions

@Suite("props.test.ts › $bindState expressions › resolvePropValue with $bindState")
struct PropExpressionBindStateTests {
    @Test("resolves to the state value at the path")
    func resolvesStateValue() throws {
        let ctx = ResolutionContext(state: ["form": ["email": "alice@example.com"]])
        #expect(try PropExpression.resolve(["$bindState": "/form/email"], in: ctx) == "alice@example.com")
    }

    @Test("returns undefined for missing path")
    func returnsUndefinedForMissingPath() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(["$bindState": "/missing"], in: ctx) == .undefined)
    }
}

@Suite("props.test.ts › $bindState expressions › resolvePropValue with $bindItem")
struct PropExpressionBindItemTests {
    @Test("resolves item field using repeatBasePath")
    func resolvesUsingBasePath() throws {
        let ctx = ResolutionContext(
            state: ["todos": [["completed": true], ["completed": false]]],
            repeatItem: ["completed": true],
            repeatIndex: 0,
            repeatBasePath: "/todos/0"
        )
        #expect(try PropExpression.resolve(["$bindItem": "completed"], in: ctx) == true)
    }

    @Test(#"handles "/" as the full item path"#)
    func handlesWholeItemPath() throws {
        let ctx = ResolutionContext(
            state: ["items": ["hello", "world"]],
            repeatItem: "hello",
            repeatIndex: 0,
            repeatBasePath: "/items/0"
        )
        #expect(try PropExpression.resolve(["$bindItem": ""], in: ctx) == "hello")
    }

    @Test("returns undefined when no repeatBasePath")
    func returnsUndefinedWithoutBasePath() throws {
        let ctx = ResolutionContext(state: [:], repeatItem: ["completed": true], repeatIndex: 0)
        // Without repeatBasePath, the raw item path won't resolve in stateModel
        #expect(try PropExpression.resolve(["$bindItem": "completed"], in: ctx) == .undefined)
    }
}

@Suite("props.test.ts › $bindState expressions › resolveBindings")
struct PropExpressionBindingsTests {
    @Test("extracts $bindState paths from props")
    func extractsBindStatePaths() {
        let ctx = ResolutionContext(state: [:])
        let props: JSONObject = [
            "value": ["$bindState": "/form/email"],
            "label": "Email",
            "placeholder": "Enter email",
        ]
        #expect(PropExpression.bindings(for: props, in: ctx) == [
            "value": "/form/email",
        ])
    }

    @Test("returns undefined when no bind expressions")
    func returnsNilWithoutBindings() {
        let ctx = ResolutionContext(state: [:])
        let props: JSONObject = [
            "label": "Hello",
            "count": 42,
        ]
        #expect(PropExpression.bindings(for: props, in: ctx) == nil)
    }

    @Test("handles multiple $bindState props")
    func handlesMultipleBindStateProps() {
        let ctx = ResolutionContext(state: [:])
        let props: JSONObject = [
            "value": ["$bindState": "/form/name"],
            "checked": ["$bindState": "/form/agree"],
            "label": "Name",
        ]
        #expect(PropExpression.bindings(for: props, in: ctx) == [
            "value": "/form/name",
            "checked": "/form/agree",
        ])
    }

    @Test("resolves $bindItem paths using repeatBasePath")
    func resolvesBindItemPaths() {
        let ctx = ResolutionContext(
            state: [:],
            repeatItem: ["completed": false],
            repeatIndex: 1,
            repeatBasePath: "/todos/1"
        )
        let props: JSONObject = [
            "checked": ["$bindItem": "completed"],
            "label": ["$item": "title"],
        ]
        #expect(PropExpression.bindings(for: props, in: ctx) == [
            "checked": "/todos/1/completed",
        ])
    }

    @Test("ignores non-bind dynamic expressions")
    func ignoresNonBindExpressions() {
        let ctx = ResolutionContext(state: [:])
        let props: JSONObject = [
            "title": ["$state": "/title"],
            "index": ["$index": true],
            "name": ["$item": "name"],
            "value": ["$bindState": "/path"],
        ]
        #expect(PropExpression.bindings(for: props, in: ctx) == [
            "value": "/path",
        ])
    }

    @Test("handles mixed $bindState and $bindItem props")
    func handlesMixedBindings() {
        let ctx = ResolutionContext(
            state: [:],
            repeatItem: ["done": false],
            repeatIndex: 0,
            repeatBasePath: "/todos/0"
        )
        let props: JSONObject = [
            "value": ["$bindState": "/form/search"],
            "checked": ["$bindItem": "done"],
            "label": "Task",
        ]
        #expect(PropExpression.bindings(for: props, in: ctx) == [
            "value": "/form/search",
            "checked": "/todos/0/done",
        ])
    }
}

// MARK: - resolveActionParam

@Suite("props.test.ts › resolveActionParam")
struct PropExpressionActionParamTests {
    @Test("resolves $item to an absolute state path via repeatBasePath")
    func resolvesItemToStatePath() throws {
        let ctx = ResolutionContext(
            state: ["todos": [["title": "Buy milk"]]],
            repeatItem: ["title": "Buy milk"],
            repeatIndex: 0,
            repeatBasePath: "/todos/0"
        )
        #expect(try PropExpression.resolveActionParam(["$item": "title"], in: ctx) == "/todos/0/title")
    }

    @Test("resolves $item with empty string to the repeatBasePath itself")
    func resolvesEmptyItemToBasePath() throws {
        let ctx = ResolutionContext(
            state: ["items": ["a", "b"]],
            repeatItem: "a",
            repeatIndex: 0,
            repeatBasePath: "/items/0"
        )
        #expect(try PropExpression.resolveActionParam(["$item": ""], in: ctx) == "/items/0")
    }

    @Test("returns undefined for $item when no repeatBasePath")
    func returnsUndefinedForItemWithoutBasePath() throws {
        let ctx = ResolutionContext(state: [:], repeatItem: ["title": "Hello"], repeatIndex: 0)
        #expect(try PropExpression.resolveActionParam(["$item": "title"], in: ctx) == .undefined)
    }

    @Test("resolves $index to the current repeat index")
    func resolvesIndex() throws {
        let ctx = ResolutionContext(state: [:], repeatItem: ["id": "1"], repeatIndex: 5)
        #expect(try PropExpression.resolveActionParam(["$index": true], in: ctx) == 5)
    }

    @Test("returns undefined for $index when no repeat context")
    func returnsUndefinedForIndexWithoutRepeat() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolveActionParam(["$index": true], in: ctx) == .undefined)
    }

    @Test("delegates $state expressions to resolvePropValue")
    func delegatesStateExpressions() throws {
        let ctx = ResolutionContext(state: ["form": ["id": "abc-123"]])
        #expect(try PropExpression.resolveActionParam(["$state": "/form/id"], in: ctx) == "abc-123")
    }

    @Test("passes through literal strings")
    func passesThroughStrings() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolveActionParam("submit", in: ctx) == "submit")
    }

    @Test("passes through literal numbers")
    func passesThroughNumbers() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolveActionParam(42, in: ctx) == 42)
    }

    @Test("passes through null")
    func passesThroughNull() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolveActionParam(.null, in: ctx) == .null)
    }
}

// MARK: - $computed expressions

@Suite("props.test.ts › $computed expressions")
struct PropExpressionComputedTests {
    @Test("calls a registered function with resolved args")
    func callsFunctionWithResolvedArgs() throws {
        let ctx = ResolutionContext(
            state: ["form": ["firstName": "Jane", "lastName": "Doe"]],
            functions: [
                "fullName": { args in
                    let args = JSONValue.object(args)
                    return .string("\(args["first"].javaScriptString) \(args["last"].javaScriptString)")
                },
            ]
        )
        let value: JSONValue = [
            "$computed": "fullName",
            "args": [
                "first": ["$state": "/form/firstName"],
                "last": ["$state": "/form/lastName"],
            ],
        ]
        #expect(try PropExpression.resolve(value, in: ctx) == "Jane Doe")
    }

    @Test("calls function with no args")
    func callsFunctionWithoutArgs() throws {
        let ctx = ResolutionContext(
            state: [:],
            functions: [
                "timestamp": { _ in 1_234_567_890 },
            ]
        )
        #expect(try PropExpression.resolve(["$computed": "timestamp"], in: ctx) == 1_234_567_890)
    }

    @Test("returns undefined for unknown function")
    func returnsUndefinedForUnknownFunction() throws {
        let ctx = ResolutionContext(state: [:], functions: [:])
        #expect(try PropExpression.resolve(["$computed": "unknown"], in: ctx) == .undefined)
    }

    @Test("returns undefined when no functions in context")
    func returnsUndefinedWithoutFunctions() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(["$computed": "any"], in: ctx) == .undefined)
    }

    @Test("deduplicates warnings for the same unknown function")
    func deduplicatesUnknownFunctionWarnings() throws {
        let recorder = DiagnosticsRecorder()
        let ctx = ResolutionContext(state: [:], functions: [:])
        try recorder.record {
            _ = try PropExpression.resolve(["$computed": "dedupTest"], in: ctx)
            _ = try PropExpression.resolve(["$computed": "dedupTest"], in: ctx)
        }
        let calls = recorder.warnings.filter { $0.contains("dedupTest") }
        #expect(calls.count == 1)
    }

    @Test("resolves nested expressions in args")
    func resolvesNestedArgs() throws {
        let ctx = ResolutionContext(
            state: ["active": true, "values": ["a": 10, "b": 20]],
            functions: [
                "conditionalSum": { args in
                    let args = JSONValue.object(args)
                    if args["enabled"].isTruthy {
                        return .number((args["x"].numberValue ?? .nan) + (args["y"].numberValue ?? .nan))
                    }
                    return 0
                },
            ]
        )
        let value: JSONValue = [
            "$computed": "conditionalSum",
            "args": [
                "enabled": ["$state": "/active"],
                "x": ["$state": "/values/a"],
                "y": ["$state": "/values/b"],
            ],
        ]
        #expect(try PropExpression.resolve(value, in: ctx) == 30)
    }
}

// MARK: - $template expressions

@Suite("props.test.ts › $template expressions")
struct PropExpressionTemplateTests {
    @Test("interpolates state values into a string")
    func interpolatesStateValues() throws {
        let ctx = ResolutionContext(state: ["user": ["name": "Alice"], "count": 3])
        let value: JSONValue = ["$template": "Hello, ${/user/name}! You have ${/count} messages."]
        #expect(try PropExpression.resolve(value, in: ctx) == "Hello, Alice! You have 3 messages.")
    }

    @Test("replaces missing paths with empty string")
    func replacesMissingPathsWithEmpty() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(["$template": "Hi ${/name}!"], in: ctx) == "Hi !")
    }

    @Test("handles template with no interpolations")
    func handlesNoInterpolations() throws {
        let ctx = ResolutionContext(state: [:])
        #expect(try PropExpression.resolve(["$template": "No variables here"], in: ctx) == "No variables here")
    }

    @Test("handles multiple references to the same path")
    func handlesRepeatedReferences() throws {
        let ctx = ResolutionContext(state: ["x": "A"])
        #expect(try PropExpression.resolve(["$template": "${/x} and ${/x}"], in: ctx) == "A and A")
    }

    @Test("converts non-string values to strings")
    func convertsNonStringValues() throws {
        let ctx = ResolutionContext(state: ["num": 42, "bool": true])
        #expect(try PropExpression.resolve(["$template": "${/num} is ${/bool}"], in: ctx) == "42 is true")
    }

    @Test("resolves bare names against state model when not in repeat")
    func resolvesBareNamesAgainstState() throws {
        let ctx = ResolutionContext(state: ["name": "Bob"])
        let result = try PropExpression.resolve(["$template": "Hi ${name}!"], in: ctx)
        #expect(result == "Hi Bob!")
    }

    @Test("resolves bare names against repeat item first")
    func resolvesBareNamesAgainstItemFirst() throws {
        let ctx = ResolutionContext(
            state: ["name": "Global"],
            repeatItem: ["name": "Alice", "action": "signed up"],
            repeatIndex: 0
        )
        let result = try PropExpression.resolve(["$template": "${name} ${action}"], in: ctx)
        #expect(result == "Alice signed up")
    }

    @Test("falls back to state model for bare names not in repeat item")
    func fallsBackToStateForBareNames() throws {
        let ctx = ResolutionContext(state: ["fallback": "ok"], repeatItem: ["name": "Alice"], repeatIndex: 0)
        let result = try PropExpression.resolve(["$template": "${name} - ${fallback}"], in: ctx)
        #expect(result == "Alice - ok")
    }
}

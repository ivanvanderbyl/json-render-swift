// Ports upstream tests from packages/core/src/directives.test.ts (json-render 0.21.1).
import Testing
@testable import JSONRender

// Upstream zod schemas are written here as the equivalent JSON Schema. The
// schema is informational only, so it does not change what the tests check.

/// Upstream compares definitions by reference with `toBe`. A Swift definition
/// is a value that holds a closure, so compare the fields that can be compared.
private func isSameDefinition(_ found: DirectiveDefinition?, _ expected: DirectiveDefinition) -> Bool {
    guard let found else { return false }
    return found.name == expected.name
        && found.description == expected.description
        && found.schema == expected.schema
}

@Suite("directives.test.ts › defineDirective")
struct DirectiveDefineTests {
    @Test("returns the definition unchanged")
    func returnsDefinitionUnchanged() throws {
        let def = try DirectiveDefinition(
            name: "$double",
            schema: ["type": "object", "properties": ["$double": ["type": "number"]]],
            resolve: { value, _ in .number((value["$double"].numberValue ?? .nan) * 2) }
        )
        #expect(def.name == "$double")
        // `typeof def.resolve` is "function" by construction: `resolve` is a
        // non-optional closure property.
    }

    @Test("throws when name does not start with $")
    func throwsWithoutDollarPrefix() {
        let error = #expect(throws: JavaScriptError.self) {
            try DirectiveDefinition(
                name: "double",
                schema: ["type": "object", "properties": ["double": ["type": "number"]]],
                resolve: { _, _ in 0 }
            )
        }
        #expect(error?.message.contains(#"Directive name must start with "$""#) == true)
    }

    @Test("throws when name conflicts with a built-in key")
    func throwsForBuiltInKey() {
        for name in [
            "$state",
            "$item",
            "$index",
            "$bindState",
            "$bindItem",
            "$cond",
            "$computed",
            "$template",
        ] {
            let error = #expect(throws: JavaScriptError.self) {
                try DirectiveDefinition(
                    name: name,
                    schema: ["type": "object", "properties": [:]],
                    resolve: { _, _ in 0 }
                )
            }
            #expect(error?.message.contains("conflicts with a built-in") == true)
        }
    }
}

@Suite("directives.test.ts › createDirectiveRegistry")
struct DirectiveRegistryTests {
    @Test("creates a Map from an array of definitions")
    func createsRegistry() throws {
        let d1 = try DirectiveDefinition(
            name: "$a",
            schema: ["type": "object", "properties": ["$a": ["type": "string"]]],
            resolve: { _, _ in "a" }
        )
        let d2 = try DirectiveDefinition(
            name: "$b",
            schema: ["type": "object", "properties": ["$b": ["type": "string"]]],
            resolve: { _, _ in "b" }
        )
        let reg = DirectiveRegistry([d1, d2])
        #expect(reg.count == 2)
        #expect(isSameDefinition(reg["$a"], d1))
        #expect(isSameDefinition(reg["$b"], d2))
    }

    @Test("returns an empty Map for an empty array")
    func createsEmptyRegistry() {
        let reg = DirectiveRegistry([])
        #expect(reg.count == 0)
    }
}

@Suite("directives.test.ts › findDirective")
struct DirectiveFindTests {
    let d: DirectiveDefinition
    let registry: DirectiveRegistry

    init() throws {
        d = try DirectiveDefinition(
            name: "$upper",
            schema: ["type": "object", "properties": ["$upper": ["type": "string"]]],
            resolve: { value, _ in .string(value["$upper"].javaScriptString.uppercased()) }
        )
        registry = DirectiveRegistry([d])
    }

    @Test("finds a matching directive")
    func findsMatchingDirective() throws {
        #expect(try isSameDefinition(registry.find(in: ["$upper": "hello"]), d))
    }

    @Test("returns undefined for non-matching objects")
    func returnsNilForNonMatchingObject() throws {
        #expect(try registry.find(in: ["foo": "bar"]) == nil)
    }

    @Test("returns undefined when registry is undefined")
    func returnsNilWithoutRegistry() throws {
        // Swift models a missing registry as an optional, as in
        // `ResolutionContext.directives`, so there is nothing to search.
        let missing: DirectiveRegistry? = nil
        #expect(try missing?.find(in: ["$upper": "hello"]) == nil)
    }

    @Test("returns undefined for empty registry")
    func returnsNilForEmptyRegistry() throws {
        #expect(try DirectiveRegistry([]).find(in: ["$upper": "hello"]) == nil)
    }

    @Test("ignores $ keys not in registry")
    func ignoresUnregisteredKeys() throws {
        #expect(try registry.find(in: ["$unknown": 1]) == nil)
    }

    @Test("throws when multiple directive keys match")
    func throwsForAmbiguousKeys() throws {
        let d2 = try DirectiveDefinition(
            name: "$lower",
            schema: ["type": "object", "properties": ["$lower": ["type": "string"]]],
            resolve: { value, _ in .string(value["$lower"].javaScriptString.lowercased()) }
        )
        let multiRegistry = DirectiveRegistry([d, d2])
        let error = #expect(throws: JavaScriptError.self) {
            try multiRegistry.find(in: ["$upper": "hello", "$lower": "WORLD"])
        }
        #expect(error?.message.contains("Ambiguous directive") == true)
    }
}

@Suite("directives.test.ts › resolvePropValue with custom directives")
struct DirectiveResolutionTests {
    let registry: DirectiveRegistry

    init() throws {
        let doubleDirective = try DirectiveDefinition(
            name: "$double",
            schema: ["type": "object", "properties": ["$double": [:]]],
            resolve: { value, ctx in
                let resolved = try PropExpression.resolve(value["$double"], in: ctx)
                return .number((resolved.numberValue ?? .nan) * 2)
            }
        )

        let upperDirective = try DirectiveDefinition(
            name: "$upper",
            schema: ["type": "object", "properties": ["$upper": [:]]],
            resolve: { value, ctx in
                let resolved = try PropExpression.resolve(value["$upper"], in: ctx)
                return .string(resolved.javaScriptString.uppercased())
            }
        )

        registry = DirectiveRegistry([doubleDirective, upperDirective])
    }

    @Test("resolves a custom directive")
    func resolvesCustomDirective() throws {
        let ctx = ResolutionContext(state: [:], directives: registry)
        #expect(try PropExpression.resolve(["$double": 5], in: ctx) == 10)
    }

    @Test("resolves a directive with $state sub-value")
    func resolvesStateSubValue() throws {
        let ctx = ResolutionContext(state: ["count": 7], directives: registry)
        #expect(try PropExpression.resolve(["$double": ["$state": "/count"]], in: ctx) == 14)
    }

    @Test("resolves nested directives (composition)")
    func resolvesNestedDirectives() throws {
        let ctx = ResolutionContext(state: ["val": 3], directives: registry)
        let value: JSONValue = ["$double": ["$double": ["$state": "/val"]]]
        #expect(try PropExpression.resolve(value, in: ctx) == 12)
    }

    @Test("resolves directives inside object props")
    func resolvesInsideObjects() throws {
        let ctx = ResolutionContext(state: ["name": "alice"], directives: registry)
        let value: JSONValue = ["label": ["$upper": ["$state": "/name"]], "count": 1]
        #expect(try PropExpression.resolve(value, in: ctx) == [
            "label": "ALICE",
            "count": 1,
        ])
    }

    @Test("resolves directives inside arrays")
    func resolvesInsideArrays() throws {
        let ctx = ResolutionContext(state: ["x": 5], directives: registry)
        let value: JSONValue = [["$double": ["$state": "/x"]], "literal"]
        #expect(try PropExpression.resolve(value, in: ctx) == [10, "literal"])
    }

    @Test("falls through to plain object resolution when no directive matches")
    func fallsThroughToPlainObject() throws {
        let ctx = ResolutionContext(state: ["a": 1], directives: registry)
        #expect(try PropExpression.resolve(["foo": ["$state": "/a"]], in: ctx) == [
            "foo": 1,
        ])
    }

    @Test("cannot register a directive that shadows a built-in key")
    func rejectsBuiltInShadowing() {
        let error = #expect(throws: JavaScriptError.self) {
            try DirectiveDefinition(
                name: "$state",
                schema: ["type": "object", "properties": ["$state": ["type": "string"]]],
                resolve: { _, _ in "should-not-reach" }
            )
        }
        #expect(error?.message.contains("conflicts with a built-in") == true)
    }

    @Test("works without directives in context (backward compat)")
    func worksWithoutDirectives() throws {
        let ctx = ResolutionContext(state: ["x": 1])
        #expect(try PropExpression.resolve(["$state": "/x"], in: ctx) == 1)
        #expect(try PropExpression.resolve(["foo": "bar"], in: ctx) == ["foo": "bar"])
    }
}

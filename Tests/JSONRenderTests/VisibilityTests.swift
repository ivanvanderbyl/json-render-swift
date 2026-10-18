// Ports upstream tests from packages/core/src/visibility.test.ts (json-render 0.21.1).
// Suite and test names match the upstream describe and it names.

import Testing
@testable import JSONRender

@Suite("visibility.test.ts › evaluateVisibility › undefined / boolean")
struct VisibilityUndefinedBooleanTests {
    @Test("returns true for undefined")
    func trueForUndefined() throws {
        #expect(try Visibility.evaluate(.undefined, in: ResolutionContext(state: [:])) == true)
    }

    @Test("returns true for true")
    func trueForTrue() throws {
        #expect(try Visibility.evaluate(true, in: ResolutionContext(state: [:])) == true)
    }

    @Test("returns false for false")
    func falseForFalse() throws {
        #expect(try Visibility.evaluate(false, in: ResolutionContext(state: [:])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › truthiness ($state only)")
struct VisibilityTruthinessTests {
    @Test("returns true when state path is truthy (boolean)")
    func truthyBoolean() throws {
        #expect(try Visibility.evaluate(["$state": "/isAdmin"], in: ResolutionContext(state: ["isAdmin": true])) == true)
    }

    @Test("returns true when state path is truthy (number)")
    func truthyNumber() throws {
        #expect(try Visibility.evaluate(["$state": "/count"], in: ResolutionContext(state: ["count": 5])) == true)
    }

    @Test("returns true when state path is truthy (string)")
    func truthyString() throws {
        #expect(try Visibility.evaluate(["$state": "/name"], in: ResolutionContext(state: ["name": "Alice"])) == true)
    }

    @Test("returns false when state path is falsy (boolean)")
    func falsyBoolean() throws {
        #expect(try Visibility.evaluate(["$state": "/isAdmin"], in: ResolutionContext(state: ["isAdmin": false])) == false)
    }

    @Test("returns false when state path is falsy (zero)")
    func falsyZero() throws {
        #expect(try Visibility.evaluate(["$state": "/count"], in: ResolutionContext(state: ["count": 0])) == false)
    }

    @Test("returns false when state path is falsy (empty string)")
    func falsyEmptyString() throws {
        #expect(try Visibility.evaluate(["$state": "/name"], in: ResolutionContext(state: ["name": ""])) == false)
    }

    @Test("returns false when state path is undefined")
    func falsyUndefined() throws {
        #expect(try Visibility.evaluate(["$state": "/nothing"], in: ResolutionContext(state: [:])) == false)
    }

    @Test("returns false for missing path")
    func falseForMissingPath() throws {
        #expect(try Visibility.evaluate(["$state": "/nonexistent"], in: ResolutionContext(state: ["other": true])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › negation ($state + not)")
struct VisibilityNegationTests {
    @Test("returns false when state path is truthy")
    func falseWhenTruthy() throws {
        let cond: JSONValue = ["$state": "/visible", "not": true]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["visible": true])) == false)
    }

    @Test("returns true when state path is falsy")
    func trueWhenFalsy() throws {
        let cond: JSONValue = ["$state": "/visible", "not": true]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["visible": false])) == true)
    }

    @Test("not inverts an eq condition")
    func notInvertsEq() throws {
        let cond: JSONValue = ["$state": "/tab", "eq": "home", "not": true]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["tab": "home"])) == false)
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["tab": "settings"])) == true)
    }

    @Test("not inverts a gt condition")
    func notInvertsGt() throws {
        let cond: JSONValue = ["$state": "/count", "gt": 5, "not": true]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["count": 10])) == false)
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["count": 3])) == true)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › equality ($state + eq)")
struct VisibilityEqualityTests {
    @Test("returns true when values match (number)")
    func matchNumber() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "eq": 5], in: ResolutionContext(state: ["count": 5])) == true)
    }

    @Test("returns false when values do not match")
    func noMatch() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "eq": 10], in: ResolutionContext(state: ["count": 5])) == false)
    }

    @Test("returns true when values match (string)")
    func matchString() throws {
        #expect(try Visibility.evaluate(["$state": "/tab", "eq": "home"], in: ResolutionContext(state: ["tab": "home"])) == true)
    }

    @Test("supports state-to-state comparison")
    func stateToState() throws {
        let cond: JSONValue = ["$state": "/a", "eq": ["$state": "/b"]]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["a": 42, "b": 42])) == true)
    }

    @Test("state-to-state comparison fails when different")
    func stateToStateDifferent() throws {
        let cond: JSONValue = ["$state": "/a", "eq": ["$state": "/b"]]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["a": 1, "b": 2])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › inequality ($state + neq)")
struct VisibilityInequalityTests {
    @Test("returns true when values differ")
    func trueWhenDiffer() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "neq": 10], in: ResolutionContext(state: ["count": 5])) == true)
    }

    @Test("returns false when values are equal")
    func falseWhenEqual() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "neq": 5], in: ResolutionContext(state: ["count": 5])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › numeric comparisons")
struct VisibilityNumericComparisonTests {
    @Test("gt: returns true when greater")
    func gtGreater() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "gt": 3], in: ResolutionContext(state: ["count": 5])) == true)
    }

    @Test("gt: returns false when less")
    func gtLess() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "gt": 3], in: ResolutionContext(state: ["count": 2])) == false)
    }

    @Test("gt: returns false when equal")
    func gtEqual() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "gt": 5], in: ResolutionContext(state: ["count": 5])) == false)
    }

    @Test("gte: returns true when equal")
    func gteEqual() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "gte": 5], in: ResolutionContext(state: ["count": 5])) == true)
    }

    @Test("gte: returns true when greater")
    func gteGreater() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "gte": 5], in: ResolutionContext(state: ["count": 6])) == true)
    }

    @Test("gte: returns false when less")
    func gteLess() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "gte": 5], in: ResolutionContext(state: ["count": 4])) == false)
    }

    @Test("lt: returns true when less")
    func ltLess() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "lt": 5], in: ResolutionContext(state: ["count": 3])) == true)
    }

    @Test("lt: returns false when greater")
    func ltGreater() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "lt": 5], in: ResolutionContext(state: ["count": 7])) == false)
    }

    @Test("lt: returns false when equal")
    func ltEqual() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "lt": 5], in: ResolutionContext(state: ["count": 5])) == false)
    }

    @Test("lte: returns true when equal")
    func lteEqual() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "lte": 5], in: ResolutionContext(state: ["count": 5])) == true)
    }

    @Test("lte: returns true when less")
    func lteLess() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "lte": 5], in: ResolutionContext(state: ["count": 4])) == true)
    }

    @Test("lte: returns false when greater")
    func lteGreater() throws {
        #expect(try Visibility.evaluate(["$state": "/count", "lte": 5], in: ResolutionContext(state: ["count": 6])) == false)
    }

    @Test("returns false for non-numeric values")
    func falseForNonNumeric() throws {
        #expect(try Visibility.evaluate(["$state": "/name", "gt": 5], in: ResolutionContext(state: ["name": "Alice"])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › dynamic path references in comparison")
struct VisibilityDynamicReferenceTests {
    @Test("eq with $state reference on right")
    func eqWithStateReference() throws {
        let cond: JSONValue = ["$state": "/count", "eq": ["$state": "/limit"]]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["count": 5, "limit": 5])) == true)
    }

    @Test("lt with $state reference on right")
    func ltWithStateReference() throws {
        let cond: JSONValue = ["$state": "/count", "lt": ["$state": "/limit"]]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: ["count": 3, "limit": 5])) == true)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › array (implicit AND)")
struct VisibilityImplicitAndTests {
    static let cond: JSONValue = [["$state": "/isAdmin"], ["$state": "/tab", "eq": "settings"]]

    @Test("returns true when all conditions are true")
    func trueWhenAllTrue() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": true, "tab": "settings"])) == true)
    }

    @Test("returns false when one condition is false")
    func falseWhenOneFalse() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": false, "tab": "settings"])) == false)
    }

    @Test("returns false when all conditions are false")
    func falseWhenAllFalse() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": false, "tab": "home"])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › $and condition (explicit AND)")
struct VisibilityExplicitAndTests {
    static let cond: JSONValue = ["$and": [["$state": "/isAdmin"], ["$state": "/tab", "eq": "settings"]]]

    @Test("returns true when all children are true")
    func trueWhenAllTrue() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": true, "tab": "settings"])) == true)
    }

    @Test("returns false when one child is false")
    func falseWhenOneFalse() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": false, "tab": "settings"])) == false)
    }

    @Test("returns false when all children are false")
    func falseWhenAllFalse() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": false, "tab": "home"])) == false)
    }

    @Test("supports nested $or inside $and")
    func nestedOrInsideAnd() throws {
        // AND( OR(isAdmin, isModerator), tab=settings )
        let cond: JSONValue = [
            "$and": [
                ["$or": [["$state": "/isAdmin"], ["$state": "/isModerator"]]],
                ["$state": "/tab", "eq": "settings"],
            ],
        ]
        #expect(
            try Visibility.evaluate(
                cond,
                in: ResolutionContext(state: ["isAdmin": false, "isModerator": true, "tab": "settings"])
            ) == true
        )
        #expect(
            try Visibility.evaluate(
                cond,
                in: ResolutionContext(state: ["isAdmin": false, "isModerator": false, "tab": "settings"])
            ) == false
        )
    }

    @Test("supports booleans inside $and")
    func booleansInsideAnd() throws {
        #expect(try Visibility.evaluate(["$and": [true, ["$state": "/ok"]]], in: ResolutionContext(state: ["ok": true])) == true)
        #expect(try Visibility.evaluate(["$and": [false, ["$state": "/ok"]]], in: ResolutionContext(state: ["ok": true])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › $or condition")
struct VisibilityOrTests {
    static let cond: JSONValue = ["$or": [["$state": "/isAdmin"], ["$state": "/isModerator"]]]

    @Test("returns true when at least one child is true")
    func trueWhenOneTrue() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": false, "isModerator": true])) == true)
    }

    @Test("returns true when all children are true")
    func trueWhenAllTrue() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": true, "isModerator": true])) == true)
    }

    @Test("returns false when all children are false")
    func falseWhenAllFalse() throws {
        #expect(try Visibility.evaluate(Self.cond, in: ResolutionContext(state: ["isAdmin": false, "isModerator": false])) == false)
    }

    @Test("supports nested arrays (AND inside OR)")
    func nestedArrayInsideOr() throws {
        // OR( AND(isAdmin, tab=settings), isSuperUser )
        let cond: JSONValue = [
            "$or": [
                [["$state": "/isAdmin"], ["$state": "/tab", "eq": "settings"]],
                ["$state": "/isSuperUser"],
            ],
        ]
        #expect(
            try Visibility.evaluate(
                cond,
                in: ResolutionContext(state: ["isAdmin": true, "tab": "settings", "isSuperUser": false])
            ) == true
        )
        #expect(
            try Visibility.evaluate(
                cond,
                in: ResolutionContext(state: ["isAdmin": false, "tab": "settings", "isSuperUser": false])
            ) == false
        )
    }

    @Test("supports booleans inside $or")
    func booleansInsideOr() throws {
        #expect(try Visibility.evaluate(["$or": [false, ["$state": "/ok"]]], in: ResolutionContext(state: ["ok": true])) == true)
        #expect(try Visibility.evaluate(["$or": [false, false]], in: ResolutionContext(state: [:])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › $item conditions")
struct VisibilityItemTests {
    @Test("$item truthiness check")
    func itemTruthiness() throws {
        #expect(try Visibility.evaluate(["$item": "active"], in: ResolutionContext(state: [:], repeatItem: ["active": true])) == true)
    }

    @Test("$item falsy check")
    func itemFalsy() throws {
        #expect(try Visibility.evaluate(["$item": "active"], in: ResolutionContext(state: [:], repeatItem: ["active": false])) == false)
    }

    @Test("$item equality check")
    func itemEquality() throws {
        let cond: JSONValue = ["$item": "status", "eq": "done"]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: [:], repeatItem: ["status": "done"])) == true)
    }

    @Test("$item equality check fails")
    func itemEqualityFails() throws {
        let cond: JSONValue = ["$item": "status", "eq": "done"]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: [:], repeatItem: ["status": "pending"])) == false)
    }

    @Test("$item root reference")
    func itemRootReference() throws {
        let cond: JSONValue = ["$item": "", "eq": "hello"]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: [:], repeatItem: "hello")) == true)
    }

    @Test("$item with not")
    func itemWithNot() throws {
        let cond: JSONValue = ["$item": "active", "not": true]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: [:], repeatItem: ["active": true])) == false)
    }

    @Test("$item returns false when no repeat scope")
    func itemFalseWithoutRepeatScope() throws {
        #expect(try Visibility.evaluate(["$item": "x"], in: ResolutionContext(state: [:])) == false)
    }
}

@Suite("visibility.test.ts › evaluateVisibility › $index conditions")
struct VisibilityIndexTests {
    @Test("$index equality check")
    func indexEquality() throws {
        #expect(try Visibility.evaluate(["$index": true, "eq": 0], in: ResolutionContext(state: [:], repeatIndex: 0)) == true)
    }

    @Test("$index equality check fails")
    func indexEqualityFails() throws {
        #expect(try Visibility.evaluate(["$index": true, "eq": 0], in: ResolutionContext(state: [:], repeatIndex: 1)) == false)
    }

    @Test("$index gt check")
    func indexGt() throws {
        #expect(try Visibility.evaluate(["$index": true, "gt": 2], in: ResolutionContext(state: [:], repeatIndex: 5)) == true)
    }

    @Test("$index truthiness")
    func indexTruthiness() throws {
        #expect(try Visibility.evaluate(["$index": true], in: ResolutionContext(state: [:], repeatIndex: 3)) == true)
    }

    @Test("$index zero is falsy")
    func indexZeroFalsy() throws {
        #expect(try Visibility.evaluate(["$index": true], in: ResolutionContext(state: [:], repeatIndex: 0)) == false)
    }

    @Test("$index with not")
    func indexWithNot() throws {
        let cond: JSONValue = ["$index": true, "eq": 0, "not": true]
        #expect(try Visibility.evaluate(cond, in: ResolutionContext(state: [:], repeatIndex: 1)) == true)
    }
}

@Suite("visibility.test.ts › visibility helper")
struct VisibilityHelperTests {
    @Test("always is true")
    func alwaysIsTrue() {
        #expect(Visibility.always == true)
    }

    @Test("never is false")
    func neverIsFalse() {
        #expect(Visibility.never == false)
    }

    @Test("when creates a $state condition")
    func whenCreatesStateCondition() {
        #expect(Visibility.when("/user/isAdmin") == ["$state": "/user/isAdmin"])
    }

    @Test("unless creates a negated $state condition")
    func unlessCreatesNegatedCondition() {
        #expect(Visibility.unless("/form/hasErrors") == ["$state": "/form/hasErrors", "not": true])
    }

    @Test("eq creates an equality condition")
    func eqCreatesCondition() {
        #expect(Visibility.eq("/tab", "home") == ["$state": "/tab", "eq": "home"])
    }

    @Test("neq creates an inequality condition")
    func neqCreatesCondition() {
        #expect(Visibility.neq("/role", "guest") == ["$state": "/role", "neq": "guest"])
    }

    @Test("gt creates a greater-than condition")
    func gtCreatesCondition() {
        #expect(Visibility.gt("/count", 5) == ["$state": "/count", "gt": 5])
    }

    @Test("gte creates a gte condition")
    func gteCreatesCondition() {
        #expect(Visibility.gte("/count", 5) == ["$state": "/count", "gte": 5])
    }

    @Test("lt creates a less-than condition")
    func ltCreatesCondition() {
        #expect(Visibility.lt("/count", 5) == ["$state": "/count", "lt": 5])
    }

    @Test("lte creates a lte condition")
    func lteCreatesCondition() {
        #expect(Visibility.lte("/count", 5) == ["$state": "/count", "lte": 5])
    }

    @Test("and returns an $and wrapper")
    func andReturnsWrapper() {
        let result = Visibility.and(Visibility.when("/isAdmin"), Visibility.eq("/tab", "home"))
        #expect(result == ["$and": [["$state": "/isAdmin"], ["$state": "/tab", "eq": "home"]]])
    }

    @Test("or returns an $or wrapper")
    func orReturnsWrapper() {
        let result = Visibility.or(Visibility.when("/isAdmin"), Visibility.when("/isModerator"))
        #expect(result == ["$or": [["$state": "/isAdmin"], ["$state": "/isModerator"]]])
    }
}

@Suite("visibility.test.ts › splitRepeatVisibility")
struct VisibilitySplitRepeatTests {
    @Test("passes through pure container conditions")
    func passesThroughContainerConditions() throws {
        let cond: JSONValue = ["$state": "/show", "eq": true]
        #expect(try Visibility.splitRepeatVisibility(cond) == (container: cond, itemFilter: .undefined))
        #expect(try Visibility.splitRepeatVisibility(.undefined) == (container: .undefined, itemFilter: .undefined))
        #expect(try Visibility.splitRepeatVisibility(true) == (container: true, itemFilter: .undefined))
    }

    @Test("routes pure item conditions to the item filter")
    func routesItemConditionsToFilter() throws {
        let cond: JSONValue = ["$item": "status", "eq": "todo"]
        #expect(try Visibility.splitRepeatVisibility(cond) == (container: .undefined, itemFilter: cond))
    }

    @Test("partitions AND-composed mixed conditions")
    func partitionsAndComposedConditions() throws {
        let state: JSONValue = ["$state": "/show", "eq": true]
        let item: JSONValue = ["$item": "status", "eq": "todo"]
        for cond: JSONValue in [[state, item], ["$and": [state, item]]] {
            #expect(try Visibility.splitRepeatVisibility(cond) == (container: ["$and": [state]], itemFilter: ["$and": [item]]))
        }
    }

    @Test("keeps mixed $or entirely as an item filter")
    func keepsMixedOrAsItemFilter() throws {
        let cond: JSONValue = [
            "$or": [
                ["$state": "/all", "eq": true],
                ["$item": "pinned", "eq": true],
            ],
        ]
        #expect(try Visibility.splitRepeatVisibility(cond) == (container: .undefined, itemFilter: cond))
    }
}

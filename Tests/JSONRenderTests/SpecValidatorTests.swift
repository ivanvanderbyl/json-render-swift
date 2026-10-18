import Testing
@testable import JSONRender

// Ports upstream tests from packages/core/src/spec-validator.test.ts (json-render 0.21.1).

@Suite("spec-validator.test.ts › validateSpec")
struct SpecValidatorTests {
    @Test("returns valid for a correct spec")
    func returnsValidForCorrectSpec() throws {
        let spec = Spec(root: "root", elements: [
            "root": ["type": "Stack", "props": [:], "children": ["child1"]],
            "child1": ["type": "Text", "props": ["text": "hello"], "children": []],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(result.valid)
        #expect(result.issues.isEmpty)
    }

    @Test("detects missing root")
    func detectsMissingRoot() throws {
        // Upstream casts this literal with `as Spec`, so it is built from the plain object.
        let spec = Spec([
            "root": "",
            "elements": ["a": ["type": "T", "props": [:], "children": []]],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "missing_root" })
    }

    @Test("detects root_not_found")
    func detectsRootNotFound() throws {
        let spec = Spec(root: "missing", elements: [
            "a": ["type": "T", "props": [:], "children": []],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "root_not_found" })
    }

    @Test("detects empty spec")
    func detectsEmptySpec() throws {
        let spec = Spec(root: "r", elements: [:])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "empty_spec" })
    }

    @Test("detects missing_child")
    func detectsMissingChild() throws {
        let spec = Spec(root: "root", elements: [
            "root": ["type": "Stack", "props": [:], "children": ["nonexistent"]],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "missing_child" })
    }

    @Test("detects missing children in named slots")
    func detectsMissingChildrenInNamedSlots() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Layout",
                "props": [:],
                "slots": ["header": ["nonexistent"]],
            ],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        #expect(result.issues.contains {
            $0.code == "missing_child" && $0.elementKey == "root" && $0.message.contains(#"slot "header""#)
        })
    }

    @Test("detects visible_in_props")
    func detectsVisibleInProps() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Text",
                "props": ["visible": ["$state": "/show"]],
                "children": [],
            ],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "visible_in_props" })
    }

    @Test("detects on_in_props")
    func detectsOnInProps() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Button",
                "props": ["on": ["press": ["action": "doSomething"]]],
                "children": [],
            ],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "on_in_props" })
    }

    @Test("detects repeat_in_props")
    func detectsRepeatInProps() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Stack",
                "props": ["repeat": ["statePath": "/items"]],
                "children": [],
            ],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "repeat_in_props" })
    }

    @Test("detects watch_in_props")
    func detectsWatchInProps() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Select",
                "props": [
                    "watch": [
                        "/form/country": ["action": "loadCities"],
                    ],
                ],
                "children": [],
            ],
        ])
        let result = try SpecValidator.validate(spec)
        #expect(!result.valid)
        let watchIssue = result.issues.first { $0.code == "watch_in_props" }
        #expect(watchIssue != nil)
        #expect(watchIssue?.elementKey == "root")
    }

    @Test("detects orphaned elements when checkOrphans is true")
    func detectsOrphanedElements() throws {
        let spec = Spec(root: "root", elements: [
            "root": ["type": "Stack", "props": [:], "children": []],
            "orphan": ["type": "Text", "props": [:], "children": []],
        ])
        let result = try SpecValidator.validate(spec, checkOrphans: true)
        #expect(result.valid)
        #expect(result.issues.contains { $0.code == "orphaned_element" })
    }

    @Test("treats named slot children as reachable")
    func treatsNamedSlotChildrenAsReachable() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Layout",
                "props": [:],
                "slots": ["header": ["heading"]],
            ],
            "heading": ["type": "Heading", "props": [:]],
        ])
        let result = try SpecValidator.validate(spec, checkOrphans: true)
        #expect(result.valid)
        #expect(result.issues.isEmpty)
    }
}

@Suite("spec-validator.test.ts › repeat validation")
struct SpecValidatorRepeatTests {
    @Test("rejects repeat without children")
    func rejectsRepeatWithoutChildren() throws {
        let result = try SpecValidator.validate(Spec(
            root: "list",
            elements: [
                "list": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/items"],
                    "children": [],
                ],
            ],
            state: ["items": [["id": "1"]]]
        ))
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "repeat_without_children" })
    }

    @Test("rejects repeat over a non-array state value")
    func rejectsRepeatOverNonArray() throws {
        let result = try SpecValidator.validate(Spec(
            root: "list",
            elements: [
                "list": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/items"],
                    "children": ["card"],
                ],
                "card": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["items": ["1": ["title": "x"]]]
        ))
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "repeat_state_mismatch" })
    }

    @Test("rejects repeat over a missing state path when state is provided")
    func rejectsRepeatOverMissingPath() throws {
        let result = try SpecValidator.validate(Spec(
            root: "list",
            elements: [
                "list": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/items"],
                    "children": ["card"],
                ],
                "card": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["other": []]
        ))
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "repeat_state_mismatch" })
    }

    @Test("accepts a well-formed repeat and skips state checks when no state is provided")
    func acceptsWellFormedRepeat() throws {
        let withState = try SpecValidator.validate(Spec(
            root: "list",
            elements: [
                "list": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/items"],
                    "children": ["card"],
                ],
                "card": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["items": [["id": "1"]]]
        ))
        #expect(withState.valid)
        let runtimeState = try SpecValidator.validate(Spec(
            root: "list",
            elements: [
                "list": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/items"],
                    "children": ["card"],
                ],
                "card": ["type": "Text", "props": [:], "children": []],
            ]
        ))
        #expect(runtimeState.valid)
    }

    @Test("accepts a nested repeat relative to the enclosing item")
    func acceptsNestedRelativeRepeat() throws {
        let result = try SpecValidator.validate(Spec(
            root: "groups",
            elements: [
                "groups": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/groups"],
                    "children": ["subitems"],
                ],
                "subitems": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": ["$item": "subitems"]],
                    "children": ["label"],
                ],
                "label": ["type": "Text", "props": [:], "children": []],
            ],
            state: [
                "groups": [["subitems": [["label": "a"]]]],
            ]
        ))

        #expect(result.valid)
        #expect(result.issues.isEmpty)
    }

    @Test("rejects a relative repeat outside repeat scope")
    func rejectsRelativeRepeatOutsideScope() throws {
        let result = try SpecValidator.validate(Spec(
            root: "items",
            elements: [
                "items": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": ["$item": "items"]],
                    "children": ["label"],
                ],
                "label": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["items": [["label": "root"]]]
        ))

        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "repeat_item_outside_scope" })
    }

    @Test("does not give named slots the repeat scope created by their element")
    func namedSlotsDoNotGetRepeatScope() throws {
        let result = try SpecValidator.validate(Spec(
            root: "items",
            elements: [
                "items": [
                    "type": "Layout",
                    "props": [:],
                    "repeat": ["statePath": "/items"],
                    "children": ["body"],
                    "slots": ["header": ["nested"]],
                ],
                "body": ["type": "Text", "props": [:], "children": []],
                "nested": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": ["$item": "nested"]],
                    "children": ["label"],
                ],
                "label": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["items": [["nested": []]]]
        ))

        #expect(result.issues.contains { $0.code == "repeat_item_outside_scope" })
    }

    @Test("accepts relative repeat structure when the outer sample array is empty")
    func acceptsRelativeRepeatWithEmptyOuterSample() throws {
        let result = try SpecValidator.validate(Spec(
            root: "groups",
            elements: [
                "groups": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/groups"],
                    "children": ["subitems"],
                ],
                "subitems": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": ["$item": "subitems"]],
                    "children": ["label"],
                ],
                "label": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["groups": []]
        ))

        #expect(result.valid)
    }

    @Test("rejects a nested relative repeat that does not resolve to an array")
    func rejectsNestedRelativeRepeatNotArray() throws {
        let result = try SpecValidator.validate(Spec(
            root: "groups",
            elements: [
                "groups": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/groups"],
                    "children": ["subitems"],
                ],
                "subitems": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": ["$item": "/subitems"]],
                    "children": ["label"],
                ],
                "label": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["groups": [["subitems": ["label": "a"]]]]
        ))

        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "repeat_state_mismatch" })
    }

    @Test("does not duplicate repeat issues for the same structural context")
    func doesNotDuplicateRepeatIssues() throws {
        let result = try SpecValidator.validate(Spec(
            root: "root",
            elements: [
                "root": [
                    "type": "Stack",
                    "props": [:],
                    "children": ["left", "right"],
                ],
                "left": [
                    "type": "Stack",
                    "props": [:],
                    "children": ["shared"],
                ],
                "right": [
                    "type": "Stack",
                    "props": [:],
                    "children": ["shared"],
                ],
                "shared": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": ["$item": "items"]],
                    "children": ["label"],
                ],
                "label": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["items": []]
        ))

        #expect(result.issues.filter { $0.code == "repeat_item_outside_scope" }.count == 1)
    }

    @Test("validates a reused repeat separately inside and outside scope")
    func validatesReusedRepeatSeparately() throws {
        let result = try SpecValidator.validate(Spec(
            root: "root",
            elements: [
                "root": [
                    "type": "Stack",
                    "props": [:],
                    "children": ["groups", "shared"],
                ],
                "groups": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/groups"],
                    "children": ["shared"],
                ],
                "shared": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": ["$item": "items"]],
                    "children": ["label"],
                ],
                "label": ["type": "Text", "props": [:], "children": []],
            ],
            state: ["groups": [["items": []]]]
        ))

        #expect(result.issues.filter { $0.code == "repeat_item_outside_scope" }.count == 1)
        #expect(result.issues.filter { $0.code == "repeat_state_mismatch" }.isEmpty)
    }

    @Test("terminates repeat validation for cyclic child graphs")
    func terminatesForCyclicGraphs() throws {
        let result = try SpecValidator.validate(Spec(
            root: "groups",
            elements: [
                "groups": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/groups"],
                    "children": ["items"],
                ],
                "items": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": ["$item": "items"]],
                    "children": ["groups"],
                ],
            ],
            state: ["groups": [["items": []]]]
        ))

        #expect(result.issues.filter { $0.code == "repeat_state_mismatch" }.isEmpty)
    }
}

@Suite("spec-validator.test.ts › visible condition validation")
struct SpecValidatorVisibleConditionTests {
    static func base(_ visible: JSONValue) -> Spec {
        Spec(root: "root", elements: [
            "root": [
                "type": "Text",
                "props": ["text": "hi"],
                "children": [],
                "visible": visible,
            ],
        ])
    }

    @Test("accepts documented forms")
    func acceptsDocumentedForms() throws {
        let forms: [JSONValue] = [
            true,
            false,
            ["$state": "/tab", "eq": "home"],
            ["$item": "status", "eq": "todo"],
            ["$index": true, "lt": 3],
            [
                ["$state": "/a", "eq": 1],
                ["$item": "b", "neq": 2],
            ],
            ["$or": [["$state": "/a", "eq": 1], ["$and": [["$item": "b", "not": true]]]]],
        ]
        for visible in forms {
            #expect(try SpecValidator.validate(Self.base(visible)).valid)
        }
    }

    @Test("rejects conditions mixing $state and $item (silently hidden at runtime)")
    func rejectsMixedStateAndItem() throws {
        let result = try SpecValidator.validate(
            Self.base([["$state": "/tasks", "$item": "status", "eq": "todo"]])
        )
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "invalid_visible" })
    }

    @Test("rejects unknown condition shapes")
    func rejectsUnknownShapes() throws {
        let result = try SpecValidator.validate(Self.base(["when": "/tasks", "is": "todo"]))
        #expect(!result.valid)
        #expect(result.issues.first?.code == "invalid_visible")
    }
}

@Suite("spec-validator.test.ts › autoFixSpec")
struct SpecValidatorAutoFixTests {
    @Test("prunes children references to undefined elements")
    func prunesUndefinedChildren() throws {
        let spec = Spec(root: "root", elements: [
            "root": ["type": "Card", "props": [:], "children": ["text", "ghost"]],
            "text": ["type": "Text", "props": ["text": "hi"], "children": []],
        ])
        let (fixed, fixes, fixDetails) = try SpecValidator.autoFix(spec)
        #expect(fixed.elements["root"]?["children"] == ["text"])
        #expect(fixes == [
            #"Removed reference to undefined element "ghost" from children of "root"."#,
        ])
        #expect(fixDetails == [
            SpecFix(
                message: #"Removed reference to undefined element "ghost" from children of "root"."#,
                lossy: true
            ),
        ])
        #expect(try SpecValidator.validate(fixed).valid)
    }

    @Test("leaves intact children untouched")
    func leavesIntactChildren() throws {
        let spec = Spec(root: "root", elements: [
            "root": ["type": "Card", "props": [:], "children": ["text"]],
            "text": ["type": "Text", "props": ["text": "hi"], "children": []],
        ])
        let (fixed, fixes, _) = try SpecValidator.autoFix(spec)
        #expect(fixed.elements["root"]?["children"] == ["text"])
        #expect(fixes == [])
    }

    @Test("prunes undefined children from named slots")
    func prunesUndefinedSlotChildren() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Layout",
                "props": [:],
                "slots": ["header": ["heading", "ghost"]],
            ],
            "heading": ["type": "Heading", "props": [:]],
        ])
        let (fixed, _, fixDetails) = try SpecValidator.autoFix(spec)
        #expect(fixed.elements["root"]?["slots"] == ["header": ["heading"]])
        #expect(fixDetails.contains(SpecFix(
            message: #"Removed reference to undefined element "ghost" from slot "header" of "root"."#,
            lossy: true
        )))
        #expect(try SpecValidator.validate(fixed).valid)
    }

    @Test("does not prune a repeat container down to zero children")
    func doesNotPruneRepeatToZeroChildren() throws {
        let spec = Spec(
            root: "list",
            elements: [
                "list": [
                    "type": "Stack",
                    "props": [:],
                    "repeat": ["statePath": "/items"],
                    "children": ["ghost"],
                ],
            ],
            state: ["items": [["id": "1"]]]
        )
        let (fixed, _, fixDetails) = try SpecValidator.autoFix(spec)
        #expect(fixed.elements["list"]?["children"] == ["ghost"])
        #expect(fixDetails == [])
        // The real problem (missing template) stays visible to the repair loop.
        let result = try SpecValidator.validate(fixed)
        #expect(!result.valid)
        #expect(result.issues.contains { $0.code == "missing_child" })
    }

    @Test("withholds lossy fixes when options.lossy is false")
    func withholdsLossyFixes() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Card",
                "props": ["visible": true],
                "children": ["ghost"],
            ],
        ])
        let (fixed, _, fixDetails) = try SpecValidator.autoFix(spec, lossy: false)
        #expect(fixed.elements["root"]?["children"] == ["ghost"])
        #expect(fixDetails.allSatisfy { !$0.lossy })
        #expect(fixDetails.count > 0)
    }

    @Test("classifies field relocations as lossless")
    func classifiesRelocationsAsLossless() throws {
        let fixDetails = try SpecValidator.autoFix(Spec(root: "root", elements: [
            "root": [
                "type": "Text",
                "props": ["text": "hi", "visible": true],
                "children": [],
            ],
        ])).fixDetails
        #expect(fixDetails == [
            SpecFix(
                message: #"Moved "visible" from props to element level on "root"."#,
                lossy: false
            ),
        ])
    }

    @Test("moves visible from props to element level")
    func movesVisible() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Text",
                "props": ["text": "hi", "visible": ["$state": "/show"]],
                "children": [],
            ],
        ])
        let (fixed, fixes, _) = try SpecValidator.autoFix(spec)
        #expect(fixed.elements["root"]?["props"]["visible"] == .undefined)
        #expect(fixed.elements["root"]?["visible"] == ["$state": "/show"])
        #expect(fixes.contains { $0.contains("visible") })
    }

    @Test("moves on from props to element level")
    func movesOn() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Button",
                "props": ["label": "OK", "on": ["press": ["action": "submit"]]],
                "children": [],
            ],
        ])
        let (fixed, fixes, _) = try SpecValidator.autoFix(spec)
        #expect(fixed.elements["root"]?["props"]["on"] == .undefined)
        #expect(fixed.elements["root"]?["on"] == ["press": ["action": "submit"]])
        #expect(fixes.contains { $0.contains(#""on""#) })
    }

    @Test("moves repeat from props to element level")
    func movesRepeat() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Stack",
                "props": ["repeat": ["statePath": "/items"]],
                "children": ["child"],
            ],
            "child": ["type": "Text", "props": [:], "children": []],
        ])
        let (fixed, fixes, _) = try SpecValidator.autoFix(spec)
        #expect(fixed.elements["root"]?["props"]["repeat"] == .undefined)
        #expect(fixed.elements["root"]?["repeat"] == ["statePath": "/items"])
        #expect(fixes.contains { $0.contains(#""repeat""#) })
    }

    @Test("moves watch from props to element level")
    func movesWatch() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Select",
                "props": [
                    "label": "Country",
                    "watch": [
                        "/form/country": ["action": "loadCities"],
                    ],
                ],
                "children": [],
            ],
        ])
        let (fixed, fixes, _) = try SpecValidator.autoFix(spec)
        #expect(fixed.elements["root"]?["props"]["watch"] == .undefined)
        #expect(fixed.elements["root"]?["watch"] == [
            "/form/country": ["action": "loadCities"],
        ])
        #expect(fixes.contains { $0.contains(#""watch""#) })
    }

    @Test("returns no fixes for a correct spec")
    func returnsNoFixesForCorrectSpec() throws {
        let spec = Spec(root: "root", elements: [
            "root": [
                "type": "Stack",
                "props": ["direction": "vertical"],
                "children": [],
                "watch": ["/x": ["action": "y"]],
            ],
        ])
        let (_, fixes, _) = try SpecValidator.autoFix(spec)
        #expect(fixes.isEmpty)
    }
}

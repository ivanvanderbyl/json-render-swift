// Ports upstream tests from packages/core/src/actions.test.ts (json-render 0.21.1).
// Suite and test names match the upstream describe and it names.

import Testing
@testable import JSONRender

// actions.test.ts › onSuccess/onError schemas
// Deferred: "keeps params on the onSuccess action form" - ported with the schema module.
// Deferred: "keeps params on the onError action form" - ported with the schema module.

@Suite("actions.test.ts › interpolateString")
struct InterpolateStringTests {
    @Test("interpolates ${path} expressions")
    func interpolatesPathExpressions() {
        let data: JSONValue = ["user": ["name": "Alice"], "count": 5]

        #expect(Actions.interpolate("Hello ${/user/name}!", state: data) == "Hello Alice!")
        #expect(Actions.interpolate("${/user/name} has ${/count} items", state: data) == "Alice has 5 items")
    }

    @Test("returns string unchanged when no variables")
    func returnsUnchangedWithoutVariables() {
        #expect(Actions.interpolate("No vars here", state: [:]) == "No vars here")
    }

    @Test("replaces missing values with empty string")
    func replacesMissingWithEmpty() {
        #expect(Actions.interpolate("Hello ${/missing}!", state: [:]) == "Hello !")
    }

    @Test("handles multiple occurrences of same variable")
    func handlesRepeatedVariable() {
        let data: JSONValue = ["name": "Bob"]
        #expect(Actions.interpolate("${/name} says ${/name}", state: data) == "Bob says Bob")
    }
}

@Suite("actions.test.ts › resolveAction")
struct ResolveActionTests {
    @Test("resolves literal params")
    func resolvesLiteralParams() throws {
        let resolved = try Actions.resolve(
            ActionBinding([
                "action": "navigate",
                "params": ["url": "/home", "count": 5],
            ]),
            state: [:]
        )

        #expect(resolved.action == "navigate")
        #expect(resolved.params["url"] == "/home")
        #expect(resolved.params["count"] == 5)
    }

    @Test("resolves dynamic $state params")
    func resolvesStateParams() throws {
        let data: JSONValue = ["userId": 123, "settings": ["theme": "dark"]]
        let resolved = try Actions.resolve(
            ActionBinding([
                "action": "updateUser",
                "params": [
                    "id": ["$state": "/userId"],
                    "theme": ["$state": "/settings/theme"],
                ],
            ]),
            state: data
        )

        #expect(resolved.params["id"] == 123)
        #expect(resolved.params["theme"] == "dark")
    }

    @Test("passes a resolved dotted email to a form action handler")
    func passesResolvedDottedEmail() throws {
        let state: JSONObject = ["form": ["email": "john.doe@example.com"]]
        let resolved = try Actions.resolve(
            ActionBinding([
                "action": "createCustomer",
                "params": ["email": ["$state": "/form/email"]],
            ]),
            state: .object(state)
        )

        #expect(FormValue.find("email", params: resolved.params, state: state) == "john.doe@example.com")
    }

    @Test("interpolates confirmation messages")
    func interpolatesConfirmation() throws {
        let data: JSONValue = ["user": ["name": "Alice"]]
        let resolved = try Actions.resolve(
            ActionBinding([
                "action": "delete",
                "confirm": [
                    "title": "Delete ${/user/name}",
                    "message": "Are you sure you want to delete ${/user/name}?",
                ],
            ]),
            state: data
        )

        #expect(resolved.confirm["title"] == "Delete Alice")
        #expect(resolved.confirm["message"] == "Are you sure you want to delete Alice?")
    }

    @Test("preserves onSuccess and onError handlers")
    func preservesHandlers() throws {
        let resolved = try Actions.resolve(
            ActionBinding([
                "action": "save",
                "onSuccess": ["navigate": "/success"],
                "onError": ["set": ["error": "$error.message"]],
            ]),
            state: [:]
        )

        #expect(resolved.onSuccess == ["navigate": "/success"])
        #expect(resolved.onError == ["set": ["error": "$error.message"]])
    }
}

@MainActor
@Suite("actions.test.ts › executeAction")
struct ExecuteActionTests {
    /// Records each call, like a `vi.fn()` spy.
    final class Spy<Arguments> { var calls: [Arguments] = [] }

    @Test("calls the handler with resolved params")
    func callsHandlerWithParams() async throws {
        let handler = Spy<JSONObject>()

        try await Actions.execute(ActionExecutionContext(
            action: ResolvedAction(action: "test", params: ["value": 42]),
            handler: { params in
                handler.calls.append(params)
                return .undefined
            },
            setState: { _, _ in }
        ))

        #expect(handler.calls.contains(["value": 42]))
    }

    @Test("handles onSuccess with navigate")
    func onSuccessNavigates() async throws {
        let navigate = Spy<JSONValue>()

        try await Actions.execute(ActionExecutionContext(
            action: ResolvedAction(
                action: "test",
                params: [:],
                onSuccess: ["navigate": "/success"]
            ),
            handler: { _ in .undefined },
            setState: { _, _ in },
            navigate: { path in navigate.calls.append(path) }
        ))

        #expect(navigate.calls.contains("/success"))
    }

    @Test("handles onSuccess with set")
    func onSuccessSetsState() async throws {
        let setState = Spy<(String, JSONValue)>()

        try await Actions.execute(ActionExecutionContext(
            action: ResolvedAction(
                action: "test",
                params: [:],
                onSuccess: ["set": ["saved": true, "message": "Done"]]
            ),
            handler: { _ in .undefined },
            setState: { path, value in setState.calls.append((path, value)) }
        ))

        #expect(setState.calls.contains { $0 == ("saved", true) })
        #expect(setState.calls.contains { $0 == ("message", "Done") })
    }

    @Test("handles onSuccess with action")
    func onSuccessRunsAction() async throws {
        let executeAction = Spy<ActionBinding>()

        try await Actions.execute(ActionExecutionContext(
            action: ResolvedAction(
                action: "test",
                params: [:],
                onSuccess: ["action": "followUp"]
            ),
            handler: { _ in .undefined },
            setState: { _, _ in },
            executeAction: { binding in executeAction.calls.append(binding) }
        ))

        #expect(executeAction.calls.map(\.object).contains(["action": "followUp"]))
    }

    @Test("handles onSuccess with action and params")
    func onSuccessRunsActionWithParams() async throws {
        let executeAction = Spy<ActionBinding>()

        try await Actions.execute(ActionExecutionContext(
            action: ResolvedAction(
                action: "save",
                params: [:],
                onSuccess: ["action": "toast", "params": ["message": "Saved"]]
            ),
            handler: { _ in .undefined },
            setState: { _, _ in },
            executeAction: { binding in executeAction.calls.append(binding) }
        ))

        #expect(executeAction.calls.map(\.object).contains([
            "action": "toast",
            "params": ["message": "Saved"],
        ]))
    }

    @Test("handles onError with set")
    func onErrorSetsState() async throws {
        let setState = Spy<(String, JSONValue)>()
        let error = JavaScriptError.error("Something went wrong")

        try await Actions.execute(ActionExecutionContext(
            action: ResolvedAction(
                action: "test",
                params: [:],
                onError: ["set": ["error": "$error.message"]]
            ),
            handler: { _ in throw error },
            setState: { path, value in setState.calls.append((path, value)) }
        ))

        #expect(setState.calls.contains { $0 == ("error", "Something went wrong") })
    }

    @Test("handles onError with action")
    func onErrorRunsAction() async throws {
        let executeAction = Spy<ActionBinding>()
        let error = JavaScriptError.error("Failed")

        try await Actions.execute(ActionExecutionContext(
            action: ResolvedAction(
                action: "test",
                params: [:],
                onError: ["action": "handleError"]
            ),
            handler: { _ in throw error },
            setState: { _, _ in },
            executeAction: { binding in executeAction.calls.append(binding) }
        ))

        #expect(executeAction.calls.map(\.object).contains(["action": "handleError"]))
    }

    @Test("handles onError with action and params")
    func onErrorRunsActionWithParams() async throws {
        let executeAction = Spy<ActionBinding>()
        let error = JavaScriptError.error("Failed")

        try await Actions.execute(ActionExecutionContext(
            action: ResolvedAction(
                action: "save",
                params: [:],
                onError: ["action": "toast", "params": ["message": "Save failed"]]
            ),
            handler: { _ in throw error },
            setState: { _, _ in },
            executeAction: { binding in executeAction.calls.append(binding) }
        ))

        #expect(executeAction.calls.map(\.object).contains([
            "action": "toast",
            "params": ["message": "Save failed"],
        ]))
    }

    @Test("re-throws error when no onError handler")
    func rethrowsWithoutOnError() async {
        let error = JavaScriptError.error("Unhandled")

        await #expect(throws: JavaScriptError.error("Unhandled")) {
            try await Actions.execute(ActionExecutionContext(
                action: ResolvedAction(action: "test", params: [:]),
                handler: { _ in throw error },
                setState: { _, _ in }
            ))
        }
    }
}

@Suite("actions.test.ts › actionBinding helper › simple")
struct ActionBindingSimpleTests {
    @Test("creates binding with action only")
    func createsWithActionOnly() {
        let a = ActionBinding.simple("navigate")

        #expect(a.action == "navigate")
        #expect(a.params == .undefined)
    }

    @Test("creates binding with params")
    func createsWithParams() {
        let a = ActionBinding.simple("navigate", params: ["url": "/home"])

        #expect(a.action == "navigate")
        #expect(a.params == ["url": "/home"])
    }
}

@Suite("actions.test.ts › actionBinding helper › withConfirm")
struct ActionBindingWithConfirmTests {
    @Test("creates binding with confirmation")
    func createsWithConfirmation() {
        let a = ActionBinding.withConfirm("delete", confirm: [
            "title": "Confirm",
            "message": "Are you sure?",
        ])

        #expect(a.action == "delete")
        #expect(a.confirm == [
            "title": "Confirm",
            "message": "Are you sure?",
        ])
    }

    @Test("creates binding with confirmation and params")
    func createsWithConfirmationAndParams() {
        let a = ActionBinding.withConfirm(
            "delete",
            confirm: ["title": "Delete", "message": "Delete item?"],
            params: ["id": 123]
        )

        #expect(a.action == "delete")
        #expect(a.params == ["id": 123])
        #expect(a.confirm["title"] == "Delete")
    }
}

@Suite("actions.test.ts › actionBinding helper › withSuccess")
struct ActionBindingWithSuccessTests {
    @Test("creates binding with navigate success handler")
    func createsWithNavigateSuccess() {
        let a = ActionBinding.withSuccess("save", onSuccess: ["navigate": "/success"])

        #expect(a.action == "save")
        #expect(a.onSuccess == ["navigate": "/success"])
    }

    @Test("creates binding with set success handler")
    func createsWithSetSuccess() {
        let a = ActionBinding.withSuccess("save", onSuccess: ["set": ["saved": true]])

        #expect(a.onSuccess == ["set": ["saved": true]])
    }

    @Test("creates binding with success handler and params")
    func createsWithSuccessAndParams() {
        let a = ActionBinding.withSuccess(
            "save",
            onSuccess: ["navigate": "/done"],
            params: ["data": "test"]
        )

        #expect(a.params == ["data": "test"])
        #expect(a.onSuccess == ["navigate": "/done"])
    }
}

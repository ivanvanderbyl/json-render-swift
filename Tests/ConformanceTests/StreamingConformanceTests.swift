import Foundation
import Testing
@testable import JSONRender

/// Streaming against upstream goldens (Conformance/corpus/streaming.json).
@MainActor
@Suite("Conformance: streaming")
struct StreamingConformanceTests {
    @Test(arguments: Golden.cases("streaming"))
    func matchesUpstream(_ golden: GoldenCase) async throws {
        let input = Tagged.decode(golden.input)
        let actual: JSONValue
        switch input["op"].stringValue {
        case "parseLine":
            actual = Tagged.capture { SpecStream.parseLine(input["line"].stringValue ?? "").map { .object($0.object) } ?? .null }
        case "applySpec":
            var spec = Spec(input["spec"].objectValue ?? [:])
            var steps: [JSONValue] = []
            for patch in input["patches"].arrayValue ?? [] {
                do {
                    try spec.apply(JSONPatch(patch.objectValue ?? [:]))
                    steps.append(["value": Tagged.encode(.object(spec.object))])
                } catch {
                    steps.append(["threw": .string(String(describing: error)), "partial": Tagged.encode(.object(spec.object))])
                    break
                }
            }
            actual = .array(JSONArray(steps))
        case "compile":
            actual = Tagged.capture { .object(try SpecStream.compile(input["stream"].stringValue ?? "", initial: input["initial"].objectValue ?? [:])) }
        case "compiler":
            let compiler = SpecStreamCompiler(initial: input["initial"].objectValue ?? [:])
            let pushes: [JSONValue] = (input["chunks"].arrayValue ?? []).map { chunk in
                Tagged.capture {
                    let (result, newPatches) = try compiler.push(chunk.stringValue ?? "")
                    return ["result": .object(result), "newPatches": .array(JSONArray(newPatches.map { .object($0.object) }))]
                }
            }
            let result = Tagged.capture { .object(try compiler.result()) }
            actual = [
                "pushes": .array(JSONArray(pushes)),
                "result": result,
                "patches": Tagged.encode(.array(JSONArray(compiler.patches.map { .object($0.object) }))),
            ]
        case "mixed":
            var events: [JSONValue] = []
            let parser = MixedStreamParser(
                onPatch: { events.append(["patch": Tagged.encode(.object($0.object))]) },
                onText: { events.append(["text": .string($0)]) }
            )
            for chunk in input["chunks"].arrayValue ?? [] { parser.push(chunk.stringValue ?? "") }
            if input["flush"] != false { parser.flush() }
            actual = .array(JSONArray(events))
        case "transform":
            let transform = JSONRenderTransform()
            var output: [JSONObject] = []
            for chunk in input["chunks"].arrayValue ?? [] { output += transform.transform(chunk.objectValue ?? [:]) }
            output += transform.finish()
            actual = ["value": Tagged.encode(.array(JSONArray(output.map(JSONValue.object))))]
        case "nested":
            actual = Tagged.capture { .object(Spec(nested: input["nested"].objectValue ?? [:]).object) }
        case "specFromParts":
            actual = Tagged.capture { try MessageParts.spec(from: (input["parts"].arrayValue ?? []).compactMap(\.objectValue)).map { .object($0.object) } ?? .null }
        case "textFromParts":
            actual = Tagged.capture { .string(MessageParts.text(from: (input["parts"].arrayValue ?? []).compactMap(\.objectValue))) }
        case "flatToTree":
            actual = Tagged.capture { .object(Spec(flatElements: (input["elements"].arrayValue ?? []).compactMap(\.objectValue)).object) }
        case "uiStream":
            actual = await uiStream(input)
        default:
            Issue.record("unknown op")
            return
        }
        withDivergence(golden) {
            #expect(Tagged.matches(golden.output, actual), "upstream \(golden.output)\nSwift    \(actual)")
        }
    }

    /// Drives ``UIStream`` with the scripted responses the upstream harness
    /// serves, recording its state once it has handled each chunk.
    private func uiStream(_ input: JSONValue) async -> JSONValue {
        let server = ScriptedServer(input)
        let messages = MessageRecorder()
        var completed: [JSONValue] = []
        var errors: [JSONValue] = []
        let stream = UIStream(
            api: URL(string: "/stream")!,
            fetch: { request in try await server.respond(to: request) },
            validate: input["validate"] == true,
            maxRetries: input["maxRetries"].numberValue.map { Int($0) } ?? 5,
            onComplete: { completed.append(Tagged.encode(.object($0.object))) },
            onError: { errors.append(Actions.message(of: $0)) }
        )
        func snapshot() -> JSONValue {
            [
                "spec": stream.spec.map { Tagged.encode(.object($0.object)) } ?? .null,
                "rawLines": .array(JSONArray(stream.rawLines.map(JSONValue.string))),
                "isStreaming": .bool(stream.isStreaming),
                "error": stream.error.map { Actions.message(of: $0) } ?? .null,
            ]
        }
        let steps: [JSONValue] = await messages.record {
            let context = input["context"].objectValue
            let sending = Task {
                await stream.send("prompt", context: context)
                server.finished = true
            }
            await server.settle()
            var steps = [snapshot()]
            while let response = server.nextOpened() {
                for chunk in response.chunks {
                    response.deliver(chunk)
                    await server.settle()
                    steps.append(snapshot())
                }
                if response.stops {
                    stream.stop()
                    await server.settle()
                    steps.append(snapshot())
                    break
                }
                response.close()
                await server.settle()
                steps.append(snapshot())
            }
            await sending.value
            steps.append(snapshot())
            return steps
        }
        return [
            "steps": .array(JSONArray(steps)),
            "completed": .array(JSONArray(completed)),
            "errors": .array(JSONArray(errors)),
            "requests": .array(JSONArray(server.requests)),
            "messages": messages.encoded,
        ]
    }
}

/// Serves the scripted responses of a `uiStream` corpus case, one per request.
@MainActor
private final class ScriptedServer {
    /// One streamed body. ``UIStream`` pulls a chunk at a time; a pull that
    /// finds nothing waits until the test delivers or closes, or the reading
    /// task is cancelled.
    final class Body: @unchecked Sendable {
        let chunks: [Data]
        let stops: Bool
        private let lock = NSLock()
        private var queued: [Data?] = []
        private var waiting: CheckedContinuation<Data?, Never>?

        init(_ response: JSONValue) {
            chunks = (response["chunks"].arrayValue ?? []).map { chunk in
                if case let .string(text) = chunk { return Data(text.utf8) }
                return Data((chunk["bytes"].arrayValue ?? []).map { UInt8($0.numberValue ?? 0) })
            }
            stops = response["stop"] == true
        }

        var isWaiting: Bool { lock.withLock { waiting != nil } }

        func deliver(_ chunk: Data) { push(chunk) }
        func close() { push(nil) }

        private func push(_ chunk: Data?) {
            let waiter: CheckedContinuation<Data?, Never>? = lock.withLock {
                guard let waiting else {
                    queued.append(chunk)
                    return nil
                }
                self.waiting = nil
                return waiting
            }
            waiter?.resume(returning: chunk)
        }

        func next() async -> Data? {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    let ready: Data?? = lock.withLock {
                        if !queued.isEmpty { return .some(queued.removeFirst()) }
                        if Task.isCancelled { return .some(nil) }
                        waiting = continuation
                        return .none
                    }
                    if let ready { continuation.resume(returning: ready) }
                }
            } onCancel: {
                let waiter: CheckedContinuation<Data?, Never>? = lock.withLock {
                    defer { waiting = nil }
                    return waiting
                }
                waiter?.resume(returning: nil)
            }
        }
    }

    private let responses: [JSONValue]
    private var opened: [Body] = []
    private var newest: Body?
    private(set) var requests: [JSONValue] = []
    var finished = false

    init(_ input: JSONValue) {
        responses = input["responses"].arrayValue.map(Array.init) ?? [[
            "status": input["status"], "errorBody": input["errorBody"],
            "rawErrorBody": input["rawErrorBody"], "chunks": input["chunks"],
        ]]
    }

    func respond(to request: URLRequest) async throws -> UIStreamResponse {
        let body = request.httpBody.flatMap { try? JSONValue(parsing: $0) } ?? .undefined
        requests.append([
            "url": .string(request.url?.absoluteString ?? ""),
            "method": .string(request.httpMethod ?? ""),
            "headers": .object((request.allHTTPHeaderFields ?? [:]).reduce(into: JSONObject()) { $0[$1.key] = .string($1.value) }),
            "body": Tagged.encode(body),
        ])
        let response = requests.count <= responses.count ? responses[requests.count - 1] : ["chunks": []]
        if case let .number(status) = response["status"], status != 200 {
            let text = response["rawErrorBody"].stringValue
                ?? (response["errorBody"].isUndefined ? [:] : response["errorBody"]).stringified() ?? ""
            return UIStreamResponse(statusCode: Int(status), body: AsyncThrowingStream { continuation in
                continuation.yield(Data(text.utf8))
                continuation.finish()
            })
        }
        let streamed = Body(response)
        opened.append(streamed)
        newest = streamed
        return UIStreamResponse(statusCode: 200, body: AsyncThrowingStream(unfolding: { await streamed.next() }))
    }

    func nextOpened() -> Body? { opened.isEmpty ? nil : opened.removeFirst() }

    /// Waits until the stream cannot go on without the test: it is waiting
    /// on the newest body, or the send has finished.
    func settle() async {
        for attempt in 0..<20_000 {
            if finished || newest?.isWaiting == true { return }
            if attempt.isMultiple(of: 100) {
                try? await Task.sleep(for: .milliseconds(1))
            } else {
                await Task.yield()
            }
        }
        Issue.record("the stream did not settle")
    }
}

/// createStateStore sequences (Conformance/corpus/state-store.json).
@MainActor
@Suite("Conformance: state store")
struct StateStoreConformanceTests {
    @Test(arguments: Golden.cases("state-store"))
    func matchesUpstream(_ golden: GoldenCase) throws {
        let input = Tagged.decode(golden.input)
        let store = MemoryStateStore(input["initial"].objectValue ?? [:])
        var notifications = 0
        _ = store.subscribe { notifications += 1 }
        var outputs: [JSONValue] = []
        for step in input["steps"].arrayValue ?? [] {
            let before = store.snapshot
            let count = notifications
            let result = Tagged.capture {
                switch step["op"].stringValue {
                case "set": store.set(step["path"].stringValue ?? "", step["value"]); return .undefined
                case "update": store.update(step["updates"].objectValue ?? [:]); return .undefined
                default: return store.get(step["path"].stringValue ?? "")
                }
            }
            let after = store.snapshot
            let shared = before.keys.filter { after.hasKey($0) && (after[$0] ?? .undefined).strictEquals(before[$0] ?? .undefined) }
            outputs.append([
                "result": result,
                "notified": .number(Double(notifications - count)),
                "snapshotChanged": .bool(!before.isIdentical(to: after)),
                "sharedKeys": .array(JSONArray(shared.map(JSONValue.string))),
                "snapshot": Tagged.encode(.object(after)),
            ])
        }
        #expect(Tagged.matches(golden.output, .array(JSONArray(outputs))), "upstream \(golden.output)\nSwift    \(outputs)")
    }
}

/// resolveAction, interpolateString, actionBinding and executeAction
/// (Conformance/corpus/actions.json).
@MainActor
@Suite("Conformance: actions")
struct ActionConformanceTests {
    @Test(arguments: Golden.cases("actions"))
    func matchesUpstream(_ golden: GoldenCase) async throws {
        let input = Tagged.decode(golden.input)
        let actual: JSONValue
        func encode(_ resolved: ResolvedAction) -> JSONValue {
            ["action": resolved.action, "params": .object(resolved.params), "confirm": resolved.confirm, "onSuccess": resolved.onSuccess, "onError": resolved.onError]
        }
        switch input["op"].stringValue {
        case "resolve":
            actual = Tagged.capture { encode(try Actions.resolve(ActionBinding(input["binding"].objectValue ?? [:]), state: input["state"].isUndefined ? [:] : input["state"])) }
        case "interpolate":
            actual = Tagged.capture { .string(Actions.interpolate(input["template"].stringValue ?? "", state: input["state"].isUndefined ? [:] : input["state"])) }
        case "builder":
            let args = input["args"].arrayValue ?? []
            let name = args.first?.stringValue ?? ""
            let binding: ActionBinding = switch input["builder"].stringValue {
            case "withConfirm": .withConfirm(name, confirm: args[1].objectValue ?? [:], params: args.count > 2 ? args[2].objectValue : nil)
            case "withSuccess": .withSuccess(name, onSuccess: args[1].objectValue ?? [:], params: args.count > 2 ? args[2].objectValue : nil)
            default: .simple(name, params: args.count > 1 ? args[1].objectValue : nil)
            }
            actual = ["value": Tagged.encode(.object(binding.object))]
        case "execute":
            var calls: [JSONValue] = []
            let action = input["action"]
            let behaviour = input["handler"]
            let resolved = ResolvedAction(
                action: action["action"], params: action["params"].objectValue ?? [:],
                confirm: action["confirm"], onSuccess: action["onSuccess"], onError: action["onError"]
            )
            let rejects = input["executeActionRejects"] == true
            let navigate: @MainActor (JSONValue) -> Void = { path in calls.append(["fn": "navigate", "path": path]) }
            let executeAction: @MainActor (ActionBinding) async throws -> Void = { binding in
                calls.append(["fn": "executeAction", "binding": .object(binding.object)])
                if rejects { throw JavaScriptError.error("follow-up failed") }
            }
            let context = ActionExecutionContext(
                action: resolved,
                handler: { params in
                    calls.append(["fn": "handler", "params": .object(params)])
                    if case let .string(message) = behaviour["reject"] { throw JavaScriptError.error(message) }
                    return behaviour["resolve"]
                },
                setState: { path, value in calls.append(["fn": "setState", "path": .string(path), "value": value]) },
                navigate: input["navigate"] == true ? navigate : nil,
                executeAction: input["executeAction"] == true ? executeAction : nil
            )
            do {
                try await Actions.execute(context)
                actual = ["calls": Tagged.encode(.array(JSONArray(calls))), "outcome": "resolved"]
            } catch {
                actual = ["calls": Tagged.encode(.array(JSONArray(calls))), "outcome": "rejected", "error": Actions.message(of: error)]
            }
        default:
            Issue.record("unknown op")
            return
        }
        withDivergence(golden) {
            #expect(Tagged.matches(golden.output, actual), "upstream \(golden.output)\nSwift    \(actual)")
        }
    }
}

import Foundation
import Observation

/// What a ``UIStream`` fetch returns: the HTTP status and the body as it arrives.
public struct UIStreamResponse: Sendable {
    public var statusCode: Int
    public var body: AsyncThrowingStream<Data, any Error>

    public init(statusCode: Int, body: AsyncThrowingStream<Data, any Error>) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// A failure ``UIStream`` reports. The descriptions are upstream's messages.
public enum UIStreamError: Error, Equatable, LocalizedError {
    /// The server answered with a status outside 200 to 299. The message is
    /// the body's `message` or `error` member, or "HTTP error: <status>".
    case http(status: Int, message: String)
    /// Validation still found errors after the last repair attempt.
    case validationFailed(retries: Int, issues: String)

    public var errorDescription: String? {
        switch self {
        case let .http(_, message): message
        case let .validationFailed(retries, issues): "Spec validation failed after \(retries) retries:\n\(issues)"
        }
    }
}

/// Builds a spec from a streamed JSONL response, like `useUIStream` from
/// `@json-render/react-native`.
///
/// ``send(_:context:)`` posts `{ prompt, context, currentSpec }` to the API
/// and applies each JSONL patch line to ``spec`` as it arrives. With
/// `validate` on, a malformed line stops the stream and asks the server to
/// continue, and after the stream the spec is auto-fixed and validated, with
/// repair prompts for any remaining errors, up to `maxRetries` times.
@MainActor
@Observable
public final class UIStream {
    public typealias Fetch = @Sendable (URLRequest) async throws -> UIStreamResponse

    /// The spec built so far, or `nil` before the first send.
    public private(set) var spec: Spec?
    public private(set) var isStreaming = false
    public private(set) var error: (any Error)?
    /// The non-blank lines the current request has received, as sent.
    public private(set) var rawLines: [String] = []

    private let api: URL
    private let fetch: Fetch
    private let validate: Bool
    private let maxRetries: Int
    private let onComplete: ((Spec) -> Void)?
    private let onError: ((any Error) -> Void)?
    @ObservationIgnored private var current: Task<Void, Never>?

    /// - Parameter fetch: Performs the request. Defaults to `URLSession.shared`.
    public init(
        api: URL,
        fetch: Fetch? = nil,
        validate: Bool = false,
        maxRetries: Int = 5,
        onComplete: ((Spec) -> Void)? = nil,
        onError: ((any Error) -> Void)? = nil
    ) {
        self.api = api
        self.fetch = fetch ?? UIStream.urlSession()
        self.validate = validate
        self.maxRetries = maxRetries
        self.onComplete = onComplete
        self.onError = onError
    }

    /// Streams a new spec. A `previousSpec` in the context that has a root is
    /// the starting point; the request continues from it. A send cancels any
    /// send still running.
    public func send(_ prompt: String, context: JSONObject? = nil) async {
        current?.cancel()
        isStreaming = true
        error = nil
        rawLines = []
        var initial: JSONObject = ["root": "", "elements": [:]]
        if case let .object(previous)? = context?["previousSpec"], previous["root"]?.isTruthy == true {
            initial = previous
            initial["elements"] = .object(Self.spread(previous["elements"] ?? .undefined))
        }
        // Like the hook's synchronous start, the first request's spec is in
        // place before this method suspends.
        spec = Spec(initial)
        let task = Task { await self.run(prompt, context: context, initial: initial) }
        current = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Cancels the running request and keeps the spec built so far.
    public func stop() {
        current?.cancel()
        current = nil
        isStreaming = false
    }

    /// Forgets the spec, error and raw lines.
    public func clear() {
        spec = nil
        error = nil
        rawLines = []
    }

    private struct RequestResult {
        var spec: JSONObject
        var completed: Bool
        var malformedLines: [String]
    }

    private func run(_ prompt: String, context: JSONObject?, initial: JSONObject) async {
        defer { isStreaming = false }
        var currentSpec = initial
        var retriesUsed = 0
        var currentPrompt = prompt
        var currentContext = context
        do {
            while retriesUsed <= maxRetries {
                let result = try await request(currentPrompt, context: currentContext, initial: currentSpec, abortOnMalformed: validate)
                currentSpec = result.spec
                if !result.completed, let malformed = result.malformedLines.last {
                    if retriesUsed >= maxRetries { break }
                    retriesUsed += 1
                    currentContext = continuing(context, from: currentSpec)
                    currentPrompt = """
                    The previous generation contained malformed JSON that could not be parsed. The line was:
                    \(Self.prefix(malformed, units: 500))

                    The current spec state is provided. Continue generating from where you left off. Output ONLY the remaining patches needed to complete the UI.
                    """
                    continue
                }
                if !validate || currentSpec["root"]?.isTruthy != true { break }
                let fixed = try SpecValidator.autoFix(Spec(currentSpec), lossy: retriesUsed >= maxRetries)
                if !fixed.fixDetails.isEmpty {
                    currentSpec = fixed.spec.object
                    spec = fixed.spec
                }
                let validation = try SpecValidator.validate(Spec(currentSpec))
                if validation.valid { break }
                if retriesUsed >= maxRetries { break }
                retriesUsed += 1
                currentContext = continuing(context, from: currentSpec)
                currentPrompt = "FIX THE FOLLOWING ERRORS in the current UI spec. Output ONLY the patches needed to fix these issues, do not recreate the entire UI.\n\n"
                    + SpecValidator.formatIssues(validation.issues)
            }
            if validate, retriesUsed >= maxRetries, currentSpec["root"]?.isTruthy == true {
                let validation = try SpecValidator.validate(Spec(currentSpec))
                if !validation.valid {
                    let failure = UIStreamError.validationFailed(retries: maxRetries, issues: SpecValidator.formatIssues(validation.issues))
                    error = failure
                    onError?(failure)
                    return
                }
            }
            onComplete?(Spec(currentSpec))
        } catch {
            if Self.isCancellation(error) { return }
            self.error = error
            onError?(error)
        }
    }

    private func continuing(_ context: JSONObject?, from spec: JSONObject) -> JSONObject {
        var next = context ?? [:]
        next["previousSpec"] = .object(spec)
        return next
    }

    private func request(_ prompt: String, context: JSONObject?, initial: JSONObject, abortOnMalformed: Bool) async throws -> RequestResult {
        var currentSpec = initial
        spec = Spec(currentSpec)
        var malformedLines: [String] = []

        var body: JSONObject = ["prompt": .string(prompt)]
        if let context { body["context"] = .object(context) }
        body["currentSpec"] = .object(currentSpec)
        var request = URLRequest(url: api)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((JSONValue.object(body).stringified() ?? "").utf8)

        let response = try await fetch(request)
        try Task.checkCancellation()
        guard (200...299).contains(response.statusCode) else {
            throw UIStreamError.http(status: response.statusCode, message: await Self.errorMessage(response))
        }

        var decoder = LineDecoder()
        var aborted = false
        reading: for try await chunk in response.body {
            try Task.checkCancellation()
            var newLines: [String] = []
            for line in decoder.lines(appending: chunk) {
                if !JavaScript.trim(line).isEmpty { newLines.append(line) }
                switch Self.parsePatchLine(line) {
                case let .patch(patch):
                    currentSpec = try Self.applyPatch(patch, to: currentSpec)
                    spec = Spec(currentSpec)
                case .malformed:
                    malformedLines.append(JavaScript.trim(line))
                    if abortOnMalformed {
                        aborted = true
                        break reading
                    }
                case .skipped:
                    break
                }
            }
            if !newLines.isEmpty { rawLines += newLines }
        }
        try Task.checkCancellation()
        if !aborted {
            let rest = decoder.remainder()
            if !JavaScript.trim(rest).isEmpty {
                rawLines.append(rest)
                switch Self.parsePatchLine(rest) {
                case let .patch(patch):
                    currentSpec = try Self.applyPatch(patch, to: currentSpec)
                    spec = Spec(currentSpec)
                case .malformed:
                    malformedLines.append(JavaScript.trim(rest))
                case .skipped:
                    break
                }
            }
        }
        return RequestResult(spec: currentSpec, completed: !aborted, malformedLines: malformedLines)
    }

    /// The message upstream builds from a failed response: the JSON body's
    /// truthy `message`, else its truthy `error`, else "HTTP error: <status>".
    private static func errorMessage(_ response: UIStreamResponse) async -> String {
        let fallback = "HTTP error: \(response.statusCode)"
        var data = Data()
        do {
            for try await chunk in response.body { data.append(chunk) }
            let body = try JSONValue(parsing: String(decoding: data, as: UTF8.self))
            let message = try JavaScript.member("message", of: body)
            if message.isTruthy { return message.javaScriptString }
            let error = try JavaScript.member("error", of: body)
            if error.isTruthy { return error.javaScriptString }
        } catch {}
        return fallback
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? URLError, error.code == .cancelled { return true }
        return false
    }

    /// The default fetch: `URLSession` with the body delivered as it arrives.
    public static func urlSession(_ session: URLSession = .shared) -> Fetch {
        { request in
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            let body = AsyncThrowingStream<Data, any Error> { continuation in
                let reader = Task {
                    do {
                        var buffer = Data()
                        for try await byte in bytes {
                            buffer.append(byte)
                            if byte == 0x0A || buffer.count >= 4096 {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }
                        if !buffer.isEmpty { continuation.yield(buffer) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in reader.cancel() }
            }
            return UIStreamResponse(statusCode: status, body: body)
        }
    }
}

// MARK: - Line parsing

extension UIStream {
    enum ParsedLine: Equatable {
        case patch(JSONValue)
        case skipped
        case malformed
    }

    /// Upstream `parsePatchLine`: blank lines, `//` comments and lines that do
    /// not start with `{` or `[` are skipped. A line that does not parse is
    /// retried with up to three trailing `}` or `]` removed.
    static func parsePatchLine(_ line: String) -> ParsedLine {
        let trimmed = JavaScript.trim(line)
        if trimmed.isEmpty || JavaScript.startsWith(trimmed, "//") { return .skipped }
        guard JavaScript.startsWith(trimmed, "{") || JavaScript.startsWith(trimmed, "[") else { return .skipped }
        if let patch = try? JSONValue(parsing: trimmed) { return .patch(patch) }
        var attempt = Array(trimmed.utf16)
        for removed in 1...3 {
            guard let last = attempt.last, last == UInt16(UInt8(ascii: "}")) || last == UInt16(UInt8(ascii: "]")) else { break }
            attempt.removeLast()
            if let patch = try? JSONValue(parsing: String(decoding: attempt, as: UTF16.self)) {
                Diagnostics.warn("[json-render] Recovered malformed JSONL line by removing \(removed) trailing '\(Character(Unicode.Scalar(last)!))'")
                return .patch(patch)
            }
        }
        return .malformed
    }

    /// `string.slice(0, units)`.
    static func prefix(_ string: String, units: Int) -> String {
        String(decoding: Array(string.utf16.prefix(units)), as: UTF16.self)
    }
}

/// Splits UTF-8 bytes into lines the way the hook does with a streaming
/// `TextDecoder` and `buffer.split("\n")`: a leading byte order mark is
/// dropped, invalid bytes become U+FFFD, and an unfinished character at the
/// very end is discarded.
struct LineDecoder {
    private var pending: [UInt8] = []
    private var atStart = true

    mutating func lines(appending chunk: Data) -> [String] {
        pending.append(contentsOf: chunk)
        if atStart {
            if pending.count < 3, [0xEF, 0xBB, 0xBF].starts(with: pending) { return [] }
            atStart = false
            if pending.starts(with: [0xEF, 0xBB, 0xBF]) { pending.removeFirst(3) }
        }
        var lines: [String] = []
        var start = 0
        for index in pending.indices where pending[index] == 0x0A {
            lines.append(String(decoding: pending[start..<index], as: UTF8.self))
            start = index + 1
        }
        pending.removeFirst(start)
        return lines
    }

    /// What is left after the last newline, without a trailing unfinished character.
    func remainder() -> String {
        String(decoding: pending.dropLast(Self.unfinishedSuffixLength(pending)), as: UTF8.self)
    }

    /// The length of a trailing, valid but incomplete UTF-8 sequence.
    static func unfinishedSuffixLength(_ bytes: [UInt8]) -> Int {
        var start = bytes.count
        while start > 0, bytes.count - start < 3, bytes[start - 1] & 0xC0 == 0x80 { start -= 1 }
        guard start > 0 else { return 0 }
        let lead = bytes[start - 1]
        let needed: Int
        switch lead {
        case 0xC2...0xDF: needed = 2
        case 0xE0...0xEF: needed = 3
        case 0xF0...0xF4: needed = 4
        default: return 0
        }
        let available = bytes.count - start + 1
        guard available < needed else { return 0 }
        if available >= 2 {
            let second = bytes[start]
            let valid = switch lead {
            case 0xE0: (0xA0...0xBF).contains(second)
            case 0xED: (0x80...0x9F).contains(second)
            case 0xF0: (0x90...0xBF).contains(second)
            case 0xF4: (0x80...0x8F).contains(second)
            default: true
            }
            if !valid { return 0 }
        }
        return available
    }
}

// MARK: - Patches

extension UIStream {
    /// Upstream `applyPatch`: applies one patch to a spec with the hook's own
    /// rules rather than RFC 6902. `/root` and `/state` are set directly,
    /// `/state/...` and `/elements/<key>/...` use `setByPath` and
    /// `removeByPath`, patches to missing elements are ignored, and `test`
    /// and unknown operations change nothing.
    static func applyPatch(_ patch: JSONValue, to spec: JSONObject) throws -> JSONObject {
        var next = spec
        next["elements"] = .object(spread(spec["elements"] ?? .undefined))
        let op = try JavaScript.member("op", of: patch)
        let path = try JavaScript.member("path", of: patch)
        switch op.stringValue {
        case "add", "replace":
            try setSpecValue(&next, path: path, value: try JavaScript.member("value", of: patch))
        case "remove":
            try removeSpecValue(&next, path: path)
        case "move":
            let from = try JavaScript.member("from", of: patch)
            guard from.isTruthy else { break }
            let value = try getSpecValue(next, path: from)
            try removeSpecValue(&next, path: from)
            try setSpecValue(&next, path: path, value: value)
        case "copy":
            let from = try JavaScript.member("from", of: patch)
            guard from.isTruthy else { break }
            try setSpecValue(&next, path: path, value: try getSpecValue(next, path: from))
        default:
            break
        }
        return next
    }

    private static func isPath(_ path: JSONValue, _ literal: String) -> Bool {
        if case let .string(path) = path { return JavaScript.same(path, literal) }
        return false
    }

    /// The path as a string, or the TypeError `path.startsWith(...)` throws.
    private static func pathString(_ path: JSONValue) throws -> String {
        switch path {
        case let .string(path): return path
        case .undefined: throw JavaScriptError.typeError("Cannot read properties of undefined (reading 'startsWith')")
        case .null: throw JavaScriptError.typeError("Cannot read properties of null (reading 'startsWith')")
        default: throw JavaScriptError.typeError("path.startsWith is not a function")
        }
    }

    /// `"/elements/a/b".slice(10).split("/")`.
    private static func elementParts(_ path: String) -> [String] {
        String(decoding: path.utf16.dropFirst("/elements/".utf16.count), as: UTF16.self)
            .split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    /// `path.slice("/state".length)`.
    private static func statePath(_ path: String) -> String {
        String(decoding: path.utf16.dropFirst("/state".utf16.count), as: UTF16.self)
    }

    private static func setSpecValue(_ spec: inout JSONObject, path: JSONValue, value: JSONValue) throws {
        if isPath(path, "/root") {
            spec["root"] = value
            return
        }
        if isPath(path, "/state") {
            spec["state"] = value
            return
        }
        let path = try pathString(path)
        if JavaScript.startsWith(path, "/state/") {
            var state = spec["state"] ?? .undefined
            if !state.isTruthy { state = .object([:]) }
            defer { spec["state"] = state }
            try state.write(value, atPath: statePath(path), mode: .set)
            return
        }
        guard JavaScript.startsWith(path, "/elements/") else { return }
        let parts = elementParts(path)
        let key = parts[0]
        guard !key.isEmpty else { return }
        var elements = spec["elements"]?.objectValue ?? [:]
        defer { spec["elements"] = .object(elements) }
        if parts.count == 1 {
            elements[key] = value
            return
        }
        guard let element = elements[key], element.isTruthy else { return }
        var copy = JSONValue.object(spread(element))
        defer { elements[key] = copy }
        try copy.write(value, atPath: "/" + parts.dropFirst().joined(separator: "/"), mode: .set)
    }

    private static func removeSpecValue(_ spec: inout JSONObject, path: JSONValue) throws {
        if isPath(path, "/state") {
            spec["state"] = .undefined
            return
        }
        let path = try pathString(path)
        if JavaScript.startsWith(path, "/state/"), var state = spec["state"], state.isTruthy {
            defer { spec["state"] = state }
            try state.remove(atPath: statePath(path))
            return
        }
        guard JavaScript.startsWith(path, "/elements/") else { return }
        let parts = elementParts(path)
        let key = parts[0]
        guard !key.isEmpty else { return }
        var elements = spec["elements"]?.objectValue ?? [:]
        defer { spec["elements"] = .object(elements) }
        if parts.count == 1 {
            elements[key] = nil
            return
        }
        guard let element = elements[key], element.isTruthy else { return }
        var copy = JSONValue.object(spread(element))
        defer { elements[key] = copy }
        try copy.remove(atPath: "/" + parts.dropFirst().joined(separator: "/"))
    }

    private static func getSpecValue(_ spec: JSONObject, path: JSONValue) throws -> JSONValue {
        if isPath(path, "/root") { return spec["root"] ?? .undefined }
        return JSONValue.object(spec).value(atPath: try pathString(path))
    }

    /// `{ ...value }`: an object's members, an array's or string's indices,
    /// and nothing for other values.
    static func spread(_ value: JSONValue) -> JSONObject {
        switch value {
        case let .object(object):
            return object
        case let .array(array):
            var object = JSONObject()
            for (index, element) in array.enumerated() { object[String(index)] = element }
            return object
        case let .string(string):
            var object = JSONObject()
            for (index, unit) in string.utf16.enumerated() { object[String(index)] = .string(String(decoding: [unit], as: UTF16.self)) }
            return object
        default:
            return JSONObject()
        }
    }
}

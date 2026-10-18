/// One SpecStream line: an RFC 6902 JSON Patch operation.
///
/// `JSONPatch` keeps the parsed object as written. Upstream accepts any line
/// whose `op` is truthy and whose `path` is present, so the fields are
/// ``JSONValue``s rather than enums.
public struct JSONPatch: Sendable, Equatable {
    public var object: JSONObject

    public init(_ object: JSONObject) { self.object = object }

    public init(op: String, path: String, value: JSONValue = .undefined, from: String? = nil) {
        object = ["op": .string(op), "path": .string(path)]
        if !value.isUndefined { object["value"] = value }
        if let from { object["from"] = .string(from) }
    }

    public var op: JSONValue { object["op"] ?? .undefined }
    public var path: JSONValue { object["path"] ?? .undefined }
    public var value: JSONValue { object["value"] ?? .undefined }
    public var from: JSONValue { object["from"] ?? .undefined }
}

/// SpecStream: json-render's streaming format, one JSON Patch per line.
public enum SpecStream {
    /// Parses one line, like upstream `parseSpecStreamLine`. Returns `nil` for
    /// blank lines, lines that do not start with `{`, invalid JSON, and
    /// objects without a truthy `op` and a `path`.
    public static func parseLine(_ line: String) -> JSONPatch? {
        let trimmed = JavaScript.trim(line)
        guard !trimmed.isEmpty, JavaScript.startsWith(trimmed, "{"),
              case let .object(object)? = try? JSONValue(parsing: trimmed)
        else { return nil }
        let patch = JSONPatch(object)
        return patch.op.isTruthy && !patch.path.isUndefined ? patch : nil
    }

    /// Applies a patch in place, like upstream `applySpecStreamPatch`.
    ///
    /// All six RFC 6902 operations are supported with upstream's streaming
    /// tolerance: `replace` writes even when the target is missing, and
    /// `move` and `copy` without `from` do nothing. A failed `test` throws.
    /// Unknown operations do nothing.
    public static func apply(_ patch: JSONPatch, to object: inout JSONValue) throws {
        guard case let .string(op) = patch.op else { return }
        switch op {
        case "add":
            try write(patch.value, at: patch.path, in: &object, mode: .add)
        case "replace":
            try write(patch.value, at: patch.path, in: &object, mode: .set)
        case "remove":
            try remove(at: patch.path, in: &object)
        case "move":
            guard patch.from.isTruthy else { return }
            let value = try DynamicValue.readState(object, path: patch.from)
            try remove(at: patch.from, in: &object)
            try write(value, at: patch.path, in: &object, mode: .add)
        case "copy":
            guard patch.from.isTruthy else { return }
            let value = try DynamicValue.readState(object, path: patch.from)
            try write(value, at: patch.path, in: &object, mode: .add)
        case "test":
            let actual = try DynamicValue.readState(object, path: patch.path)
            if !deepEqual(actual, patch.value) {
                throw JavaScriptError.error("Test operation failed: value at \"\(patch.path.javaScriptString)\" does not match")
            }
        default:
            return
        }
    }

    /// `addByPath` / `setByPath` with a path straight from the patch.
    private static func write(_ value: JSONValue, at path: JSONValue, in object: inout JSONValue, mode: JSONValue.WriteMode) throws {
        try object.write(value, atPath: try patchPath(path), mode: mode)
    }

    private static func remove(at path: JSONValue, in object: inout JSONValue) throws {
        try object.remove(atPath: try patchPath(path))
    }

    /// The path string `parseJsonPointer` receives. Non-strings fail there.
    private static func patchPath(_ path: JSONValue) throws -> String {
        guard case let .string(path) = path else {
            if path.isNullish {
                throw JavaScriptError.typeError("Cannot read properties of \(path.javaScriptString) (reading 'startsWith')")
            }
            throw JavaScriptError.typeError("path.startsWith is not a function")
        }
        return path
    }

    /// Compiles a whole stream, like upstream `compileSpecStream`.
    public static func compile(_ stream: String, initial: JSONObject = [:]) throws -> JSONObject {
        var result = JSONValue.object(JSONObject(copying: initial))
        for line in JavaScript.splitLines(stream) {
            if let patch = parseLine(line) { try apply(patch, to: &result) }
        }
        return result.objectValue ?? [:]
    }

    /// The deep equality upstream uses for the JSON Patch `test` operation.
    /// Objects compare by key count and then member by member, so a missing
    /// key matches an `undefined` member.
    static func deepEqual(_ a: JSONValue, _ b: JSONValue) -> Bool {
        if a.strictEquals(b) { return true }
        switch (a, b) {
        case let (.array(left), .array(right)):
            return left.count == right.count && zip(left, right).allSatisfy(deepEqual)
        case (.array, .object), (.object, .array):
            return false
        case let (.object(left), .object(right)):
            return left.count == right.count
                && left.allSatisfy { deepEqual($0.value, right[$0.key] ?? .undefined) }
        default:
            return false
        }
    }
}

extension JSONObject {
    /// A shallow copy with new identity, like `{ ...object }`.
    public init(copying other: JSONObject) {
        self.init()
        for (key, value) in other { self[key] = value }
    }
}

extension JavaScript {
    /// `string.split("\n")`.
    static func splitLines(_ string: String) -> [String] {
        Array(string.utf16).split(separator: 0x0A, omittingEmptySubsequences: false).map {
            String(decoding: $0, as: UTF16.self)
        }
    }
}

/// Incrementally compiles SpecStream chunks, like upstream
/// `createSpecStreamCompiler`.
///
/// Each complete line is applied once: a line identical to one already seen
/// is skipped, as upstream does. An incomplete trailing line waits for more
/// text, or for ``result()``.
public final class SpecStreamCompiler {
    private var current: JSONObject
    private var buffer = ""
    private var applied: [JSONPatch] = []
    private var processedLines: Set<ExactKey> = []

    public init(initial: JSONObject = [:]) {
        current = JSONObject(copying: initial)
    }

    /// Adds a chunk of text and applies every complete new line.
    @discardableResult
    public func push(_ chunk: String) throws -> (result: JSONObject, newPatches: [JSONPatch]) {
        buffer += chunk
        var lines = JavaScript.splitLines(buffer)
        buffer = lines.removeLast()

        var newPatches: [JSONPatch] = []
        for line in lines {
            let trimmed = JavaScript.trim(line)
            if trimmed.isEmpty || processedLines.contains(ExactKey(trimmed)) { continue }
            processedLines.insert(ExactKey(trimmed))
            if let patch = SpecStream.parseLine(trimmed) {
                try apply(patch)
                applied.append(patch)
                newPatches.append(patch)
            }
        }
        // Upstream returns a shallow copy so React sees a new reference.
        if !newPatches.isEmpty { current = JSONObject(copying: current) }
        return (current, newPatches)
    }

    /// The compiled result, after applying any complete line still buffered.
    public func result() throws -> JSONObject {
        let trimmed = JavaScript.trim(buffer)
        if !trimmed.isEmpty {
            if let patch = SpecStream.parseLine(buffer), !processedLines.contains(ExactKey(trimmed)) {
                processedLines.insert(ExactKey(trimmed))
                try apply(patch)
                applied.append(patch)
                current = JSONObject(copying: current)
            }
            buffer = ""
        }
        return current
    }

    /// Every patch applied so far, like upstream `getPatches`.
    public var patches: [JSONPatch] { applied }

    /// Starts again from `initial`.
    public func reset(_ initial: JSONObject = [:]) {
        current = JSONObject(copying: initial)
        buffer = ""
        applied = []
        processedLines = []
    }

    private func apply(_ patch: JSONPatch) throws {
        var value = JSONValue.object(current)
        current = [:]
        defer { current = value.objectValue ?? [:] }
        try SpecStream.apply(patch, to: &value)
    }
}

/// Splits a stream of prose and JSONL patches, like upstream
/// `createMixedStreamParser`. Lines between a "```spec" fence and a closing
/// "```" are patches; outside a fence, any line that parses as a patch is one
/// and the rest is text.
public final class MixedStreamParser {
    private let onPatch: (JSONPatch) -> Void
    private let onText: (String) -> Void
    private var buffer = ""
    private var inSpecFence = false

    public init(onPatch: @escaping (JSONPatch) -> Void, onText: @escaping (String) -> Void) {
        self.onPatch = onPatch
        self.onText = onText
    }

    /// Adds a chunk and reports each complete line.
    public func push(_ chunk: String) {
        buffer += chunk
        var lines = JavaScript.splitLines(buffer)
        buffer = lines.removeLast()
        for line in lines { process(line) }
    }

    /// Reports any buffered partial line. Call when the stream ends.
    public func flush() {
        if !JavaScript.trim(buffer).isEmpty { process(buffer) }
        buffer = ""
    }

    private func process(_ line: String) {
        let trimmed = JavaScript.trim(line)
        if !inSpecFence, JavaScript.startsWith(trimmed, "```spec") {
            inSpecFence = true
            return
        }
        if inSpecFence, trimmed == "```" {
            inSpecFence = false
            return
        }
        if trimmed.isEmpty { return }
        if inSpecFence {
            if let patch = SpecStream.parseLine(trimmed) { onPatch(patch) }
            return
        }
        if let patch = SpecStream.parseLine(trimmed) {
            onPatch(patch)
        } else {
            onText(line)
        }
    }
}

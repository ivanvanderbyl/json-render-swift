import Foundation
@testable import JSONRender

/// Records Diagnostics messages in the shape Conformance/src/console.mjs uses.
final class MessageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [Diagnostics.Message] = []

    func record<T>(_ body: () throws -> T) rethrows -> T {
        try Diagnostics.$handler.withValue({ [self] message in lock.withLock { messages.append(message) } }) {
            try body()
        }
    }

    func record<T>(isolation: isolated (any Actor)? = #isolation, _ body: () async throws -> T) async rethrows -> T {
        try await Diagnostics.$handler.withValue({ [self] message in lock.withLock { messages.append(message) } }) {
            try await body()
        }
    }

    func reset() { lock.withLock { messages = [] } }

    var encoded: JSONValue {
        .array(JSONArray(lock.withLock { messages }.map { ["level": .string($0.level.rawValue), "text": .string($0.text)] }))
    }

    /// Each distinct message once, in order of first appearance.
    var dedupedEncoded: JSONValue {
        var seen: Set<String> = []
        let unique = lock.withLock { messages }.filter { seen.insert("\($0.level.rawValue):\($0.text)").inserted }
        return .array(JSONArray(unique.map { ["level": .string($0.level.rawValue), "text": .string($0.text)] }))
    }
}

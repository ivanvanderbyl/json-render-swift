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

    var encoded: JSONValue {
        .array(JSONArray(lock.withLock { messages }.map { ["level": .string($0.level.rawValue), "text": .string($0.text)] }))
    }
}

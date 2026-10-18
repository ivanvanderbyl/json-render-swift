import Foundation
@testable import JSONRender

/// Captures the warnings and errors json-render reports, the way upstream
/// tests spy on `console.warn` and `console.error`.
final class DiagnosticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Diagnostics.Message] = []

    var messages: [Diagnostics.Message] { lock.withLock { recorded } }
    var warnings: [String] { messages.filter { $0.level == .warning }.map(\.text) }
    var errors: [String] { messages.filter { $0.level == .error }.map(\.text) }

    func record<T>(_ body: () throws -> T) rethrows -> T {
        try Diagnostics.$handler.withValue({ [self] message in lock.withLock { recorded.append(message) } }) {
            try body()
        }
    }

    func record<T>(isolation: isolated (any Actor)? = #isolation, _ body: () async throws -> T) async rethrows -> T {
        try await Diagnostics.$handler.withValue({ [self] message in lock.withLock { recorded.append(message) } }) {
            try await body()
        }
    }
}

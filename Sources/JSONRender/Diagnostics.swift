import os

/// Warnings json-render reports where upstream calls `console.warn` or
/// `console.error`. By default they go to the unified log. Bind ``handler``
/// to capture them, for example in tests.
public enum Diagnostics {
    public enum Level: String, Sendable { case warning, error }

    public struct Message: Sendable, Equatable, CustomStringConvertible {
        public var level: Level
        public var text: String
        public var description: String { "\(level.rawValue): \(text)" }
    }

    /// Receives every message reported in the current task.
    @TaskLocal public static var handler: (@Sendable (Message) -> Void)?

    private static let logger = Logger(subsystem: "JSONRender", category: "json-render")

    /// Reports a warning, like `console.warn`.
    public static func warn(_ text: String) { report(Message(level: .warning, text: text)) }
    /// Reports an error, like `console.error`.
    public static func error(_ text: String) { report(Message(level: .error, text: text)) }

    static func report(_ message: Message) {
        if let handler {
            handler(message)
        } else if message.level == .error {
            logger.error("\(message.text, privacy: .public)")
        } else {
            logger.warning("\(message.text, privacy: .public)")
        }
    }
}

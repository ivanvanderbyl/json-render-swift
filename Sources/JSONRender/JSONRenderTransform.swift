/// The data part type json-render uses in AI SDK UI message streams.
public enum SpecDataPart {
    /// `SPEC_DATA_PART`: "spec".
    public static let name = "spec"
    /// `SPEC_DATA_PART_TYPE`: "data-spec", the chunk type on the wire.
    public static let type = "data-\(name)"
}

/// Classifies AI SDK UI message stream chunks as prose or spec patches, like
/// upstream `createJsonRenderTransform`.
///
/// Lines between a "```spec" fence and "```" become `data-spec` patch chunks
/// and the fences are dropped. Outside a fence, a line starting with `{` that
/// parses as a patch becomes a patch chunk; other text passes through as
/// `text-delta` chunks. Text blocks are closed before each patch and reopened
/// after it, so prose and UI stay interleaved. Other chunk types pass through.
///
/// Upstream emits one `text-delta` per UTF-16 code unit; this port emits one
/// per Unicode scalar, because a Swift string cannot hold half a surrogate pair.
public final class JSONRenderTransform {
    private var lineBuffer = ""
    private var currentTextID: JSONValue = ""
    private var buffering = false
    private var inSpecFence = false
    private var inTextBlock = false
    private var textIDCounter = 0
    private var output: [JSONObject] = []

    public init() {}

    /// Transforms one input chunk into zero or more output chunks.
    public func transform(_ chunk: JSONObject) -> [JSONObject] {
        switch chunk["type"] ?? .undefined {
        case "text-start":
            let id = chunk["id"] ?? .undefined
            if let number = JavaScript.parseInt(id.javaScriptString), number >= textIDCounter {
                textIDCounter = number
            }
            currentTextID = id
            inTextBlock = true
            output.append(chunk)
        case "text-delta":
            let text = (chunk["delta"] ?? .undefined).javaScriptString
            for scalar in text.unicodeScalars {
                let character = String(scalar)
                if scalar == "\n" {
                    if buffering {
                        processCompleteLine(lineBuffer)
                        lineBuffer = ""
                        buffering = false
                    } else if !inSpecFence {
                        emitTextDelta("\n")
                    }
                } else if lineBuffer.isEmpty, !buffering {
                    if inSpecFence || scalar == "{" || scalar == "`" {
                        buffering = true
                        lineBuffer += character
                    } else {
                        emitTextDelta(character)
                    }
                } else if buffering {
                    lineBuffer += character
                } else {
                    emitTextDelta(character)
                }
            }
        case "text-end":
            flushBuffer()
            if inTextBlock {
                output.append(["type": "text-end", "id": currentTextID])
                inTextBlock = false
            }
        default:
            output.append(chunk)
        }
        return drain()
    }

    /// Flushes buffered text and closes an open text block. Call when the
    /// input stream ends.
    public func finish() -> [JSONObject] {
        flushBuffer()
        closeTextBlock()
        return drain()
    }

    private func drain() -> [JSONObject] {
        defer { output = [] }
        return output
    }

    private func closeTextBlock() {
        if inTextBlock {
            output.append(["type": "text-end", "id": currentTextID])
            inTextBlock = false
        }
    }

    private func ensureTextBlock() {
        if !inTextBlock {
            textIDCounter += 1
            currentTextID = .string(String(textIDCounter))
            output.append(["type": "text-start", "id": currentTextID])
            inTextBlock = true
        }
    }

    private func emitTextDelta(_ delta: String) {
        ensureTextBlock()
        output.append(["type": "text-delta", "id": currentTextID, "delta": .string(delta)])
    }

    private func emitPatch(_ patch: JSONPatch) {
        closeTextBlock()
        output.append(["type": .string(SpecDataPart.type), "data": ["type": "patch", "patch": .object(patch.object)]])
    }

    private func flushBuffer() {
        if lineBuffer.isEmpty { return }
        let trimmed = JavaScript.trim(lineBuffer)
        if inSpecFence {
            if !trimmed.isEmpty, let patch = SpecStream.parseLine(trimmed) { emitPatch(patch) }
            lineBuffer = ""
            buffering = false
            return
        }
        if !trimmed.isEmpty {
            if let patch = SpecStream.parseLine(trimmed) {
                emitPatch(patch)
            } else {
                emitTextDelta(lineBuffer)
            }
        } else {
            emitTextDelta(lineBuffer)
        }
        lineBuffer = ""
        buffering = false
    }

    private func processCompleteLine(_ line: String) {
        let trimmed = JavaScript.trim(line)
        if !inSpecFence, JavaScript.startsWith(trimmed, "```spec") {
            inSpecFence = true
            return
        }
        if inSpecFence, trimmed == "```" {
            inSpecFence = false
            return
        }
        if inSpecFence {
            if !trimmed.isEmpty, let patch = SpecStream.parseLine(trimmed) { emitPatch(patch) }
            return
        }
        if trimmed.isEmpty {
            emitTextDelta("\n")
            return
        }
        if let patch = SpecStream.parseLine(trimmed) {
            emitPatch(patch)
        } else {
            emitTextDelta(line + "\n")
        }
    }
}

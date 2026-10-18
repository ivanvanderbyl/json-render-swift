/// A version number per element that changes when the element or anything it
/// renders changes, like upstream `useElementSignatures`. The renderer skips
/// unchanged elements on spec updates, and resets an element's error boundary
/// when its version changes.
struct ElementSignatures {
    private struct Entry {
        var own: JSONValue
        var children: [(String, Int)]
        var version: Int
    }

    private var entries: [String: Entry] = [:]
    private var lastVersion = 0

    /// Computes versions for every element. Iterative, so deep graphs do not
    /// overflow the stack, and cycles terminate. Throws when an element's
    /// `children` or `slots` cannot be iterated, as upstream does.
    mutating func update(_ elements: JSONObject) throws -> [String: Int] {
        var next: [String: Entry] = [:]
        var signatures: [String: Int] = [:]
        var visiting: Set<String> = []

        struct Frame {
            var key: String
            var element: JSONValue
            var children: [String]
            var index = 0
            var versions: [(String, Int)] = []
        }

        func childKeys(_ element: JSONValue) throws -> [String] {
            var keys: [String] = []
            let children = element["children"]
            if !children.isNullish { keys += try JavaScript.iterate(children, expression: "element.children").map(\.javaScriptString) }
            let slots = element["slots"]
            if !slots.isNullish {
                // `Object.values(slots).flat()` keeps a non-array slot value whole.
                for (_, value) in try JavaScript.entries(slots) {
                    keys += value.arrayValue.map { $0.map(\.javaScriptString) } ?? [value.javaScriptString]
                }
            }
            return keys
        }

        for (key, element) in elements where signatures[key] == nil && element.isTruthy {
            visiting.insert(key)
            var stack = [Frame(key: key, element: element, children: try childKeys(element))]
            while var frame = stack.popLast() {
                if frame.index < frame.children.count {
                    let childKey = frame.children[frame.index]
                    frame.index += 1
                    if let version = signatures[childKey] {
                        frame.versions.append((childKey, version))
                        stack.append(frame)
                        continue
                    }
                    let child = elements[childKey] ?? .undefined
                    if !child.isTruthy || visiting.contains(childKey) {
                        frame.versions.append((childKey, -1))
                        stack.append(frame)
                        continue
                    }
                    visiting.insert(childKey)
                    stack.append(frame)
                    stack.append(Frame(key: childKey, element: child, children: try childKeys(child)))
                    continue
                }
                let prior = entries[frame.key]
                let unchanged = prior.map {
                    Self.structurallyEqual($0.own, frame.element)
                        && $0.children.count == frame.versions.count
                        && zip($0.children, frame.versions).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
                } ?? false
                let version: Int
                if unchanged, let prior {
                    version = prior.version
                } else {
                    lastVersion += 1
                    version = lastVersion
                }
                visiting.remove(frame.key)
                next[frame.key] = Entry(own: frame.element, children: frame.versions, version: version)
                signatures[frame.key] = version
                if !stack.isEmpty {
                    stack[stack.count - 1].versions.append((frame.key, version))
                }
            }
        }
        entries = next
        return signatures
    }

    /// Upstream `structurallyEqual`: same shape and `Object.is` leaves.
    static func structurallyEqual(_ a: JSONValue, _ b: JSONValue) -> Bool {
        switch (a, b) {
        case let (.number(x), .number(y)):
            return (x.isNaN && y.isNaN) || (x == y && x.sign == y.sign)
        case let (.array(x), .array(y)):
            return x.isIdentical(to: y) || (x.count == y.count && zip(x, y).allSatisfy(structurallyEqual))
        case let (.object(x), .object(y)):
            return x.isIdentical(to: y)
                || (x.count == y.count && x.allSatisfy { key, value in y[key].map { structurallyEqual(value, $0) } ?? false })
        default:
            return a.strictEquals(b)
        }
    }
}

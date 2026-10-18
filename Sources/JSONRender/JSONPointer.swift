/// JSON Pointer (RFC 6901) paths, as json-render uses them for state and spec
/// locations. json-render accepts paths with or without a leading slash.
public enum JSONPointer {
    /// Splits a path into unescaped segments, like upstream `parseJsonPointer`.
    /// `~1` decodes to `/` and then `~0` decodes to `~`.
    public static func parse(_ path: String) -> [String] {
        var units = Array(path.utf16)
        if units.first == 0x2F { units.removeFirst() }
        return units.split(separator: 0x2F, omittingEmptySubsequences: false).map { segment in
            String(decoding: unescape(Array(segment)), as: UTF16.self)
        }
    }

    /// Replaces every `~1` with `/`, then every `~0` with `~`, as upstream does
    /// with two global string replacements.
    private static func unescape(_ units: [UInt16]) -> [UInt16] {
        func replace(_ input: [UInt16], _ digit: UInt16, with replacement: UInt16) -> [UInt16] {
            var output: [UInt16] = []
            output.reserveCapacity(input.count)
            var index = 0
            while index < input.count {
                if input[index] == 0x7E, index + 1 < input.count, input[index + 1] == digit {
                    output.append(replacement)
                    index += 2
                } else {
                    output.append(input[index])
                    index += 1
                }
            }
            return output
        }
        return replace(replace(units, 0x31, with: 0x2F), 0x30, with: 0x7E)
    }

    /// Converts a path value the way upstream passes it to `getByPath`: falsy
    /// values mean the root, strings are paths, and anything else is the
    /// TypeError JavaScript raises when it calls `path.startsWith`.
    static func path(from value: JSONValue) throws -> String? {
        if case let .string(path) = value { return path.isEmpty ? nil : path }
        if !value.isTruthy { return nil }
        throw JavaScriptError.typeError("path.startsWith is not a function")
    }
}

extension JSONValue {
    /// Reads the value at a JSON Pointer path, like upstream `getByPath`.
    /// An empty path or "/" returns the value itself. Missing members, and
    /// traversal through anything that is not an object or array, give
    /// `undefined`. Array segments are read with `parseInt`, so "1abc" reads
    /// index 1 as it does upstream.
    public func value(atPath path: String) -> JSONValue {
        if path.isEmpty || path == "/" { return self }
        var current = self
        for segment in JSONPointer.parse(path) {
            switch current {
            case .undefined, .null:
                return .undefined
            case let .array(array):
                let index = JavaScript.parseInt(segment)
                current = index.flatMap { array.indices.contains($0) ? array[$0] : nil } ?? .undefined
            case let .object(object):
                current = object[segment] ?? .undefined
            default:
                return .undefined
            }
        }
        return current
    }

    /// Writes a value at a path, creating objects or arrays for missing
    /// segments, like upstream `setByPath`. Upstream throws a TypeError when
    /// the path passes through `null`; this method then leaves the value
    /// unchanged. Use ``SpecStream`` to observe that error.
    public mutating func setValue(_ value: JSONValue, atPath path: String) {
        try? write(value, atPath: path, mode: .set)
    }

    /// Adds a value with JSON Patch "add" semantics, like upstream `addByPath`:
    /// array indices insert rather than replace, and "-" appends.
    public mutating func addValue(_ value: JSONValue, atPath path: String) {
        try? write(value, atPath: path, mode: .add)
    }

    /// Removes a value with JSON Patch "remove" semantics, like upstream
    /// `removeByPath`. Missing paths are a no-op.
    public mutating func removeValue(atPath path: String) {
        try? remove(atPath: path)
    }

    enum WriteMode { case set, add }

    /// `setByPath` / `addByPath`, including the TypeError upstream raises when a
    /// path passes through `null`.
    mutating func write(_ value: JSONValue, atPath path: String, mode: WriteMode) throws {
        try Self.write(value, into: &self, segments: JSONPointer.parse(path)[...], mode: mode)
    }

    private static func write(
        _ value: JSONValue, into node: inout JSONValue, segments: ArraySlice<String>, mode: WriteMode
    ) throws {
        let segment = segments.first!
        let rest = segments.dropFirst()
        switch node {
        case var .array(array):
            node = .undefined
            defer { node = .array(array) }
            if rest.isEmpty {
                if segment == "-" {
                    array.append(value)
                    return
                }
                guard let index = JavaScript.parseInt(segment) else {
                    // `array[NaN] = value` adds a non-index property that JSON
                    // never sees; adding with NaN inserts at the start.
                    if mode == .add { array.insert(value, at: 0) }
                    return
                }
                switch mode {
                case .set:
                    // A negative index is a non-index property in JavaScript.
                    guard index >= 0 else { return }
                    if index >= array.count {
                        array.append(contentsOf: repeatElement(.undefined, count: index - array.count))
                        array.append(value)
                    } else {
                        array[index] = value
                    }
                case .add:
                    let start = index < 0 ? max(array.count + index, 0) : min(index, array.count)
                    array.insert(value, at: start)
                }
                return
            }
            // Intermediate array segment: a NaN or negative index writes into a
            // non-index property, which JSON never sees.
            guard let index = JavaScript.parseInt(segment), index >= 0 else { return }
            if index >= array.count {
                array.append(contentsOf: repeatElement(.undefined, count: index - array.count + 1))
            }
            var child = array[index]
            array[index] = .undefined
            if !child.isContainer, !child.isNull { child = container(for: rest.first!) }
            try write(value, into: &child, segments: rest, mode: mode)
            array[index] = child
        case var .object(object):
            node = .undefined
            defer { node = .object(object) }
            if rest.isEmpty {
                object[segment] = value
                return
            }
            var child = object[segment] ?? .undefined
            object[segment] = .undefined
            if !child.isContainer, !child.isNull { child = container(for: rest.first!) }
            try write(value, into: &child, segments: rest, mode: mode)
            object[segment] = child
        case .null:
            if rest.isEmpty {
                throw JavaScriptError.typeError("Cannot set properties of null (setting '\(segment)')")
            }
            throw JavaScriptError.typeError("Cannot use 'in' operator to search for '\(segment)' in null")
        default:
            throw JavaScriptError.typeError("Cannot use 'in' operator to search for '\(segment)' in \(node.javaScriptString)")
        }
    }

    /// The container setByPath creates for a missing segment: an array when the
    /// next segment is a numeric index or "-", otherwise an object.
    private static func container(for nextSegment: String) -> JSONValue {
        nextSegment == "-" || JavaScript.isDigits(nextSegment) ? .array([]) : .object([:])
    }

    /// `removeByPath`, including the TypeError upstream raises when the parent
    /// of the removed member is `null`.
    mutating func remove(atPath path: String) throws {
        try Self.remove(from: &self, segments: JSONPointer.parse(path)[...])
    }

    private static func remove(from node: inout JSONValue, segments: ArraySlice<String>) throws {
        let segment = segments.first!
        let rest = segments.dropFirst()
        switch node {
        case var .array(array):
            guard let index = JavaScript.parseInt(segment) else { return }
            if rest.isEmpty {
                if index >= 0, index < array.count {
                    node = .undefined
                    array.remove(at: index)
                    node = .array(array)
                }
                return
            }
            guard index >= 0, index < array.count, array[index].isContainer || array[index].isNull else { return }
            node = .undefined
            defer { node = .array(array) }
            var child = array[index]
            array[index] = .undefined
            defer { array[index] = child }
            try remove(from: &child, segments: rest)
        case var .object(object):
            if rest.isEmpty {
                node = .undefined
                object[segment] = nil
                node = .object(object)
                return
            }
            guard let child = object[segment], child.isContainer || child.isNull else { return }
            node = .undefined
            defer { node = .object(object) }
            var member = child
            object[segment] = .undefined
            defer { object[segment] = member }
            try remove(from: &member, segments: rest)
        case .null:
            if rest.isEmpty {
                throw JavaScriptError.typeError("Cannot convert undefined or null to object")
            }
            throw JavaScriptError.typeError("Cannot use 'in' operator to search for '\(segment)' in null")
        default:
            // Deleting a member of a primitive is a silent no-op in sloppy code
            // paths and never reached from an object root.
            return
        }
    }
}

extension JavaScript {
    /// `parseInt(string, 10)` limited to what array indexing needs: the integer
    /// value of the leading digits after optional whitespace and sign, or nil
    /// when there are none (NaN).
    static func parseInt(_ string: String) -> Int? {
        var scalars = Substring(string).unicodeScalars.drop(while: isWhitespace)
        var negative = false
        if let sign = scalars.first, sign == "+" || sign == "-" {
            negative = sign == "-"
            scalars = scalars.dropFirst()
        }
        var value = 0
        var digits = 0
        for scalar in scalars {
            guard scalar.value >= 0x30, scalar.value <= 0x39 else { break }
            let (multiplied, overflow) = value.multipliedReportingOverflow(by: 10)
            if overflow { return negative ? Int.min : Int.max }
            value = multiplied + Int(scalar.value - 0x30)
            digits += 1
        }
        guard digits > 0 else { return nil }
        return negative ? -value : value
    }

    /// `/^\d+$/.test(string)`.
    static func isDigits(_ string: String) -> Bool {
        !string.isEmpty && string.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    /// `string.startsWith(prefix)`, comparing UTF-16 code units.
    static func startsWith(_ string: String, _ prefix: String) -> Bool {
        string.utf16.starts(with: prefix.utf16)
    }

    /// `string.endsWith(suffix)`, comparing UTF-16 code units.
    static func endsWith(_ string: String, _ suffix: String) -> Bool {
        string.utf16.reversed().starts(with: suffix.utf16.reversed())
    }

    /// `string.slice(1)`: drops the first UTF-16 code unit.
    static func dropFirstUnit(_ string: String) -> String {
        String(decoding: string.utf16.dropFirst(), as: UTF16.self)
    }

    /// `a === b` for two strings: equal UTF-16 code units.
    static func same(_ a: String, _ b: String) -> Bool {
        a.utf16.elementsEqual(b.utf16)
    }
}

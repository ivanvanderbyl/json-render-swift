@testable import JSONRender

/// Decodes and encodes the tagged JSON the conformance harness uses for
/// JavaScript values plain JSON cannot hold. See Conformance/src/encoding.mjs.
enum Tagged {
    static func decode(_ value: JSONValue) -> JSONValue {
        switch value {
        case let .array(array):
            return .array(JSONArray(array.map(decode)))
        case let .object(object):
            if let tag = object["$js"]?.stringValue {
                switch tag {
                case "undefined", "hole": return .undefined
                case "NaN": return .number(.nan)
                case "Infinity": return .number(.infinity)
                case "-Infinity": return .number(-.infinity)
                case "-0": return .number(-0.0)
                case "object": return decodeMembers(object["value"]?.objectValue ?? [:])
                default: return value
                }
            }
            return decodeMembers(object)
        default:
            return value
        }
    }

    private static func decodeMembers(_ object: JSONObject) -> JSONValue {
        var out = JSONObject()
        for (key, member) in object { out[key] = decode(member) }
        return .object(out)
    }

    static func encode(_ value: JSONValue) -> JSONValue {
        switch value {
        case .undefined:
            return ["$js": "undefined"]
        case let .number(number):
            if number.isNaN { return ["$js": "NaN"] }
            if number == .infinity { return ["$js": "Infinity"] }
            if number == -.infinity { return ["$js": "-Infinity"] }
            if number == 0, number.sign == .minus { return ["$js": "-0"] }
            return value
        case let .array(array):
            return .array(JSONArray(array.map(encode)))
        case let .object(object):
            var out = JSONObject()
            for (key, member) in object { out[key] = encode(member) }
            return object.hasKey("$js") ? ["$js": "object", "value": .object(out)] : .object(out)
        default:
            return value
        }
    }

    /// True when `actual` (a Swift capture) matches `golden` (an upstream
    /// capture): both are decoded and compared member by member, numbers by
    /// SameValue (NaN equals NaN, 0 differs from -0) and array holes as
    /// `undefined`.
    static func matches(_ golden: JSONValue, _ actual: JSONValue) -> Bool {
        sameValue(decode(golden), decode(actual))
    }

    private static func sameValue(_ a: JSONValue, _ b: JSONValue) -> Bool {
        switch (a, b) {
        case let (.number(x), .number(y)):
            return (x.isNaN && y.isNaN) || (x == y && x.sign == y.sign)
        case let (.array(x), .array(y)):
            return x.count == y.count && zip(x, y).allSatisfy(sameValue)
        case let (.object(x), .object(y)):
            return x.count == y.count && x.allSatisfy { key, value in y[key].map { sameValue(value, $0) } ?? false }
        default:
            return a == b
        }
    }

    /// Runs `body` and encodes its result like `capture()` in encoding.mjs.
    static func capture(_ body: () throws -> JSONValue) -> JSONValue {
        do {
            return ["value": encode(try body())]
        } catch {
            return ["threw": .string(String(describing: error))]
        }
    }
}

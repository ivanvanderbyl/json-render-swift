/// A JavaScript plain object: string keys mapped to ``JSONValue`` members.
///
/// Like ``JSONArray``, `JSONObject` has copy-on-write value semantics and its
/// shared storage is the identity JavaScript `===` compares.
///
/// Keys iterate in JavaScript property order: keys that are array indices
/// ("0" to "4294967294" in canonical form) come first in ascending numeric
/// order, then all other keys in insertion order. Keys are distinct by UTF-16
/// code units, so "é" and "e\u{301}" are two keys, as in JavaScript.
public struct JSONObject: Sendable {
    final class Storage: @unchecked Sendable {
        var keys: [String]
        /// How many leading entries of `keys` are array-index keys.
        var indexKeyCount: Int
        var values: [ExactKey: JSONValue]

        init(keys: [String], indexKeyCount: Int, values: [ExactKey: JSONValue]) {
            self.keys = keys
            self.indexKeyCount = indexKeyCount
            self.values = values
        }
    }

    private(set) var storage: Storage

    public init() { storage = Storage(keys: [], indexKeyCount: 0, values: [:]) }

    /// The keys in JavaScript property order, like `Object.keys`.
    public var keys: [String] { storage.keys }

    public var count: Int { storage.keys.count }
    public var isEmpty: Bool { storage.keys.isEmpty }

    /// True when both objects share storage, like JavaScript `===`.
    public func isIdentical(to other: JSONObject) -> Bool { storage === other.storage }

    /// True when the object has the key as an own property, like `key in object`
    /// for plain data. A member set to `undefined` still counts.
    public func hasKey(_ key: String) -> Bool { storage.values[ExactKey(key)] != nil }

    /// Reads or writes a member. Reading a missing key returns `nil`. Assigning
    /// `nil` deletes the member; assigning `.undefined` keeps the key with an
    /// undefined value, like `object[key] = undefined`.
    public subscript(key: String) -> JSONValue? {
        get { storage.values[ExactKey(key)] }
        set {
            makeUnique()
            let exact = ExactKey(key)
            if let newValue {
                if storage.values.updateValue(newValue, forKey: exact) == nil {
                    insertKey(key)
                }
            } else if storage.values.removeValue(forKey: exact) != nil {
                removeKey(exact)
            }
        }
    }

    @discardableResult
    public mutating func removeValue(forKey key: String) -> JSONValue? {
        let previous = self[key]
        self[key] = nil
        return previous
    }

    /// Members in key order, like `Object.entries`.
    public var entries: [(key: String, value: JSONValue)] {
        storage.keys.map { ($0, storage.values[ExactKey($0)]!) }
    }

    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(keys: storage.keys, indexKeyCount: storage.indexKeyCount, values: storage.values)
        }
    }

    private func insertKey(_ key: String) {
        guard let index = arrayIndex(key) else {
            storage.keys.append(key)
            return
        }
        var low = 0
        var high = storage.indexKeyCount
        while low < high {
            let middle = (low + high) / 2
            if arrayIndex(storage.keys[middle])! < index { low = middle + 1 } else { high = middle }
        }
        storage.keys.insert(key, at: low)
        storage.indexKeyCount += 1
    }

    private func removeKey(_ exact: ExactKey) {
        guard let position = storage.keys.firstIndex(where: { ExactKey($0) == exact }) else { return }
        storage.keys.remove(at: position)
        if position < storage.indexKeyCount { storage.indexKeyCount -= 1 }
    }
}

/// The numeric value of a key that JavaScript treats as an array index: the
/// canonical decimal form of an integer from 0 to 2^32 - 2.
func arrayIndex(_ key: String) -> UInt32? {
    let units = key.utf8
    guard let first = units.first, units.count <= 10 else { return nil }
    if first == UInt8(ascii: "0") { return units.count == 1 ? 0 : nil }
    var value: UInt64 = 0
    for unit in units {
        guard unit >= UInt8(ascii: "0"), unit <= UInt8(ascii: "9") else { return nil }
        value = value * 10 + UInt64(unit - UInt8(ascii: "0"))
    }
    return value < 4_294_967_295 ? UInt32(value) : nil
}

/// A string key compared and hashed by UTF-16 code units, like JavaScript
/// property keys, rather than by Unicode canonical equivalence.
struct ExactKey: Hashable, Sendable {
    let value: String
    init(_ value: String) { self.value = value }

    static func == (lhs: ExactKey, rhs: ExactKey) -> Bool {
        lhs.value.utf16.elementsEqual(rhs.value.utf16)
    }

    func hash(into hasher: inout Hasher) {
        for unit in value.utf16 { hasher.combine(unit) }
    }
}

extension JSONObject: Sequence {
    public func makeIterator() -> IndexingIterator<[(key: String, value: JSONValue)]> {
        entries.makeIterator()
    }
}

extension JSONObject: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.init()
        for (key, value) in elements { self[key] = value }
    }
}

extension JSONObject: Equatable {
    /// Same keys and structurally equal members, in any order.
    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        if lhs.storage === rhs.storage { return true }
        guard lhs.count == rhs.count else { return false }
        for (key, value) in lhs {
            guard let other = rhs[key], other == value else { return false }
        }
        return true
    }
}

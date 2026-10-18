/// A JavaScript array of ``JSONValue`` elements with reference identity.
///
/// `JSONArray` has value semantics with copy-on-write. Copies share storage, and
/// that shared storage is the identity JavaScript `===` compares. Mutating a
/// shared copy gives it new storage, so it is no longer strictly equal to the
/// original, as with a new array in JavaScript.
public struct JSONArray: Sendable {
    final class Storage: @unchecked Sendable {
        var elements: [JSONValue]
        init(_ elements: [JSONValue]) { self.elements = elements }
    }

    private(set) var storage: Storage

    public init() { storage = Storage([]) }

    public init<S: Sequence>(_ elements: S) where S.Element == JSONValue {
        storage = Storage(Array(elements))
    }

    /// The elements as a Swift array.
    public var elements: [JSONValue] { storage.elements }

    /// True when both arrays share storage, like JavaScript `===`.
    public func isIdentical(to other: JSONArray) -> Bool { storage === other.storage }

    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(storage.elements)
        }
    }
}

extension JSONArray: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { storage.elements.count }

    public subscript(position: Int) -> JSONValue {
        get { storage.elements[position] }
        set {
            makeUnique()
            storage.elements[position] = newValue
        }
    }

    public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C)
    where C.Element == JSONValue {
        makeUnique()
        storage.elements.replaceSubrange(subrange, with: newElements)
    }

    public mutating func reserveCapacity(_ n: Int) {
        makeUnique()
        storage.elements.reserveCapacity(n)
    }
}

extension JSONArray: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self.init(elements) }
}

extension JSONArray: Equatable {
    public static func == (lhs: JSONArray, rhs: JSONArray) -> Bool {
        lhs.storage === rhs.storage || lhs.storage.elements == rhs.storage.elements
    }
}

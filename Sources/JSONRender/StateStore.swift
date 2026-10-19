/// Owns the state model and notifies subscribers when it changes, like the
/// upstream `StateStore` interface.
///
/// Supply your own conformance to back json-render state with another store,
/// or use ``MemoryStateStore``. ``AdaptedStateStore`` builds a full store from
/// three closures, like upstream `createStoreAdapter`.
@MainActor
public protocol StateStore: AnyObject {
    /// Reads a value by JSON Pointer path.
    func get(_ path: String) -> JSONValue
    /// Writes a value by path and notifies subscribers. Upstream compares the
    /// old and new value with `===`, so writing an equal but separately built
    /// object or array still counts as a change.
    func set(_ path: String, _ value: JSONValue)
    /// Writes several paths with a single notification. Only paths whose value
    /// changes (by `===`) are applied.
    func update(_ updates: JSONObject)
    /// The whole state model.
    var snapshot: JSONObject { get }
    /// Registers a listener called after every change. Returns a function that
    /// unsubscribes it.
    func subscribe(_ listener: @escaping @MainActor () -> Void) -> @MainActor () -> Void
}

/// The default in-memory store, like upstream `createStateStore`.
///
/// Every change produces a new snapshot with structural sharing: objects and
/// arrays along the written path are copied, and untouched branches keep
/// their identity.
@MainActor
public final class MemoryStateStore: StateStore {
    public private(set) var snapshot: JSONObject
    private var listeners: [(id: Int, listener: @MainActor () -> Void)] = []
    private var nextListenerID = 0

    public init(_ initialState: JSONObject = [:]) {
        snapshot = JSONObject(copying: initialState)
    }

    public func get(_ path: String) -> JSONValue {
        JSONValue.object(snapshot).value(atPath: path)
    }

    public func set(_ path: String, _ value: JSONValue) {
        if get(path).strictEquals(value) { return }
        snapshot = StateUpdate.setting(value, atPath: path, in: snapshot)
        notify()
    }

    public func update(_ updates: JSONObject) {
        var next = snapshot
        var changed = false
        for (path, value) in updates where !JSONValue.object(next).value(atPath: path).strictEquals(value) {
            next = StateUpdate.setting(value, atPath: path, in: next)
            changed = true
        }
        guard changed else { return }
        snapshot = next
        notify()
    }

    public func subscribe(_ listener: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let id = nextListenerID
        nextListenerID += 1
        listeners.append((id, listener))
        return { [weak self] in self?.listeners.removeAll { $0.id == id } }
    }

    private func notify() {
        for entry in listeners { entry.listener() }
    }
}

/// A store built from a snapshot source, a write function and a subscribe
/// function, like upstream `createStoreAdapter`. It adds path reads, no-op
/// detection and batched updates.
@MainActor
public final class AdaptedStateStore: StateStore {
    private let getSnapshot: @MainActor () -> JSONObject
    private let setSnapshot: @MainActor (JSONObject) -> Void
    private let subscribeListener: @MainActor (@escaping @MainActor () -> Void) -> @MainActor () -> Void

    public init(
        getSnapshot: @escaping @MainActor () -> JSONObject,
        setSnapshot: @escaping @MainActor (JSONObject) -> Void,
        subscribe: @escaping @MainActor (@escaping @MainActor () -> Void) -> @MainActor () -> Void
    ) {
        self.getSnapshot = getSnapshot
        self.setSnapshot = setSnapshot
        subscribeListener = subscribe
    }

    public var snapshot: JSONObject { getSnapshot() }

    public func get(_ path: String) -> JSONValue {
        JSONValue.object(getSnapshot()).value(atPath: path)
    }

    public func set(_ path: String, _ value: JSONValue) {
        let current = getSnapshot()
        if JSONValue.object(current).value(atPath: path).strictEquals(value) { return }
        setSnapshot(StateUpdate.setting(value, atPath: path, in: current))
    }

    public func update(_ updates: JSONObject) {
        var next = getSnapshot()
        var changed = false
        for (path, value) in updates where !JSONValue.object(next).value(atPath: path).strictEquals(value) {
            next = StateUpdate.setting(value, atPath: path, in: next)
            changed = true
        }
        if changed { setSnapshot(next) }
    }

    public func subscribe(_ listener: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        subscribeListener(listener)
    }
}

/// Immutable state writes with structural sharing, like upstream
/// `immutableSetByPath`.
enum StateUpdate {
    /// Returns a copy of `root` with `value` at `path`. The root and every
    /// object or array along the path get new identity; other branches are
    /// shared. A missing intermediate becomes an array when the next segment
    /// is all digits, otherwise an object.
    static func setting(_ value: JSONValue, atPath path: String, in root: JSONObject) -> JSONObject {
        let segments = JSONPointer.parse(path)
        var result = JSONValue.object(JSONObject(copying: root))
        write(value, into: &result, segments: segments[...])
        return result.objectValue!
    }

    private static func write(_ value: JSONValue, into node: inout JSONValue, segments: ArraySlice<String>) {
        let segment = segments.first!
        let rest = segments.dropFirst()
        if rest.isEmpty {
            switch node {
            case var .array(array):
                node = .undefined
                defer { node = .array(array) }
                if segment == "-" {
                    array.append(value)
                } else if let index = JavaScript.parseInt(segment), index >= 0 {
                    // A NaN or negative index is a non-index property JSON never sees.
                    if index >= array.count {
                        array.append(contentsOf: repeatElement(.undefined, count: index - array.count))
                        array.append(value)
                    } else {
                        array[index] = value
                    }
                }
            case var .object(object):
                node = .undefined
                object[segment] = value
                node = .object(object)
            default:
                break
            }
            return
        }

        let existing = member(segment, of: node)
        var child: JSONValue
        switch existing {
        case let .array(array): child = .array(JSONArray(array))
        case let .object(object): child = .object(JSONObject(copying: object))
        default: child = JavaScript.isDigits(rest.first!) ? .array([]) : .object([:])
        }
        write(value, into: &child, segments: rest)
        assign(child, to: segment, of: &node)
    }

    /// `current[segment]` for an intermediate segment. On an array only a
    /// canonical index string reaches an element.
    private static func member(_ segment: String, of node: JSONValue) -> JSONValue {
        switch node {
        case let .array(array):
            guard let index = arrayIndex(segment), Int(index) < array.count else { return .undefined }
            return array[Int(index)]
        case let .object(object):
            return object[segment] ?? .undefined
        default:
            return .undefined
        }
    }

    /// `current[segment] = child`. On an array a segment that is not a
    /// canonical index names a property JSON never sees, so the write is lost.
    private static func assign(_ child: JSONValue, to segment: String, of node: inout JSONValue) {
        switch node {
        case var .array(array):
            guard let index = arrayIndex(segment).map(Int.init) else { return }
            node = .undefined
            if index >= array.count {
                array.append(contentsOf: repeatElement(.undefined, count: index - array.count + 1))
            }
            array[index] = child
            node = .array(array)
        case var .object(object):
            node = .undefined
            object[segment] = child
            node = .object(object)
        default:
            break
        }
    }
}

extension JSONPointer {
    /// The nesting depth after which ``flatten(_:)`` treats objects as leaves.
    static let maxFlattenDepth = 20

    /// Flattens nested plain objects into pointer paths, like upstream
    /// `flattenToPointers`. Arrays, `null` and primitives are leaves. Keys are
    /// joined without escaping, as upstream does. An object already visited
    /// (shared storage) is a leaf, and so is anything beyond
    /// ``maxFlattenDepth`` levels.
    public static func flatten(_ object: JSONObject) -> JSONObject {
        var seen: Set<ObjectIdentifier> = []
        var result = JSONObject()
        flatten(object, prefix: "", depth: 0, seen: &seen, into: &result)
        return result
    }

    private static func flatten(
        _ object: JSONObject, prefix: String, depth: Int, seen: inout Set<ObjectIdentifier>, into result: inout JSONObject
    ) {
        for (key, value) in object {
            let pointer = prefix + "/" + key
            if depth < maxFlattenDepth, case let .object(child) = value, !seen.contains(ObjectIdentifier(child.storage)) {
                seen.insert(ObjectIdentifier(child.storage))
                flatten(child, prefix: pointer, depth: depth + 1, seen: &seen, into: &result)
            } else {
                result[pointer] = value
            }
        }
    }
}

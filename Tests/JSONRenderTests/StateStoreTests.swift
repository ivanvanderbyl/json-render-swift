import Testing
@testable import JSONRender

// Ports upstream tests from packages/core/src/state-store.test.ts (json-render 0.21.1).

@MainActor
@Suite("state-store.test.ts › createStateStore")
struct StateStoreTests {
    final class Counter { var calls = 0 }

    @Test("creates a store with initial state")
    func createsWithInitialState() {
        let store = MemoryStateStore(["name": "test"])
        #expect(store.snapshot == ["name": "test"])
        #expect(store.get("/name") == "test")
    }

    @Test("set notifies subscribers")
    func setNotifies() {
        let store = MemoryStateStore()
        let counter = Counter()
        _ = store.subscribe { counter.calls += 1 }
        store.set("/x", 1)
        #expect(counter.calls == 1)
        #expect(store.get("/x") == 1)
    }

    @Test("set skips notification when value is unchanged")
    func setSkipsUnchanged() {
        let store = MemoryStateStore(["x": 1])
        let counter = Counter()
        _ = store.subscribe { counter.calls += 1 }
        store.set("/x", 1)
        #expect(counter.calls == 0)
        #expect(store.snapshot == ["x": 1])
    }

    @Test("update notifies subscribers once")
    func updateNotifiesOnce() {
        let store = MemoryStateStore()
        let counter = Counter()
        _ = store.subscribe { counter.calls += 1 }
        store.update(["/a": 1, "/b": 2])
        #expect(counter.calls == 1)
        #expect(store.get("/a") == 1)
        #expect(store.get("/b") == 2)
    }

    @Test("update skips notification when no values changed")
    func updateSkipsUnchanged() {
        let store = MemoryStateStore(["a": 1, "b": 2])
        let counter = Counter()
        _ = store.subscribe { counter.calls += 1 }
        store.update(["/a": 1, "/b": 2])
        #expect(counter.calls == 0)
    }

    @Test("unsubscribe stops notifications")
    func unsubscribeStops() {
        let store = MemoryStateStore()
        let counter = Counter()
        let unsubscribe = store.subscribe { counter.calls += 1 }
        store.set("/x", 1)
        #expect(counter.calls == 1)
        unsubscribe()
        store.set("/x", 2)
        #expect(counter.calls == 1)
    }

    @Test("getSnapshot returns a new reference after mutation")
    func snapshotChangesIdentity() {
        let store = MemoryStateStore(["x": 1])
        let first = store.snapshot
        store.set("/x", 2)
        let second = store.snapshot
        #expect(!first.isIdentical(to: second))
        #expect(second["x"] == 2)
    }

    @Test("getSnapshot returns same reference when set is a no-op")
    func snapshotKeepsIdentityOnNoOp() {
        let store = MemoryStateStore(["x": 1])
        let first = store.snapshot
        store.set("/x", 1)
        #expect(first.isIdentical(to: store.snapshot))
    }

    @Test("set on nested path does not mutate previous snapshot")
    func setDoesNotMutatePreviousSnapshot() {
        let store = MemoryStateStore(["user": ["name": "Alice", "age": 30]])
        let first = store.snapshot
        store.set("/user/name", "Bob")
        let second = store.snapshot
        #expect(first["user"] == ["name": "Alice", "age": 30])
        #expect(second["user"]?["name"] == "Bob")
        #expect(!(first["user"] ?? .undefined).strictEquals(second["user"] ?? .undefined))
    }

    @Test("update on nested paths does not mutate previous snapshot")
    func updateDoesNotMutatePreviousSnapshot() {
        let store = MemoryStateStore(["user": ["name": "Alice"], "meta": ["version": 1]])
        let first = store.snapshot
        store.update(["/user/name": "Bob", "/meta/version": 2])
        let second = store.snapshot
        #expect(first["user"]?["name"] == "Alice")
        #expect(first["meta"]?["version"] == 1)
        #expect(second["user"]?["name"] == "Bob")
        #expect(second["meta"]?["version"] == 2)
    }

    @Test("set preserves structural sharing for untouched branches")
    func setPreservesStructuralSharing() {
        let store = MemoryStateStore(["a": ["x": 1], "b": ["y": 2]])
        let first = store.snapshot
        store.set("/a/x", 99)
        let second = store.snapshot
        #expect((second["b"] ?? .undefined).strictEquals(first["b"] ?? .undefined))
        #expect(!(second["a"] ?? .undefined).strictEquals(first["a"] ?? .undefined))
    }

    // "getServerSnapshot returns the same state as getSnapshot" is not
    // applicable: server rendering snapshots are a React concern.
}

@Suite("state-store.test.ts › flattenToPointers")
struct FlattenToPointersTests {
    @Test("flattens top-level keys")
    func flattensTopLevel() {
        #expect(JSONPointer.flatten(["a": 1, "b": "hello"]) == ["/a": 1, "/b": "hello"])
    }

    @Test("flattens nested plain objects")
    func flattensNested() {
        #expect(JSONPointer.flatten(["user": ["name": "Alice", "age": 30]]) == ["/user/name": "Alice", "/user/age": 30])
    }

    @Test("preserves arrays as leaf values")
    func keepsArrays() {
        #expect(JSONPointer.flatten(["items": [1, 2, 3]]) == ["/items": [1, 2, 3]])
    }

    @Test("preserves null as a leaf value")
    func keepsNull() {
        #expect(JSONPointer.flatten(["x": nil]) == ["/x": nil])
    }

    @Test("handles deeply nested objects")
    func handlesDeepNesting() {
        #expect(JSONPointer.flatten(["a": ["b": ["c": 42]]]) == ["/a/b/c": 42])
    }

    @Test("returns empty object for empty input")
    func handlesEmpty() {
        #expect(JSONPointer.flatten([:]) == [:])
    }

    @Test("handles mixed nesting")
    func handlesMixedNesting() {
        let flat = JSONPointer.flatten(["count": 1, "user": ["name": "Alice"], "tags": ["a", "b"]])
        #expect(flat == ["/count": 1, "/user/name": "Alice", "/tags": ["a", "b"]])
    }

    // "stops recursion on circular references via seen set" is not applicable:
    // JSONValue is a value type and cannot contain itself. Shared storage is
    // still tracked, so an object that appears twice is a leaf the second time.
    @Test("treats an object seen earlier in the walk as a leaf")
    func treatsRepeatedObjectAsLeaf() {
        let shared: JSONValue = ["name": "shared"]
        let flat = JSONPointer.flatten(["first": shared, "second": shared])
        #expect(flat["/first/name"] == "shared")
        #expect(flat["/second"]?.strictEquals(shared) == true)
    }

    @Test("caps recursion at depth limit")
    func capsDepth() throws {
        var current: JSONValue = ["leaf": true]
        for _ in 0..<25 { current = ["nested": current] }
        let flat = JSONPointer.flatten(try #require(current.objectValue))
        #expect(flat.count == 1)
        let key = try #require(flat.keys.first)
        #expect(key.split(separator: "/", omittingEmptySubsequences: false).count <= 22)
    }
}

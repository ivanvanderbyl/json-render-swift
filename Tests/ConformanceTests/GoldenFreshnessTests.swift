import CryptoKit
import Foundation
import Testing
@testable import JSONRender

/// Fails when the goldens no longer describe the pinned upstream packages or
/// the current corpus. Regenerate them with `make goldens`.
@Suite("Conformance: goldens are current")
struct GoldenFreshnessTests {
    let manifest: JSONValue
    let pinned: JSONValue

    init() throws {
        manifest = try Golden.read("goldens/manifest.json")
        pinned = try Golden.read("package.json")
    }

    @Test("the package targets the same upstream version as the goldens")
    func targetMatchesGoldens() {
        #expect(manifest["upstream"]["@json-render/core"] == .string(Compatibility.upstreamVersion))
        #expect(manifest["upstream"]["@json-render/react"] == .string(Compatibility.upstreamVersion))
        #expect(manifest["upstream"]["@json-render/react-native"] == .string(Compatibility.upstreamVersion))
    }

    @Test("the goldens were generated with the pinned packages")
    func goldensMatchPins() throws {
        let upstream = try #require(manifest["upstream"].objectValue)
        #expect(!upstream.isEmpty)
        for (name, version) in upstream {
            #expect(pinned["dependencies"][name] == version, "\(name) is pinned to \(pinned["dependencies"][name]) but goldens used \(version)")
        }
    }

    @Test("every corpus file has a current golden")
    func goldensMatchCorpus() throws {
        let corpusDirectory = Golden.conformanceDirectory.appendingPathComponent("corpus")
        let corpusFiles = try FileManager.default.contentsOfDirectory(atPath: corpusDirectory.path)
            .filter { $0.hasSuffix(".json") }
        let suites = try #require(manifest["suites"].objectValue)
        #expect(Set(corpusFiles.map { String($0.dropLast(5)) }) == Set(suites.keys))
        for file in corpusFiles {
            let suite = String(file.dropLast(5))
            let data = try Data(contentsOf: corpusDirectory.appendingPathComponent(file))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(suites[suite]?["corpusSHA256"] == .string(digest), "corpus/\(file) changed since its golden was generated")
            let golden = try Golden.read("goldens/\(suite).json")
            #expect(golden["corpusSHA256"] == .string(digest), "goldens/\(suite).json is stale")
            #expect(golden["upstream"] == manifest["upstream"], "goldens/\(suite).json used other upstream versions")
        }
    }
}

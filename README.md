# json-render for SwiftUI

A Swift and SwiftUI renderer for [json-render](https://json-render.dev) specs that behaves like the upstream TypeScript packages. It targets **@json-render/core 0.21.1** and **@json-render/react-native 0.21.1**, and is checked against them by ported upstream tests and by goldens produced from the pinned upstream code. See [COMPATIBILITY.md](COMPATIBILITY.md) for the status of each feature and every upstream test case.

- Swift 6 with strict concurrency, iOS 17 and macOS 14 or later.
- No third-party Swift dependencies.

## Packages

| Library | What it has |
|---|---|
| `JSONRender` | The UI-free core: specs and JSON values with JavaScript semantics, catalogs and validation, dynamic props, visibility, the state store, actions, repeat, directives, watchers, form validation, streaming, and the `Runtime` that builds the render tree. |
| `JSONRenderUI` | The SwiftUI renderer: `Renderer`, `Registry` (the Swift form of `defineRegistry`) and the `ComponentContext` components draw with. |
| `JSONRenderStandard` | The 26 React Native standard components in SwiftUI, the standard catalog and the standard action handlers. |

## Installation

The package is not published yet. Add it to a SwiftPM package by path:

```swift
dependencies: [
    .package(path: "../json-render-swift"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "JSONRenderUI", package: "json-render-swift"),
        .product(name: "JSONRenderStandard", package: "json-render-swift"),
    ]),
]
```

In Xcode, choose File > Add Package Dependencies, then Add Local.

## Usage

### Render a spec with the standard components

A `Runtime` holds what upstream's `JSONUIProvider` holds: state, action handlers, validation and the render tree. Keep one per screen and give it to a `Renderer`.

```swift
import JSONRender
import JSONRenderStandard
import JSONRenderUI
import SwiftUI

struct GreetingView: View {
    @State private var runtime = Runtime(initialState: ["name": "Ada"])
    let spec = try! Spec(parsing: """
    {
      "root": "screen",
      "elements": {
        "screen": { "type": "Column", "props": { "gap": 12, "padding": 16 }, "children": ["title", "name"] },
        "title": { "type": "Heading", "props": { "text": { "$template": "Hello, ${/name}" } } },
        "name": { "type": "TextInput", "props": { "label": "Name", "value": { "$bindState": "/name" } } }
      }
    }
    """)

    var body: some View {
        Renderer(spec: spec, registry: .standard, runtime: runtime)
    }
}
```

Typing in the text field writes `/name`, and the heading updates.

### Register your own components and actions

Register a component for each type in your catalog, like `defineRegistry`. A component gets a `ComponentContext` with its resolved props, children, slots, events and bindings.

```swift
let catalog = Catalog(schema: .reactNative, components: [
    "Card": ComponentDefinition(slots: ["default"], events: ["press"]),
], actions: [
    "save": ActionDefinition(),
])

let registry = Registry(
    catalog: catalog,
    components: [
        "Card": Component { context in
            VStack(alignment: .leading) {
                Text(context.props["title"]?.stringValue ?? "")
                context.children
            }
            .onTapGesture { context.emit("press") }
        },
    ],
    actions: [
        "save": { params, setState, state in
            setState { previous in
                var next = previous
                next["saved"] = true
                return next
            }
        },
    ]
).includingStandard()

let runtime = Runtime()
for (name, handler) in registry.handlers(for: runtime) {
    runtime.registerHandler(name, handler)
}
```

`includingStandard()` adds the standard components under yours, like the React Native `Renderer`'s `includeStandard`. A component that throws draws nothing and is marked failed, like a React error boundary. A pending `confirm` action shows as an alert.

### Stream a spec

`UIStream` is the Swift form of React Native's `useUIStream`. It posts `{ prompt, context, currentSpec }` to your endpoint and applies each JSONL patch as it arrives.

```swift
@State private var stream = UIStream(api: URL(string: "https://example.com/api/ui")!, validate: true)

var body: some View {
    Renderer(spec: stream.spec, registry: .standard, runtime: runtime, loading: stream.isStreaming)
        .task { await stream.send("Show my account") }
}
```

### Load a catalog from exported JSON Schema

A TypeScript host can export its catalog for the Swift client in two forms:

- **Manifest.** Each component's props and each action's params as JSON Schema. Copy `exportCatalog` from `Conformance/src/export-catalog.mjs` into your build, then load the output with `Catalog(manifest:schema:)`.
- **Whole-spec schema.** One JSON Schema for complete specs, or for documents that hold a spec, such as one made with zod's `toJSONSchema` from a union of one element schema per type. Load it with `SpecJSONSchema`, which finds the element types and their props schemas and validates documents against the full schema.

```swift
let schema = try SpecJSONSchema(JSONValue(parsing: schemaData))
if let spec = schema.spec(in: document) {
    // The document passed the whole schema.
}
let registry = Registry(catalog: schema.catalog(), components: components)
```

A schema-valid spec is only well formed. Check the element graph with `SpecValidator.validate(_:checkOrphans:)` before you trust it.

## Testing

```sh
make test            # every Swift test, including the conformance tests
make goldens         # regenerate the goldens from the pinned upstream packages
make goldens-check   # fail if the goldens are out of date with the pinned packages
```

The goldens need Node and pnpm. The Swift tests read the committed goldens, so `make test` needs neither.

- `Tests/JSONRenderTests` ports the upstream core and React tests. Each file names the upstream file it ports, and each test keeps the upstream name.
- `Tests/ConformanceTests` compares the port with the goldens in `Conformance/goldens`, including the normalised render tree after every step of each render scenario.
- `Tests/JSONRenderUITests` and `Tests/JSONRenderStandardTests` test the SwiftUI layer: what each component draws, bound input write-back and events.
- `Tests/IntegrationTests` loads Brightfield's exported Brie schema and draws a Brie surface with host views.

To change behaviour, add a corpus case in `Conformance/corpus` (for render scenarios, edit `Conformance/corpus-sources/render.mjs` and run `node Conformance/corpus-sources/render.mjs`), run `make goldens`, and see the Swift test fail before you change the port. The Swift tests fail when a golden is stale: each golden records the upstream versions and a hash of its corpus.

## Licence

Apache License 2.0. This is a port of [json-render](https://github.com/vercel-labs/json-render) by Vercel, also Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

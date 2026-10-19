# Compatibility

This package targets **@json-render/core 0.21.1** and **@json-render/react-native 0.21.1**, published 13 October 2026. Upstream behaviour is the specification. Where the upstream docs and code disagree, this port follows the code and the disagreement is listed below.

The render semantics (providers, render tree, actions, watchers, validation) follow the renderer in **@json-render/react 0.21.1**, which is the most complete upstream renderer and the one the render goldens come from. The standard components, catalog and actions follow **@json-render/react-native 0.21.1**. See [React and React Native renderers](#react-and-react-native-renderers) for how the two differ.

The conformance harness pins these exact versions (see `Conformance/package.json`): @json-render/core, @json-render/react and @json-render/react-native 0.21.1, zod 4.6.5, react and react-dom 19.2.3, jsdom 27.4.0.

## Status by feature

| Feature | Status | Evidence |
|---|---|---|
| Spec decoding and the flat `root` / `elements` / `state` format, nested specs | Compatible | `types.test.ts` port, `streaming` goldens (`nested`, `flatToTree`) |
| JSON values with JavaScript semantics (number printing, truthiness, property order, member errors) | Compatible | `js-semantics` goldens (161 cases) |
| State paths (`getByPath`, `setByPath`, `addByPath`, `removeByPath`) | Compatible | `paths` goldens, `types.test.ts` port |
| Spec validation and auto-fix (`validateSpec`, `autoFixSpec`, `formatSpecIssues`) | Compatible | `spec-validator.test.ts` port, `spec-validator` goldens |
| Catalog validation (`defineSchema`, `defineCatalog`, `catalog.validate`) with zod's verdicts and issue messages | Compatible | `schema.test.ts` port, `catalog`, `schemas` and `standard-catalog` goldens |
| Loading a catalog from exported JSON Schema | Supported | `catalog` and `standard-catalog` goldens (manifest form), `SpecJSONSchemaTests` and the Brie integration tests (whole-spec form) |
| Dynamic props: `$state`, `$item`, `$index`, `$bindState`, `$bindItem`, `$cond`, `$template`, `$computed` | Compatible | `props.test.ts` port, `props` goldens |
| Visibility conditions | Compatible | `visibility.test.ts` port, `visibility` goldens |
| State store, `onStateChange`, controlled stores | Compatible | `state-store.test.ts` port, `state-store` goldens, render goldens |
| Bindings and two-way input binding | Compatible | `dynamic-forms.test.tsx` port, render goldens, SwiftUI context and standard input tests |
| Actions, built-in actions, `onSuccess` / `onError`, confirmation | Compatible | `actions.test.ts` port, `actions` goldens, render goldens |
| Chained actions and the action observer | Compatible | `chained-actions.test.tsx` and `action-observer.test.ts` ports, render goldens |
| Form validation (`ValidationProvider`, `validateForm`) | Compatible | `validation.test.ts` and `dynamic-forms.test.tsx` ports, `validation` goldens |
| Repeat and repeat filters | Compatible | `repeat-filter.test.tsx` port, render goldens |
| Directives | Compatible | `directives.test.ts` and `directives.test.tsx` ports, render goldens |
| Watchers (`watch`) | Compatible | render goldens |
| Slots | Compatible | `renderer.test.tsx` port, render goldens, SwiftUI slot test |
| Streaming: SpecStream lines, patches, compilers, mixed text, the AI SDK transform | Compatible | `types.test.ts` port, `streaming` goldens |
| Streaming into the renderer (spec after each patch) | Compatible | `streaming-render.test.tsx` port, render golden "spec patches stream in" |
| `useUIStream` (React Native) as `UIStream` | Compatible | `streaming` goldens (`uiStream` cases, 31) |
| Message parts (`buildSpecFromParts`, `getTextFromParts`) | Compatible | `hooks.test.ts` port, `streaming` goldens |
| Render tree (element, type, resolved props, children, visibility, failures) | Compatible | `render` goldens: 34 scenarios, compared after every step |
| SwiftUI renderer and `defineRegistry` | Supported | `JSONRenderUITests` |
| Standard components (26), standard catalog and standard actions | Compatible | `standard-catalog` goldens, `JSONRenderStandardTests` |

"Compatible" means the behaviour is checked against upstream: ported upstream tests, goldens produced by the pinned upstream code, or both. "Supported" means the feature has no direct upstream counterpart to compare with, so Swift tests define it.

## Upstream test cases

615 upstream test cases are in scope. **547 are ported and passing, 0 are failing, and 68 are N/A** with a reason. Ported tests say which upstream file they port at the top of the file, and each Swift test keeps the upstream test name. The full list is at the end of this document.

| Upstream file | Cases | Passing | N/A |
|---|---|---|---|
| `packages/core/src/actions.test.ts` | 27 | 27 | 0 |
| `packages/core/src/action-observer.test.ts` | 4 | 4 | 0 |
| `packages/core/src/directives.test.ts` | 19 | 19 | 0 |
| `packages/core/src/props.test.ts` | 61 | 61 | 0 |
| `packages/core/src/repeat-schema-parity.test.ts` | 1 | 1 | 0 |
| `packages/core/src/schema.test.ts` | 46 | 18 | 28 |
| `packages/core/src/spec-validator.test.ts` | 38 | 38 | 0 |
| `packages/core/src/state-store.test.ts` | 21 | 19 | 2 |
| `packages/core/src/types.test.ts` | 114 | 113 | 1 |
| `packages/core/src/validation.test.ts` | 90 | 90 | 0 |
| `packages/core/src/visibility.test.ts` | 79 | 79 | 0 |
| `packages/core/src/experimental-evaluator.test.ts` | 5 | 0 | 5 |
| `packages/core/src/experimental-compose.test.ts` | 27 | 0 | 27 |
| `packages/react/src/renderer.test.tsx` | 7 | 7 | 0 |
| `packages/react/src/streaming-render.test.tsx` | 17 | 13 | 4 |
| `packages/react/src/chained-actions.test.tsx` | 4 | 4 | 0 |
| `packages/react/src/dynamic-forms.test.tsx` | 11 | 11 | 0 |
| `packages/react/src/repeat-filter.test.tsx` | 6 | 6 | 0 |
| `packages/react/src/directives.test.tsx` | 3 | 3 | 0 |
| `packages/react/src/contexts/state.test.tsx` | 3 | 3 | 0 |
| `packages/react/src/contexts/visibility.test.tsx` | 8 | 7 | 1 |
| `packages/react/src/hooks.test.ts` | 24 | 24 | 0 |
| **Total** | **615** | **547** | **68** |

The React package has three more test files that were not in scope for this port: `devtools-integration.test.tsx` (devtools are excluded), and `json325-contract-probe.test.tsx`, whose seven probes check that React receives stable or fresh object identities. Swift values have no identity, so those probes have no counterpart.

## Conformance harness

`Conformance/` is a Node project that runs the corpus through the pinned upstream packages and writes goldens. The Swift `ConformanceTests` assert the Swift port gives the same results. 958 golden cases in 14 suites:

| Suite | Cases | What it compares |
|---|---|---|
| `js-semantics` | 161 | Number and string conversion, truthiness, property order, member access errors |
| `paths` | 98 | State path reads and writes |
| `visibility` | 90 | Visibility condition results |
| `props` | 73 | Resolved props and bindings |
| `validation` | 169 | Validation checks, results and messages |
| `spec-validator` | 56 | Spec validation issues, auto-fix output, formatted issues |
| `schemas` | 65 | zod verdicts and issues from exported JSON Schema |
| `catalog` | 8 | Catalog names and `catalog.validate` verdicts |
| `standard-catalog` | 85 | The React Native standard catalog, its props and params verdicts |
| `upstream-schemas` | 9 | Core's exported zod schemas, embedded in the package |
| `actions` | 23 | `resolveAction`, `interpolateString`, action builders, `executeAction` |
| `state-store` | 9 | `createStateStore` results, notifications and snapshot identity |
| `streaming` | 78 | SpecStream lines, spec patches, compilers, mixed streams, the AI SDK transform, nested specs, message parts, `useUIStream` |
| `render` | 34 | The normalised render tree from the React renderer, state, action log, diagnostics, confirmations and field states after every step of a scenario |

The render harness renders each scenario with the real `JSONUIProvider` and `Renderer` in jsdom and walks React's fibre tree to build a normalised tree: element ID, component type, resolved props, bindings, children, slots and status (rendered, hidden, no renderer or failed). The Swift runtime builds the same tree before SwiftUI draws it.

Each golden records the upstream versions and the SHA-256 of its corpus. The Swift tests fail when a golden is missing, when its corpus changed, or when the pinned versions in `Conformance/package.json` change without new goldens. `make goldens-check` fails when the goldens or the embedded upstream documents differ from what the pinned packages produce.

## Known divergences

The port matches upstream except where JavaScript and Swift cannot behave the same, or where matching upstream would crash. Each divergence with a golden is recorded in `Tests/ConformanceTests/Support/Divergences.swift` and reported as a known issue rather than a pass.

| Area | Upstream | Swift | Golden |
|---|---|---|---|
| Prototype keys | A state path such as `/toString` reads the inherited `Object.prototype` function. | Reads undefined. JSON values have no prototype. | `paths`: "get: prototype-like key" |
| Regular expressions with astral characters | `pattern` checks without the `u` flag match UTF-16 code units, so `.` matches half an emoji. | `NSRegularExpression` matches whole code points. | `validation`: 2 cases |
| Shared objects after `copy` or `move` | `applySpecPatch` and `useUIStream` copy by reference, so changing one copy changes both, and props objects of earlier snapshots change too. | Copies are independent values. | `streaming`: "applySpec: move and copy" |
| Exported schema ambiguities | `min(n).max(n)` and `length(n)` export the same JSON Schema; the export lists `minLength` before `pattern`; a top-level `optional()` cannot be expressed. | The JSON Schema import reads equal bounds as `length(n)` (a different message), reports the two issues in the other order, and rejects a top-level undefined. JSON input never holds undefined. | `schemas`: 4 cases |
| Lone surrogates | A JSON string escape such as `"\ud800"` keeps the lone surrogate. | Becomes U+FFFD, because a Swift string cannot hold it. | None |
| AI SDK transform text deltas | One `text-delta` per UTF-16 code unit. | One per Unicode scalar, for the same reason. Text without astral characters is identical. | None |
| Cyclic specs | React renders the cycle until the JavaScript heap runs out and the process crashes. | The repeated element throws, so the element that reached it fails like a throwing component and the rest renders. | None (`CycleTests`) |
| Handler start on older systems | An action handler starts synchronously when its action runs. | Same on iOS 26 and macOS 26 (`Task.immediate`). On earlier systems the handler starts on the next main-actor turn. | Render goldens run on macOS 26 |
| Error escaping every boundary | React unmounts the whole tree, providers included, so a later render starts from the initial state. | `Runtime.renderError` is set and the tree is cleared, but the runtime and its state stay. | `render`: "error in the root element escapes every boundary" matches within the scenario |
| Diagnostics | `console.warn` and `console.error`. | `Diagnostics`, which logs to the unified log unless a handler is bound. Messages are the same text. | All suites compare messages |
| Render counting and object identity | Some React tests count renders or compare object identity. | Not observable. SwiftUI decides when bodies run, and values have no identity. | N/A tests above |

## React and React Native renderers

The Swift runtime follows the React renderer, which does more than the React Native renderer in 0.21.1. A spec written for React Native renders the same way in Swift except for these differences in the React Native renderer:

- It does not resolve `$computed` expressions or directives, has no element `watch` support, and ignores `slots`.
- Its `repeat` has no item filter: a `$item` or `$index` condition on the repeat element does not filter items.
- Its `ActionProvider` has no action observer and no `validateForm` built-in.
- Its error boundary renders nothing for a failed element and never resets. The React renderer, and this port, reset the boundary when the element changes.
- Its `Renderer` includes the standard components by default (`includeStandard`). In Swift, use `Registry.standard` or `registry.includingStandard()`, because the UI target cannot depend on the standard target.
- Its `useUIStream` is the one ported (`UIStream`): it accepts a custom `fetch`, can validate and repair (`validate`, `maxRetries`), has `stop()`, and does not read `{"__meta": "usage"}` lines. The React package's `useUIStream` reports token usage instead and has no repair loop.

## Docs and code disagreements

Where the upstream docs and code disagree, this port follows the code.

- **Standard component props.** The prop tables in the React Native docs (`apps/web/content/docs/api/react-native.mdx`) and README do not match `standardComponentDefinitions`. The port uses the code's props:

  | Component | Docs | Code |
  |---|---|---|
  | Container | `background`, `borderColor` | `backgroundColor`, no border colour |
  | Row, Column | `align`, `justify`, `wrap` | `alignItems`, `justifyContent`, `flexWrap` |
  | ScrollContainer | `direction` | `horizontal`, `showsScrollIndicator` |
  | SafeArea | `edges` | `backgroundColor` only |
  | Image | `uri` | `src`, `alt` |
  | Avatar | `uri`, `fallback` | `src`, `initials`, `backgroundColor` |
  | Badge | `color`, `textColor` | `variant` |
  | Chip | `color` | `backgroundColor` |
  | TextInput | `secure` | `secureTextEntry` |

- **Heading levels.** The docs say levels 1 to 6. The code has `h1` to `h4`; any other level falls back to React Native's 14 point text.
- **Pressable, Button and ListItem actions.** The docs give these components `action` and `actionParams` props. The code has no such props: they emit `press` and the element's `on.press` binding runs. The README's `actionParams` field is also not part of the action binding format, which uses `params`.
- **Bound inputs.** The docs say to bind `Slider` and `SearchBar` values with `$bindState`. In the code `Slider` only displays its value (and ignores `step`), and `SearchBar` never writes its value.
- **Declared events.** The catalog declares `submit`, `focus` and `blur` for `TextInput` and `change` for `Switch` and `Checkbox`, but the components never emit them.
- **Examples.** Most `example` props in `standardComponentDefinitions` fail their own props schema, because every nullable prop is a required key. The `standard-catalog` goldens record these verdicts.
- **Actions.** `standardActionDefinitions` declares `setState`, `pushState` and `removeState` (built into the action provider) but not `setData`, which `createStandardActionHandlers` implements. `showAlert` buttons declare an `action`, which the handler ignores.
- **`useAction`.** The README describes `useAction(name)`. The code takes an action binding.

## Excluded features

| Feature | Reason |
|---|---|
| AI prompt generation (`catalog.prompt`, `promptTemplate`, prompt rules) | Out of scope by request. No renderer behaviour depends on it. |
| `catalog.jsonSchema()` | Exports JSON Schema for LLM structured output, part of generation. Swift imports catalogs from JSON Schema instead. |
| `experimental_composeSpec` and `experimental_createEvaluator` | Experimental AI composition through a model gateway. |
| Code generation (`@json-render/codegen`) | Out of scope by request. |
| Devtools (`@json-render/devtools` and the devtools renderers, `data-jr-key` attributes) | Out of scope by request. The action observer the devtools use is ported. |
| AI SDK chat hooks (`useChatUI`, `useJsonRenderMessage`) | Tied to the Vercel AI SDK's React hooks. The message part helpers they build on are ported (`MessageParts`). |
| `catalog.prompt`-only schema fields such as `defaultRules` | Kept on `RendererSchema` for parity, but unused because prompts are excluded. |
| Other renderers and integrations (Vue, Svelte, Solid, image, Ink, React Email, React PDF, React Three Fiber, Remotion, shadcn, Next, TanStack Start, MCP, YAML) | Not part of the requested targets. |
| State library adapters (Jotai, Redux, Zustand, XState) | JavaScript libraries. Swift hosts pass their own `StateStore`. |
| Server rendering snapshots (`getServerSnapshot`) | A React server rendering concern. |

## Upstream test case list

Every in-scope upstream case, with the Swift test that ports it or the reason it does not apply. Names join `describe` blocks with ›.

### `packages/core/src/actions.test.ts`

27 cases: 27 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| onSuccess/onError schemas › keeps params on the onSuccess action form | Passing | `ActionTests.swift` |
| onSuccess/onError schemas › keeps params on the onError action form | Passing | `ActionTests.swift` |
| interpolateString › interpolates ${path} expressions | Passing | `ActionTests.swift` |
| interpolateString › returns string unchanged when no variables | Passing | `ActionTests.swift` |
| interpolateString › replaces missing values with empty string | Passing | `ActionTests.swift` |
| interpolateString › handles multiple occurrences of same variable | Passing | `ActionTests.swift` |
| resolveAction › resolves literal params | Passing | `ActionTests.swift` |
| resolveAction › resolves dynamic $state params | Passing | `ActionTests.swift` |
| resolveAction › passes a resolved dotted email to a form action handler | Passing | `ActionTests.swift` |
| resolveAction › interpolates confirmation messages | Passing | `ActionTests.swift` |
| resolveAction › preserves onSuccess and onError handlers | Passing | `ActionTests.swift` |
| executeAction › calls the handler with resolved params | Passing | `ActionTests.swift` |
| executeAction › handles onSuccess with navigate | Passing | `ActionTests.swift` |
| executeAction › handles onSuccess with set | Passing | `ActionTests.swift` |
| executeAction › handles onSuccess with action | Passing | `ActionTests.swift` |
| executeAction › handles onSuccess with action and params | Passing | `ActionTests.swift` |
| executeAction › handles onError with set | Passing | `ActionTests.swift` |
| executeAction › handles onError with action | Passing | `ActionTests.swift` |
| executeAction › handles onError with action and params | Passing | `ActionTests.swift` |
| executeAction › re-throws error when no onError handler | Passing | `ActionTests.swift` |
| actionBinding helper › simple › creates binding with action only | Passing | `ActionTests.swift` |
| actionBinding helper › simple › creates binding with params | Passing | `ActionTests.swift` |
| actionBinding helper › withConfirm › creates binding with confirmation | Passing | `ActionTests.swift` |
| actionBinding helper › withConfirm › creates binding with confirmation and params | Passing | `ActionTests.swift` |
| actionBinding helper › withSuccess › creates binding with navigate success handler | Passing | `ActionTests.swift` |
| actionBinding helper › withSuccess › creates binding with set success handler | Passing | `ActionTests.swift` |
| actionBinding helper › withSuccess › creates binding with success handler and params | Passing | `ActionTests.swift` |

### `packages/core/src/action-observer.test.ts`

4 cases: 4 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| action observer registry › fires onDispatch for every registered observer | Passing | `ActionObserverTests.swift` |
| action observer registry › fires onSettle with the same id as dispatch | Passing | `ActionObserverTests.swift` |
| action observer registry › isolates observer throws | Passing | `ActionObserverTests.swift` |
| action observer registry › returns unique dispatch ids | Passing | `ActionObserverTests.swift` |

### `packages/core/src/directives.test.ts`

19 cases: 19 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| defineDirective › returns the definition unchanged | Passing | `DirectiveTests.swift` |
| defineDirective › throws when name does not start with $ | Passing | `DirectiveTests.swift` |
| defineDirective › throws when name conflicts with a built-in key | Passing | `DirectiveTests.swift` |
| createDirectiveRegistry › creates a Map from an array of definitions | Passing | `DirectiveTests.swift` |
| createDirectiveRegistry › returns an empty Map for an empty array | Passing | `DirectiveTests.swift` |
| findDirective › finds a matching directive | Passing | `DirectiveTests.swift` |
| findDirective › returns undefined for non-matching objects | Passing | `DirectiveTests.swift` |
| findDirective › returns undefined when registry is undefined | Passing | `DirectiveTests.swift` |
| findDirective › returns undefined for empty registry | Passing | `DirectiveTests.swift` |
| findDirective › ignores $ keys not in registry | Passing | `DirectiveTests.swift` |
| findDirective › throws when multiple directive keys match | Passing | `DirectiveTests.swift` |
| resolvePropValue with custom directives › resolves a custom directive | Passing | `DirectiveTests.swift` |
| resolvePropValue with custom directives › resolves a directive with $state sub-value | Passing | `DirectiveTests.swift` |
| resolvePropValue with custom directives › resolves nested directives (composition) | Passing | `DirectiveTests.swift` |
| resolvePropValue with custom directives › resolves directives inside object props | Passing | `DirectiveTests.swift` |
| resolvePropValue with custom directives › resolves directives inside arrays | Passing | `DirectiveTests.swift` |
| resolvePropValue with custom directives › falls through to plain object resolution when no directive matches | Passing | `DirectiveTests.swift` |
| resolvePropValue with custom directives › cannot register a directive that shadows a built-in key | Passing | `DirectiveTests.swift` |
| resolvePropValue with custom directives › works without directives in context (backward compat) | Passing | `DirectiveTests.swift` |

### `packages/core/src/props.test.ts`

61 cases: 61 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| resolvePropValue › literals › passes through strings | Passing | `PropExpressionTests.swift` |
| resolvePropValue › literals › passes through numbers | Passing | `PropExpressionTests.swift` |
| resolvePropValue › literals › passes through booleans | Passing | `PropExpressionTests.swift` |
| resolvePropValue › literals › passes through null | Passing | `PropExpressionTests.swift` |
| resolvePropValue › literals › passes through undefined | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $state expressions › resolves a state path | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $state expressions › returns undefined for missing state path | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $state expressions › resolves nested state path | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $item expressions › resolves a field from the repeat item | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $item expressions › resolves "/" to the whole item | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $item expressions › resolves nested field from item | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $item expressions › returns undefined when no repeat item in context | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $item expressions › returns undefined for missing field on item | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $index expressions › returns the current repeat index | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $index expressions › returns 0 for first item | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $index expressions › returns undefined when no repeat index in context | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $cond/$then/$else expressions › returns $then when condition is true | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $cond/$then/$else expressions › returns $else when condition is false | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $cond/$then/$else expressions › handles eq condition | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $cond/$then/$else expressions › handles nested expression in $then/$else | Passing | `PropExpressionTests.swift` |
| resolvePropValue › $cond/$then/$else expressions › handles array condition (implicit AND) | Passing | `PropExpressionTests.swift` |
| resolvePropValue › nested objects and arrays › resolves expressions inside plain objects | Passing | `PropExpressionTests.swift` |
| resolvePropValue › nested objects and arrays › resolves expressions inside arrays | Passing | `PropExpressionTests.swift` |
| resolvePropValue › nested objects and arrays › resolves deeply nested expressions | Passing | `PropExpressionTests.swift` |
| resolveElementProps › resolves all props in an element | Passing | `PropExpressionTests.swift` |
| resolveElementProps › resolves mixed expressions and literals | Passing | `PropExpressionTests.swift` |
| resolveElementProps › returns empty object for empty props | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolvePropValue with $bindState › resolves to the state value at the path | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolvePropValue with $bindState › returns undefined for missing path | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolvePropValue with $bindItem › resolves item field using repeatBasePath | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolvePropValue with $bindItem › handles "/" as the full item path | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolvePropValue with $bindItem › returns undefined when no repeatBasePath | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolveBindings › extracts $bindState paths from props | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolveBindings › returns undefined when no bind expressions | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolveBindings › handles multiple $bindState props | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolveBindings › resolves $bindItem paths using repeatBasePath | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolveBindings › ignores non-bind dynamic expressions | Passing | `PropExpressionTests.swift` |
| $bindState expressions › resolveBindings › handles mixed $bindState and $bindItem props | Passing | `PropExpressionTests.swift` |
| resolveActionParam › resolves $item to an absolute state path via repeatBasePath | Passing | `PropExpressionTests.swift` |
| resolveActionParam › resolves $item with empty string to the repeatBasePath itself | Passing | `PropExpressionTests.swift` |
| resolveActionParam › returns undefined for $item when no repeatBasePath | Passing | `PropExpressionTests.swift` |
| resolveActionParam › resolves $index to the current repeat index | Passing | `PropExpressionTests.swift` |
| resolveActionParam › returns undefined for $index when no repeat context | Passing | `PropExpressionTests.swift` |
| resolveActionParam › delegates $state expressions to resolvePropValue | Passing | `PropExpressionTests.swift` |
| resolveActionParam › passes through literal strings | Passing | `PropExpressionTests.swift` |
| resolveActionParam › passes through literal numbers | Passing | `PropExpressionTests.swift` |
| resolveActionParam › passes through null | Passing | `PropExpressionTests.swift` |
| $computed expressions › calls a registered function with resolved args | Passing | `PropExpressionTests.swift` |
| $computed expressions › calls function with no args | Passing | `PropExpressionTests.swift` |
| $computed expressions › returns undefined for unknown function | Passing | `PropExpressionTests.swift` |
| $computed expressions › returns undefined when no functions in context | Passing | `PropExpressionTests.swift` |
| $computed expressions › deduplicates warnings for the same unknown function | Passing | `PropExpressionTests.swift` |
| $computed expressions › resolves nested expressions in args | Passing | `PropExpressionTests.swift` |
| $template expressions › interpolates state values into a string | Passing | `PropExpressionTests.swift` |
| $template expressions › replaces missing paths with empty string | Passing | `PropExpressionTests.swift` |
| $template expressions › handles template with no interpolations | Passing | `PropExpressionTests.swift` |
| $template expressions › handles multiple references to the same path | Passing | `PropExpressionTests.swift` |
| $template expressions › converts non-string values to strings | Passing | `PropExpressionTests.swift` |
| $template expressions › resolves bare names against state model when not in repeat | Passing | `PropExpressionTests.swift` |
| $template expressions › resolves bare names against repeat item first | Passing | `PropExpressionTests.swift` |
| $template expressions › falls back to state model for bare names not in repeat item | Passing | `PropExpressionTests.swift` |

### `packages/core/src/repeat-schema-parity.test.ts`

1 cases: 1 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| renderer schema repeat parity › %s declares repeat as an optional element field | Passing | `SchemaTests.swift` (react and react-native; the other renderers are not part of this port) |

### `packages/core/src/schema.test.ts`

46 cases: 18 passing, 28 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| defineSchema › creates a schema with spec and catalog definition | Passing | `SchemaTests.swift` |
| defineSchema › accepts promptTemplate option | N/A | Prompt templates only shape AI prompts. AI prompt generation is excluded. |
| defineSchema › accepts defaultRules option | Passing | `SchemaTests.swift` |
| defineSchema › exposes createCatalog method | Passing | `SchemaTests.swift` |
| defineCatalog › creates catalog with componentNames and actionNames | Passing | `SchemaTests.swift` |
| defineCatalog › handles empty components and actions | Passing | `SchemaTests.swift` |
| defineCatalog › is equivalent to schema.createCatalog | Passing | `SchemaTests.swift` |
| defineCatalog › exposes the schema on the catalog | Passing | `SchemaTests.swift` |
| defineCatalog › exposes catalog data | Passing | `SchemaTests.swift` |
| catalog.prompt › includes AVAILABLE COMPONENTS section | N/A | AI prompt generation is excluded. |
| catalog.prompt › formats z.literal() as quoted value | N/A | AI prompt generation is excluded. |
| catalog.prompt › formats z.default() by unwrapping to inner type | N/A | AI prompt generation is excluded. |
| catalog.prompt › formats z.record() as Record<K, V> | N/A | AI prompt generation is excluded. |
| catalog.prompt › includes AVAILABLE ACTIONS when present | N/A | AI prompt generation is excluded. |
| catalog.prompt › omits AVAILABLE ACTIONS when there are none | N/A | AI prompt generation is excluded. |
| catalog.prompt › uses custom system message when provided | N/A | AI prompt generation is excluded. |
| catalog.prompt › appends customRules to prompt | N/A | AI prompt generation is excluded. |
| catalog.prompt › generates inline mode prompt when mode is inline | N/A | AI prompt generation is excluded. |
| catalog.prompt › generates standalone mode prompt by default | N/A | AI prompt generation is excluded. |
| catalog.prompt › accepts deprecated 'chat' as alias for 'inline' | N/A | AI prompt generation is excluded. |
| catalog.prompt › accepts deprecated 'generate' as alias for 'standalone' | N/A | AI prompt generation is excluded. |
| catalog.prompt › uses actual catalog component names in examples | N/A | AI prompt generation is excluded. |
| catalog.prompt › does not include hardcoded component names not in catalog | N/A | AI prompt generation is excluded. |
| catalog.prompt › generates example props from Zod schemas | N/A | AI prompt generation is excluded. |
| catalog.prompt › uses explicit example over Zod-generated values | N/A | AI prompt generation is excluded. |
| catalog.prompt › uses custom promptTemplate when schema has one | N/A | AI prompt generation is excluded. |
| catalog.prompt › includes defaultRules from schema in the RULES section | N/A | AI prompt generation is excluded. |
| catalog.prompt › contains sections for state, repeat, actions, visibility, and dynamic props | N/A | AI prompt generation is excluded. |
| catalog.validate › returns data assignable to Spec | Passing | `SchemaTests.swift` |
| catalog.validate › validates a valid spec | Passing | `SchemaTests.swift` |
| catalog.validate › accepts elements without visible regardless of zod version (z.any() keys became nonoptional in zod 4.4) | Passing | `SchemaTests.swift` |
| catalog.validate › still requires children on every element | Passing | `SchemaTests.swift` |
| catalog.validate › rejects spec with wrong root type | Passing | `SchemaTests.swift` |
| catalog.validate › rejects spec with missing root | Passing | `SchemaTests.swift` |
| catalog.validate › rejects spec with invalid component type | Passing | `SchemaTests.swift` |
| catalog.validate › returns data on success | Passing | `SchemaTests.swift` |
| catalog.jsonSchema › returns a JSON Schema object | N/A | Exports JSON Schema for LLM structured output, part of AI generation, which is excluded. Swift imports catalogs from JSON Schema instead. |
| catalog.jsonSchema › returns a non-empty object for a catalog with components | N/A | Exports JSON Schema for LLM structured output, part of AI generation, which is excluded. Swift imports catalogs from JSON Schema instead. |
| catalog.jsonSchema › strict mode (LLM structured output compatible) › sets additionalProperties: false on all nested objects | N/A | Exports JSON Schema for LLM structured output, part of AI generation, which is excluded. Swift imports catalogs from JSON Schema instead. |
| catalog.jsonSchema › strict mode (LLM structured output compatible) › does not emit propertyNames | N/A | Exports JSON Schema for LLM structured output, part of AI generation, which is excluded. Swift imports catalogs from JSON Schema instead. |
| catalog.jsonSchema › strict mode (LLM structured output compatible) › lists all properties in required (optional uses nullable) | N/A | Exports JSON Schema for LLM structured output, part of AI generation, which is excluded. Swift imports catalogs from JSON Schema instead. |
| catalog.jsonSchema › strict mode (LLM structured output compatible) › converts record types without additionalProperties schema value | N/A | Exports JSON Schema for LLM structured output, part of AI generation, which is excluded. Swift imports catalogs from JSON Schema instead. |
| catalog.jsonSchema › strict mode (LLM structured output compatible) › wraps optional properties with anyOf nullable | N/A | Exports JSON Schema for LLM structured output, part of AI generation, which is excluded. Swift imports catalogs from JSON Schema instead. |
| catalog.jsonSchema › strict mode (LLM structured output compatible) › does not affect default (non-strict) output | N/A | Exports JSON Schema for LLM structured output, part of AI generation, which is excluded. Swift imports catalogs from JSON Schema instead. |
| catalog.zodSchema › returns a Zod schema that validates valid specs | Passing | `SchemaTests.swift` |
| catalog.zodSchema › returns a Zod schema that rejects invalid specs | Passing | `SchemaTests.swift` |

### `packages/core/src/spec-validator.test.ts`

38 cases: 38 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| validateSpec › returns valid for a correct spec | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects missing root | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects root_not_found | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects empty spec | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects missing_child | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects missing children in named slots | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects visible_in_props | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects on_in_props | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects repeat_in_props | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects watch_in_props | Passing | `SpecValidatorTests.swift` |
| validateSpec › detects orphaned elements when checkOrphans is true | Passing | `SpecValidatorTests.swift` |
| validateSpec › treats named slot children as reachable | Passing | `SpecValidatorTests.swift` |
| repeat validation › rejects repeat without children | Passing | `SpecValidatorTests.swift` |
| repeat validation › rejects repeat over a non-array state value | Passing | `SpecValidatorTests.swift` |
| repeat validation › rejects repeat over a missing state path when state is provided | Passing | `SpecValidatorTests.swift` |
| repeat validation › accepts a well-formed repeat and skips state checks when no state is provided | Passing | `SpecValidatorTests.swift` |
| repeat validation › accepts a nested repeat relative to the enclosing item | Passing | `SpecValidatorTests.swift` |
| repeat validation › rejects a relative repeat outside repeat scope | Passing | `SpecValidatorTests.swift` |
| repeat validation › does not give named slots the repeat scope created by their element | Passing | `SpecValidatorTests.swift` |
| repeat validation › accepts relative repeat structure when the outer sample array is empty | Passing | `SpecValidatorTests.swift` |
| repeat validation › rejects a nested relative repeat that does not resolve to an array | Passing | `SpecValidatorTests.swift` |
| repeat validation › does not duplicate repeat issues for the same structural context | Passing | `SpecValidatorTests.swift` |
| repeat validation › validates a reused repeat separately inside and outside scope | Passing | `SpecValidatorTests.swift` |
| repeat validation › terminates repeat validation for cyclic child graphs | Passing | `SpecValidatorTests.swift` |
| visible condition validation › accepts documented forms | Passing | `SpecValidatorTests.swift` |
| visible condition validation › rejects conditions mixing $state and $item (silently hidden at runtime) | Passing | `SpecValidatorTests.swift` |
| visible condition validation › rejects unknown condition shapes | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › prunes children references to undefined elements | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › leaves intact children untouched | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › prunes undefined children from named slots | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › does not prune a repeat container down to zero children | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › withholds lossy fixes when options.lossy is false | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › classifies field relocations as lossless | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › moves visible from props to element level | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › moves on from props to element level | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › moves repeat from props to element level | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › moves watch from props to element level | Passing | `SpecValidatorTests.swift` |
| autoFixSpec › returns no fixes for a correct spec | Passing | `SpecValidatorTests.swift` |

### `packages/core/src/state-store.test.ts`

21 cases: 19 passing, 2 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| createStateStore › creates a store with initial state | Passing | `StateStoreTests.swift` |
| createStateStore › set notifies subscribers | Passing | `StateStoreTests.swift` |
| createStateStore › set skips notification when value is unchanged | Passing | `StateStoreTests.swift` |
| createStateStore › update notifies subscribers once | Passing | `StateStoreTests.swift` |
| createStateStore › update skips notification when no values changed | Passing | `StateStoreTests.swift` |
| createStateStore › unsubscribe stops notifications | Passing | `StateStoreTests.swift` |
| createStateStore › getSnapshot returns a new reference after mutation | Passing | `StateStoreTests.swift` |
| createStateStore › getSnapshot returns same reference when set is a no-op | Passing | `StateStoreTests.swift` |
| createStateStore › set on nested path does not mutate previous snapshot | Passing | `StateStoreTests.swift` |
| createStateStore › update on nested paths does not mutate previous snapshot | Passing | `StateStoreTests.swift` |
| createStateStore › set preserves structural sharing for untouched branches | Passing | `StateStoreTests.swift` |
| createStateStore › getServerSnapshot returns the same state as getSnapshot | N/A | Server rendering snapshots are a React concern. |
| flattenToPointers › flattens top-level keys | Passing | `StateStoreTests.swift` |
| flattenToPointers › flattens nested plain objects | Passing | `StateStoreTests.swift` |
| flattenToPointers › preserves arrays as leaf values | Passing | `StateStoreTests.swift` |
| flattenToPointers › preserves null as a leaf value | Passing | `StateStoreTests.swift` |
| flattenToPointers › handles deeply nested objects | Passing | `StateStoreTests.swift` |
| flattenToPointers › returns empty object for empty input | Passing | `StateStoreTests.swift` |
| flattenToPointers › handles mixed nesting | Passing | `StateStoreTests.swift` |
| flattenToPointers › stops recursion on circular references via seen set | N/A | A JSON value cannot contain itself. "treats an object seen earlier in the walk as a leaf" covers shared storage instead. |
| flattenToPointers › caps recursion at depth limit | Passing | `StateStoreTests.swift` |

### `packages/core/src/types.test.ts`

114 cases: 113 passing, 1 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| findFormValue › keeps a direct %s literal | Passing | `TypesTests.swift` |
| findFormValue › keeps a dotted-key %s literal | Passing | `TypesTests.swift` |
| findFormValue › treats a raw dotted parameter value as literal, even with matching state | Passing | `TypesTests.swift` |
| findFormValue › prefers a direct parameter over dotted parameters and state | Passing | `TypesTests.swift` |
| findFormValue › prefers a dotted parameter over state and skips undefined direct params | Passing | `TypesTests.swift` |
| findFormValue › keeps the first matching dotted parameter key, even if undefined | Passing | `TypesTests.swift` |
| findFormValue › finds exact and dotted flat state keys | Passing | `TypesTests.swift` |
| findFormValue › finds nested state with slash paths but not bare field names | Passing | `TypesTests.swift` |
| findFormValue › ignores nonmatching keys and returns undefined for omitted inputs | Passing | `TypesTests.swift` |
| findFormValue › preserves a direct %s value | Passing | `TypesTests.swift` |
| getByPath › gets nested values with JSON pointer paths | Passing | `TypesTests.swift` |
| getByPath › returns root object for empty or root path | Passing | `TypesTests.swift` |
| getByPath › returns undefined for missing paths | Passing | `TypesTests.swift` |
| getByPath › handles paths without leading slash | Passing | `TypesTests.swift` |
| getByPath › returns undefined when traversing through non-object | Passing | `TypesTests.swift` |
| getByPath › handles null values in path | Passing | `TypesTests.swift` |
| resolveRepeatStatePath › preserves string paths exactly | Passing | `TypesTests.swift` |
| resolveRepeatStatePath › resolves $item paths against the enclosing item path | Passing | `TypesTests.swift` |
| resolveRepeatStatePath › resolves an empty $item path to the enclosing item | Passing | `TypesTests.swift` |
| resolveRepeatStatePath › does not resolve $item outside repeat scope | Passing | `TypesTests.swift` |
| resolveRepeatStatePath › builds item paths without duplicate root separators | Passing | `TypesTests.swift` |
| setByPath › sets value at existing path | Passing | `TypesTests.swift` |
| setByPath › creates intermediate objects for deep paths | Passing | `TypesTests.swift` |
| setByPath › handles paths without leading slash | Passing | `TypesTests.swift` |
| setByPath › overwrites existing values | Passing | `TypesTests.swift` |
| setByPath › handles array-like paths | Passing | `TypesTests.swift` |
| resolveDynamicValue › resolves literal string values | Passing | `TypesTests.swift` |
| resolveDynamicValue › resolves literal number values | Passing | `TypesTests.swift` |
| resolveDynamicValue › resolves literal boolean values | Passing | `TypesTests.swift` |
| resolveDynamicValue › resolves $state references | Passing | `TypesTests.swift` |
| resolveDynamicValue › returns undefined for missing $state references | Passing | `TypesTests.swift` |
| resolveDynamicValue › returns undefined for null value | Passing | `TypesTests.swift` |
| resolveDynamicValue › returns undefined for undefined value | Passing | `TypesTests.swift` |
| JSON Pointer escaping (RFC 6901) › getByPath unescapes ~1 to / | Passing | `TypesTests.swift` |
| JSON Pointer escaping (RFC 6901) › getByPath unescapes ~0 to ~ | Passing | `TypesTests.swift` |
| JSON Pointer escaping (RFC 6901) › getByPath handles combined ~0 and ~1 escaping | Passing | `TypesTests.swift` |
| JSON Pointer escaping (RFC 6901) › setByPath unescapes ~1 to / in keys | Passing | `TypesTests.swift` |
| JSON Pointer escaping (RFC 6901) › setByPath unescapes ~0 to ~ in keys | Passing | `TypesTests.swift` |
| JSON Pointer escaping (RFC 6901) › getByPath reads array elements properly | Passing | `TypesTests.swift` |
| addByPath › adds a property to an object | Passing | `TypesTests.swift` |
| addByPath › replaces an existing object property (add semantics) | Passing | `TypesTests.swift` |
| addByPath › inserts into an array at a specific index | Passing | `TypesTests.swift` |
| addByPath › appends to an array with - (end-of-array) | Passing | `TypesTests.swift` |
| addByPath › inserts at index 0 of an array | Passing | `TypesTests.swift` |
| addByPath › creates intermediate objects | Passing | `TypesTests.swift` |
| removeByPath › deletes an object property | Passing | `TypesTests.swift` |
| removeByPath › removes an element from an array by index | Passing | `TypesTests.swift` |
| removeByPath › removes nested properties | Passing | `TypesTests.swift` |
| removeByPath › is a no-op for non-existent paths | Passing | `TypesTests.swift` |
| applySpecStreamPatch › add operation › adds a new object property | Passing | `TypesTests.swift` |
| applySpecStreamPatch › add operation › adds nested properties creating intermediates | Passing | `TypesTests.swift` |
| applySpecStreamPatch › add operation › inserts into array at index | Passing | `TypesTests.swift` |
| applySpecStreamPatch › add operation › appends to array with - | Passing | `TypesTests.swift` |
| applySpecStreamPatch › remove operation › removes an object property | Passing | `TypesTests.swift` |
| applySpecStreamPatch › remove operation › removes from array by index | Passing | `TypesTests.swift` |
| applySpecStreamPatch › replace operation › replaces an existing value | Passing | `TypesTests.swift` |
| applySpecStreamPatch › replace operation › replaces nested values | Passing | `TypesTests.swift` |
| applySpecStreamPatch › move operation › moves a value from one path to another | Passing | `TypesTests.swift` |
| applySpecStreamPatch › move operation › moves nested values | Passing | `TypesTests.swift` |
| applySpecStreamPatch › move operation › is a no-op if from is missing | Passing | `TypesTests.swift` |
| applySpecStreamPatch › copy operation › copies a value from one path to another | Passing | `TypesTests.swift` |
| applySpecStreamPatch › copy operation › copies complex values | Passing | `TypesTests.swift` |
| applySpecStreamPatch › copy operation › is a no-op if from is missing | Passing | `TypesTests.swift` |
| applySpecStreamPatch › test operation › succeeds when values match | Passing | `TypesTests.swift` |
| applySpecStreamPatch › test operation › succeeds for matching objects | Passing | `TypesTests.swift` |
| applySpecStreamPatch › test operation › succeeds for matching arrays | Passing | `TypesTests.swift` |
| applySpecStreamPatch › test operation › throws when values do not match | Passing | `TypesTests.swift` |
| applySpecStreamPatch › test operation › throws when path does not exist | Passing | `TypesTests.swift` |
| compileSpecStream › compiles a series of add patches | Passing | `TypesTests.swift` |
| compileSpecStream › handles remove operations | Passing | `TypesTests.swift` |
| compileSpecStream › handles replace operations | Passing | `TypesTests.swift` |
| compileSpecStream › handles move operations | Passing | `TypesTests.swift` |
| compileSpecStream › handles copy operations | Passing | `TypesTests.swift` |
| compileSpecStream › skips empty lines | Passing | `TypesTests.swift` |
| compileSpecStream › uses initial value | Passing | `TypesTests.swift` |
| createSpecStreamCompiler › processes chunks incrementally | Passing | `TypesTests.swift` |
| createSpecStreamCompiler › handles partial lines across chunks | Passing | `TypesTests.swift` |
| createSpecStreamCompiler › processes remaining buffer on getResult | Passing | `TypesTests.swift` |
| createSpecStreamCompiler › resets to clean state | Passing | `TypesTests.swift` |
| createSpecStreamCompiler › tracks all applied patches | Passing | `TypesTests.swift` |
| createSpecStreamCompiler › handles all RFC 6902 operations | Passing | `TypesTests.swift` |
| applySpecPatch › sets the root element | Passing | `TypesTests.swift` |
| applySpecPatch › adds an element to the elements map | Passing | `TypesTests.swift` |
| applySpecPatch › replaces an existing element | Passing | `TypesTests.swift` |
| applySpecPatch › removes an element | Passing | `TypesTests.swift` |
| applySpecPatch › adds state data | Passing | `TypesTests.swift` |
| applySpecPatch › returns the mutated spec | N/A | `Spec.apply` mutates a value type, so there is no returned reference to compare. |
| createMixedStreamParser › classifies JSONL lines as patches | Passing | `TypesTests.swift` |
| createMixedStreamParser › classifies non-JSONL lines as text | Passing | `TypesTests.swift` |
| createMixedStreamParser › handles mixed text and JSONL | Passing | `TypesTests.swift` |
| createMixedStreamParser › buffers partial lines across chunks | Passing | `TypesTests.swift` |
| createMixedStreamParser › flushes remaining buffer on flush() | Passing | `TypesTests.swift` |
| createMixedStreamParser › flushes text buffer on flush() | Passing | `TypesTests.swift` |
| createMixedStreamParser › skips empty lines | Passing | `TypesTests.swift` |
| nestedToFlat › converts a single node with no children | Passing | `TypesTests.swift` |
| nestedToFlat › converts a tree with children | Passing | `TypesTests.swift` |
| nestedToFlat › converts nested named slots to flat element references | Passing | `TypesTests.swift` |
| nestedToFlat › hoists state from root node | Passing | `TypesTests.swift` |
| nestedToFlat › preserves extra fields like visible and on | Passing | `TypesTests.swift` |
| nestedToFlat › handles deeply nested trees | Passing | `TypesTests.swift` |
| nestedToFlat › returns empty elements for empty children array | Passing | `TypesTests.swift` |
| nestedToFlat › does not hoist state from non-root nodes | Passing | `TypesTests.swift` |
| createJsonRenderTransform › passes prose text through as text-delta | Passing | `TypesTests.swift` |
| createJsonRenderTransform › classifies valid JSONL patches as data-spec (heuristic mode) | Passing | `TypesTests.swift` |
| createJsonRenderTransform › lines starting with { that are NOT patches are flushed as text | Passing | `TypesTests.swift` |
| createJsonRenderTransform › parses content inside ```spec fence as patches | Passing | `TypesTests.swift` |
| createJsonRenderTransform › handles mixed text + heuristic patches in single stream | Passing | `TypesTests.swift` |
| createJsonRenderTransform › non-text chunks pass through unchanged | Passing | `TypesTests.swift` |
| createJsonRenderTransform › flush behavior at end of stream | Passing | `TypesTests.swift` |
| createJsonRenderTransform › splits text blocks around spec data (text-start/text-end pairs) | Passing | `TypesTests.swift` |
| createJsonRenderTransform › flush closes an open text block when stream ends without text-end | Passing | `TypesTests.swift` |
| createJsonRenderTransform › consecutive patches do not produce empty text blocks | Passing | `TypesTests.swift` |
| createMixedStreamParser - fence mode › parses patches inside ```spec fence | Passing | `TypesTests.swift` |
| createMixedStreamParser - fence mode › fence delimiters are not emitted as text or patches | Passing | `TypesTests.swift` |

### `packages/core/src/validation.test.ts`

90 cases: 90 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| builtInValidationFunctions › required › passes for non-empty values | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › required › fails for empty values | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › email › passes for valid emails | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › email › fails for invalid emails | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › minLength › passes when string meets minimum length | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › minLength › fails when string is too short | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › minLength › fails for non-strings | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › minLength › fails when min is not provided | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › maxLength › passes when string meets maximum length | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › maxLength › fails when string exceeds maximum | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › pattern › passes when string matches pattern | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › pattern › fails when string does not match pattern | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › pattern › fails for invalid regex pattern | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › min › passes when number meets minimum | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › min › fails when number is below minimum | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › min › fails for non-numbers | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › max › passes when number meets maximum | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › max › fails when number exceeds maximum | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › numeric › passes for numbers | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › numeric › passes for numeric strings | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › numeric › fails for non-numeric values | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › numeric › fails for strings with trailing non-numeric characters | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › numeric › fails for empty and whitespace-only strings | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › url › passes for valid URLs | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › url › fails for invalid URLs | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › matches › passes when values match | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › matches › fails when values do not match | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › equalTo › passes when values are equal | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › equalTo › fails when values differ | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › passes when value is less than other | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › fails when value equals other | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › fails when value is greater than other | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › coerces numeric string vs number | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › fails coercion when non-numeric string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › passes for string comparison (ISO dates) | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › fails for equal strings | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › returns false when value is empty string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › returns false when other is empty string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › returns false when value is empty string vs non-empty string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › returns false when other is empty string vs non-empty string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › returns false when other is null | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › returns false when value is null | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › lessThan › returns false when other is undefined | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › passes when value is greater than other | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › fails when value equals other | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › fails when value is less than other | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › coerces numeric string vs number | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › fails coercion when non-numeric string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › passes for string comparison (ISO dates) | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › fails for lesser strings | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › returns false when value is empty string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › returns false when other is empty string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › returns false when value is empty string vs non-empty string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › returns false when other is empty string vs non-empty string | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › returns false when other is null | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › returns false when value is undefined | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › greaterThan › returns false when value is null | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › requiredIf › passes when condition is falsy (field not required) | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › requiredIf › fails when condition is truthy and value is empty | Passing | `ValidationTests.swift` |
| builtInValidationFunctions › requiredIf › passes when condition is truthy and value is present | Passing | `ValidationTests.swift` |
| runValidationCheck › runs a validation check and returns result | Passing | `ValidationTests.swift` |
| runValidationCheck › resolves dynamic args from stateModel | Passing | `ValidationTests.swift` |
| runValidationCheck › returns valid for unknown functions with warning | Passing | `ValidationTests.swift` |
| runValidationCheck › uses custom validation functions | Passing | `ValidationTests.swift` |
| runValidation › runs all validation checks | Passing | `ValidationTests.swift` |
| runValidation › collects all errors | Passing | `ValidationTests.swift` |
| runValidation › skips validation when enabled condition is false | Passing | `ValidationTests.swift` |
| runValidation › runs validation when enabled condition is true | Passing | `ValidationTests.swift` |
| runValidation › returns valid when no checks defined | Passing | `ValidationTests.swift` |
| check helper › required › creates required check with default message | Passing | `ValidationTests.swift` |
| check helper › required › creates required check with custom message | Passing | `ValidationTests.swift` |
| check helper › email › creates email check with default message | Passing | `ValidationTests.swift` |
| check helper › minLength › creates minLength check with args | Passing | `ValidationTests.swift` |
| check helper › minLength › uses default message | Passing | `ValidationTests.swift` |
| check helper › maxLength › creates maxLength check with args | Passing | `ValidationTests.swift` |
| check helper › pattern › creates pattern check | Passing | `ValidationTests.swift` |
| check helper › min › creates min check | Passing | `ValidationTests.swift` |
| check helper › max › creates max check | Passing | `ValidationTests.swift` |
| check helper › url › creates url check | Passing | `ValidationTests.swift` |
| check helper › numeric › creates numeric check with default message | Passing | `ValidationTests.swift` |
| check helper › numeric › creates numeric check with custom message | Passing | `ValidationTests.swift` |
| check helper › matches › creates matches check with path reference | Passing | `ValidationTests.swift` |
| check helper › equalTo › creates equalTo check with path reference | Passing | `ValidationTests.swift` |
| check helper › lessThan › creates lessThan check with path reference | Passing | `ValidationTests.swift` |
| check helper › greaterThan › creates greaterThan check with path reference | Passing | `ValidationTests.swift` |
| check helper › requiredIf › creates requiredIf check with path reference | Passing | `ValidationTests.swift` |
| deep arg resolution › resolves nested $state refs in validation args | Passing | `ValidationTests.swift` |
| deep arg resolution › resolves $state in cross-field lessThan check | Passing | `ValidationTests.swift` |
| deep arg resolution › resolves $state in requiredIf check | Passing | `ValidationTests.swift` |
| deep arg resolution › passes requiredIf when condition is false | Passing | `ValidationTests.swift` |

### `packages/core/src/visibility.test.ts`

79 cases: 79 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| evaluateVisibility › undefined / boolean › returns true for undefined | Passing | `VisibilityTests.swift` |
| evaluateVisibility › undefined / boolean › returns true for true | Passing | `VisibilityTests.swift` |
| evaluateVisibility › undefined / boolean › returns false for false | Passing | `VisibilityTests.swift` |
| evaluateVisibility › truthiness ($state only) › returns true when state path is truthy (boolean) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › truthiness ($state only) › returns true when state path is truthy (number) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › truthiness ($state only) › returns true when state path is truthy (string) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › truthiness ($state only) › returns false when state path is falsy (boolean) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › truthiness ($state only) › returns false when state path is falsy (zero) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › truthiness ($state only) › returns false when state path is falsy (empty string) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › truthiness ($state only) › returns false when state path is undefined | Passing | `VisibilityTests.swift` |
| evaluateVisibility › truthiness ($state only) › returns false for missing path | Passing | `VisibilityTests.swift` |
| evaluateVisibility › negation ($state + not) › returns false when state path is truthy | Passing | `VisibilityTests.swift` |
| evaluateVisibility › negation ($state + not) › returns true when state path is falsy | Passing | `VisibilityTests.swift` |
| evaluateVisibility › negation ($state + not) › not inverts an eq condition | Passing | `VisibilityTests.swift` |
| evaluateVisibility › negation ($state + not) › not inverts a gt condition | Passing | `VisibilityTests.swift` |
| evaluateVisibility › equality ($state + eq) › returns true when values match (number) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › equality ($state + eq) › returns false when values do not match | Passing | `VisibilityTests.swift` |
| evaluateVisibility › equality ($state + eq) › returns true when values match (string) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › equality ($state + eq) › supports state-to-state comparison | Passing | `VisibilityTests.swift` |
| evaluateVisibility › equality ($state + eq) › state-to-state comparison fails when different | Passing | `VisibilityTests.swift` |
| evaluateVisibility › inequality ($state + neq) › returns true when values differ | Passing | `VisibilityTests.swift` |
| evaluateVisibility › inequality ($state + neq) › returns false when values are equal | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › gt: returns true when greater | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › gt: returns false when less | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › gt: returns false when equal | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › gte: returns true when equal | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › gte: returns true when greater | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › gte: returns false when less | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › lt: returns true when less | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › lt: returns false when greater | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › lt: returns false when equal | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › lte: returns true when equal | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › lte: returns true when less | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › lte: returns false when greater | Passing | `VisibilityTests.swift` |
| evaluateVisibility › numeric comparisons › returns false for non-numeric values | Passing | `VisibilityTests.swift` |
| evaluateVisibility › dynamic path references in comparison › eq with $state reference on right | Passing | `VisibilityTests.swift` |
| evaluateVisibility › dynamic path references in comparison › lt with $state reference on right | Passing | `VisibilityTests.swift` |
| evaluateVisibility › array (implicit AND) › returns true when all conditions are true | Passing | `VisibilityTests.swift` |
| evaluateVisibility › array (implicit AND) › returns false when one condition is false | Passing | `VisibilityTests.swift` |
| evaluateVisibility › array (implicit AND) › returns false when all conditions are false | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $and condition (explicit AND) › returns true when all children are true | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $and condition (explicit AND) › returns false when one child is false | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $and condition (explicit AND) › returns false when all children are false | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $and condition (explicit AND) › supports nested $or inside $and | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $and condition (explicit AND) › supports booleans inside $and | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $or condition › returns true when at least one child is true | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $or condition › returns true when all children are true | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $or condition › returns false when all children are false | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $or condition › supports nested arrays (AND inside OR) | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $or condition › supports booleans inside $or | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $item conditions › $item truthiness check | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $item conditions › $item falsy check | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $item conditions › $item equality check | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $item conditions › $item equality check fails | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $item conditions › $item root reference | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $item conditions › $item with not | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $item conditions › $item returns false when no repeat scope | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $index conditions › $index equality check | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $index conditions › $index equality check fails | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $index conditions › $index gt check | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $index conditions › $index truthiness | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $index conditions › $index zero is falsy | Passing | `VisibilityTests.swift` |
| evaluateVisibility › $index conditions › $index with not | Passing | `VisibilityTests.swift` |
| visibility helper › always is true | Passing | `VisibilityTests.swift` |
| visibility helper › never is false | Passing | `VisibilityTests.swift` |
| visibility helper › when creates a $state condition | Passing | `VisibilityTests.swift` |
| visibility helper › unless creates a negated $state condition | Passing | `VisibilityTests.swift` |
| visibility helper › eq creates an equality condition | Passing | `VisibilityTests.swift` |
| visibility helper › neq creates an inequality condition | Passing | `VisibilityTests.swift` |
| visibility helper › gt creates a greater-than condition | Passing | `VisibilityTests.swift` |
| visibility helper › gte creates a gte condition | Passing | `VisibilityTests.swift` |
| visibility helper › lt creates a less-than condition | Passing | `VisibilityTests.swift` |
| visibility helper › lte creates a lte condition | Passing | `VisibilityTests.swift` |
| visibility helper › and returns an $and wrapper | Passing | `VisibilityTests.swift` |
| visibility helper › or returns an $or wrapper | Passing | `VisibilityTests.swift` |
| splitRepeatVisibility › passes through pure container conditions | Passing | `VisibilityTests.swift` |
| splitRepeatVisibility › routes pure item conditions to the item filter | Passing | `VisibilityTests.swift` |
| splitRepeatVisibility › partitions AND-composed mixed conditions | Passing | `VisibilityTests.swift` |
| splitRepeatVisibility › keeps mixed $or entirely as an item filter | Passing | `VisibilityTests.swift` |

### `packages/core/src/experimental-evaluator.test.ts`

5 cases: 0 passing, 5 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| experimental_createEvaluator › uses Gateway with a plain model ID and normalizes native confidence | N/A | Experimental AI evaluator that calls the Vercel AI Gateway. AI generation is excluded. |
| experimental_createEvaluator › allows missing confidence and usage without inventing telemetry | N/A | Experimental AI evaluator that calls the Vercel AI Gateway. AI generation is excluded. |
| experimental_createEvaluator › rejects malformed or unoffered decisions: %j | N/A | Experimental AI evaluator that calls the Vercel AI Gateway. AI generation is excluded. |
| experimental_createEvaluator › reports HTTP status without exposing provider error bodies | N/A | Experimental AI evaluator that calls the Vercel AI Gateway. AI generation is excluded. |
| experimental_createEvaluator › propagates cancellation and enforces its per-call timeout | N/A | Experimental AI evaluator that calls the Vercel AI Gateway. AI generation is excluded. |

### `packages/core/src/experimental-compose.test.ts`

27 cases: 0 passing, 27 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| experimental_composeSpec › edits a selected spec without mutating it, preserving IDs, state, bindings and named slots | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › moves subtrees between named slots and reorders without dropping descendants | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › does not offer cyclic, over-depth, no-op moves or replacements that lose children | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › counts existing recipes against usage/resource limits and releases removed subtrees | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › removes entire subtrees and restores their candidate availability | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › uses explicit descriptions without sharing seed props or state, and keeps no-op/limited edits intact | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › rejects an invalid seed before evaluation: %s | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › rejects invalid selected edit destinations without mutating the seed | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › supports object-valued built-in actions and catalog action callbacks | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › builds a custom catalog's named slots, bindings and actions | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › enforces root eligibility, usage counts, resource exclusions and depth | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › rejects arbitrary decisions, nonexistent parents and missing answers | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › rejects invalid recipes before calling the evaluator: %j | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › preserves unavailable and budget stops without inventing a complete UI | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › does not share state values, and isolates evaluator and consumer mutations | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › preserves unknown usage and confidence, and rejects invalid telemetry | N/A | Experimental AI composition. AI generation is excluded. |
| experimental_composeSpec › honors abort before and during evaluation, including uncooperative adapters | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › renders content in the first of two evaluations and arranges named slots atomically | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › keeps resource variants mutually exclusive and caps repeated root instances | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › uses the evaluator's sibling order independently of candidate order | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › preserves the first valid preview when independently chosen parents form a cycle | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › rejects a combined layout that exceeds the depth budget | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › reports element, depth and evaluation limits as partial output | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › finishes single-element results in one call and keeps unavailable results empty | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › does not share state or allow evaluator/consumer mutations to alter future output | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › rejects missing, arbitrary and invalid batched answers before rendering | N/A | Experimental AI composition. AI generation is excluded. |
| batched composition › stops at consumer return or abort without making a layout call | N/A | Experimental AI composition. AI generation is excluded. |

### `packages/react/src/renderer.test.tsx`

7 cases: 7 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| Renderer › renders null for null spec | Passing | `RendererTests.swift` |
| Renderer › renders null for spec without root | Passing | `RendererTests.swift` |
| Renderer › accepts loading prop | Passing | `RendererTests.swift` |
| Renderer › accepts fallback prop | Passing | `RendererTests.swift` |
| Renderer › renders named slots through defineRegistry | Passing | `RendererTests.swift` |
| Renderer › resolves nested repeat statePath %s from parent $item scope | Passing | `RendererTests.swift` |
| Renderer › does not fall back to root state for $item outside repeat scope | Passing | `RendererTests.swift` |

### `packages/react/src/streaming-render.test.tsx`

17 cases: 13 passing, 4 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| streaming render stability › does not execute untouched catalog components for each patch | N/A | Counts React component renders. SwiftUI decides when views re-evaluate. |
| streaming render stability › does not execute untouched element renderers for each patch | Passing | `StreamingRenderTests.swift` |
| streaming render stability › keeps binding identity stable across state writes | N/A | Guards against a React effect loop on unstable binding objects. Swift bindings are values. |
| streaming render stability › preserves state context updates for catalog components | N/A | Counts React component renders after a state write. |
| streaming render stability › renders a child that becomes available in a later complete spec | Passing | `StreamingRenderTests.swift` |
| streaming render stability › updates direct renderer consumers with fresh complete specs | Passing | `StreamingRenderTests.swift` |
| streaming render stability › does not preserve stale prop keys with undefined values | Passing | `StreamingRenderTests.swift` |
| streaming render stability › recovers when props arrive after the element type | Passing | `StreamingRenderTests.swift` |
| streaming render stability › keeps repeated event callbacks bound to the current item | Passing | `StreamingRenderTests.swift` |
| streaming render stability › refreshes resolved props when functions and directives change | Passing | `StreamingRenderTests.swift` |
| streaming render stability › keeps event callbacks fresh when functions and directives change | Passing | `StreamingRenderTests.swift` |
| streaming render stability › supports non-serializable resolved state and repeat items | N/A | JSON values cannot be cyclic or hold a BigInt. |
| streaming render stability › propagates shared-child updates through a DAG | Passing | `StreamingRenderTests.swift` |
| streaming render stability › terminates signature computation for cyclic element graphs | Passing | `StreamingRenderTests.swift` |
| streaming render stability › stops a watch action chain when its element unmounts | Passing | `StreamingRenderTests.swift` |
| streaming render stability › recovers a catalog component after a corrective patch | Passing | `StreamingRenderTests.swift` |
| streaming render stability › computes signatures for deep element graphs without recursion | Passing | `StreamingRenderTests.swift` |

### `packages/react/src/chained-actions.test.tsx`

4 cases: 4 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| chained actions: live $state resolution (#141) › setState after pushState sees the post-push value via $state | Passing | `RendererTests.swift` |
| chained actions: live $state resolution (#141) › multiple pushState + setState chain resolves correctly | Passing | `RendererTests.swift` |
| chained actions: live $state resolution (#141) › setState reading a path mutated by an earlier setState sees fresh value | Passing | `RendererTests.swift` |
| chained actions: live $state resolution (#141) › forwards params to a named onSuccess action (#301) | Passing | `RendererTests.swift` |

### `packages/react/src/dynamic-forms.test.tsx`

11 cases: 11 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| $computed expressions in rendering › resolves a $computed prop using provided functions | Passing | `DynamicFormsTests.swift` |
| $computed expressions in rendering › renders gracefully when functions prop is omitted | Passing | `DynamicFormsTests.swift` |
| $template expressions in rendering › interpolates state values into a template string | Passing | `DynamicFormsTests.swift` |
| $template expressions in rendering › resolves missing paths to empty string | Passing | `DynamicFormsTests.swift` |
| watchers (watch field) › does not fire on initial render, fires when watched state changes | Passing | `DynamicFormsTests.swift` |
| watchers (watch field) › fires multiple action bindings on the same watch path | Passing | `DynamicFormsTests.swift` |
| validateForm action › writes { valid: false } when a required field is empty | Passing | `DynamicFormsTests.swift` |
| validateForm action › writes { valid: true } when all fields pass validation | Passing | `DynamicFormsTests.swift` |
| validateForm action › defaults to /formValidation when no statePath is provided | Passing | `DynamicFormsTests.swift` |
| Select validate-on-change sees the new value, not the stale value › does not show 'required' error when selecting the first value | Passing | `DynamicFormsTests.swift` |
| Select validate-on-change sees the new value, not the stale value › does not show 'required' error when selecting the first city after country change resets it | Passing | `DynamicFormsTests.swift` |

### `packages/react/src/repeat-filter.test.tsx`

6 cases: 6 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| repeat with $item visible on the container (filtered list) › renders only the items matching the filter | Passing | `RendererTests.swift` |
| repeat with $item visible on the container (filtered list) › renders every item without a filter | Passing | `RendererTests.swift` |
| repeat with $item visible on the container (filtered list) › still hides the whole list for a container-level $state condition | Passing | `RendererTests.swift` |
| repeat with $item visible on the container (filtered list) › keeps per-child $item visible working inside the repeat scope | Passing | `RendererTests.swift` |
| mixed container/item visibility on repeat containers › hides the container shell when the $state gate is false | Passing | `RendererTests.swift` |
| mixed container/item visibility on repeat containers › filters items when the $state gate is true | Passing | `RendererTests.swift` |

### `packages/react/src/directives.test.tsx`

3 cases: 3 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| directives in React renderer › resolves a custom directive in rendered props | Passing | `RendererTests.swift` |
| directives in React renderer › resolves a directive that reads from state | Passing | `RendererTests.swift` |
| directives in React renderer › renders without directives (backward compat) | Passing | `RendererTests.swift` |

### `packages/react/src/contexts/state.test.tsx`

3 cases: 3 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| state re-exports (smoke test) › StateProvider + useStateStore round-trip | Passing | `DynamicFormsTests.swift` |
| state re-exports (smoke test) › useStateValue reads from state | Passing | `DynamicFormsTests.swift` |
| state re-exports (smoke test) › useStateBinding returns value and setter | Passing | `DynamicFormsTests.swift` |

### `packages/react/src/contexts/visibility.test.tsx`

8 cases: 7 passing, 1 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| useVisibility › provides isVisible function | N/A | A TypeScript `typeof` check. The Swift method always exists. |
| useVisibility › provides visibility context | Passing | `DynamicFormsTests.swift` |
| useIsVisible › returns true for undefined condition | Passing | `DynamicFormsTests.swift` |
| useIsVisible › returns true for true condition | Passing | `DynamicFormsTests.swift` |
| useIsVisible › returns false for false condition | Passing | `DynamicFormsTests.swift` |
| useIsVisible › evaluates $state conditions against data | Passing | `DynamicFormsTests.swift` |
| useIsVisible › evaluates equality conditions | Passing | `DynamicFormsTests.swift` |
| useIsVisible › evaluates array conditions (implicit AND) | Passing | `DynamicFormsTests.swift` |

### `packages/react/src/hooks.test.ts`

24 cases: 24 passing, 0 N/A.

| Upstream case | Status | Swift test or reason |
|---|---|---|
| flatToTree › converts array of elements to tree structure | Passing | `HooksTests.swift` |
| flatToTree › builds parent-child relationships | Passing | `HooksTests.swift` |
| flatToTree › handles single root element | Passing | `HooksTests.swift` |
| flatToTree › handles deeply nested elements | Passing | `HooksTests.swift` |
| flatToTree › preserves element props | Passing | `HooksTests.swift` |
| flatToTree › preserves visibility conditions | Passing | `HooksTests.swift` |
| flatToTree › handles elements with undefined parentKey as root | Passing | `HooksTests.swift` |
| flatToTree › handles empty elements array | Passing | `HooksTests.swift` |
| flatToTree › handles multiple children correctly | Passing | `HooksTests.swift` |
| buildSpecFromParts › returns null when no data-spec parts are present | Passing | `HooksTests.swift` |
| buildSpecFromParts › builds a spec from patch parts | Passing | `HooksTests.swift` |
| buildSpecFromParts › handles flat spec parts | Passing | `HooksTests.swift` |
| buildSpecFromParts › ignores non-spec parts | Passing | `HooksTests.swift` |
| buildSpecFromParts › applies patches incrementally | Passing | `HooksTests.swift` |
| buildSpecFromParts › handles nested spec parts via nestedToFlat | Passing | `HooksTests.swift` |
| buildSpecFromParts › preserves named slots in nested spec parts | Passing | `HooksTests.swift` |
| buildSpecFromParts › handles mixed patch + flat + nested parts in sequence | Passing | `HooksTests.swift` |
| buildSpecFromParts › returns empty elements map from empty parts list | Passing | `HooksTests.swift` |
| getTextFromParts › extracts text from text parts | Passing | `HooksTests.swift` |
| getTextFromParts › returns empty string when no text parts | Passing | `HooksTests.swift` |
| getTextFromParts › ignores non-text parts | Passing | `HooksTests.swift` |
| getTextFromParts › trims whitespace from text parts | Passing | `HooksTests.swift` |
| getTextFromParts › skips empty text parts | Passing | `HooksTests.swift` |
| getTextFromParts › ignores text parts with non-string text field | Passing | `HooksTests.swift` |

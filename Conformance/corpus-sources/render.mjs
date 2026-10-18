// Writes corpus/render.json: render scenarios for the upstream React renderer.
// Run with: node corpus-sources/render.mjs
//
// A scenario has a spec, the component types the registry provides, and steps.
// Steps: emit, write (a bound prop), validate, touch, setState, update, spec,
// patches, loading, confirm, cancel, release (a pending handler), execute.

import { writeFileSync } from "node:fs";

const U = { $js: "undefined" };
const cases = [];
const add = (scenario) => cases.push(scenario);
const el = (type, props = {}, extra = {}) => ({ type, props, children: [], ...extra });
const common = ["Stack", "Text", "Button", "Input", "List", "Item"];

// --- Structure -------------------------------------------------------------

add({
  name: "visibility toggles with state",
  components: common,
  spec: {
    root: "a",
    state: { show: false, tab: "home" },
    elements: {
      a: el("Stack", {}, { children: ["b", "c", "d"] }),
      b: el("Text", { text: "shown when show" }, { visible: { $state: "/show" } }),
      c: el("Text", { text: "home tab" }, { visible: { $or: [{ $state: "/tab", eq: "home" }, { $state: "/tab", not: true }] } }),
      d: el("Text", { text: "not home" }, { visible: { $state: "/tab", neq: "home" } }),
    },
  },
  steps: [{ setState: { path: "/show", value: true } }, { setState: { path: "/tab", value: "other" } }, { update: { "/show": false, "/tab": "home" } }],
});

add({
  name: "missing children, unknown types and nested containers",
  components: common,
  spec: {
    root: "a",
    elements: {
      a: el("Stack", {}, { children: ["b", "gone", "c"] }),
      b: el("Mystery", { x: 1 }),
      c: el("Stack", {}, { children: ["d"] }),
      d: el("Text", { text: "deep" }),
    },
  },
});

add({
  name: "fallback renders unknown types",
  components: ["Stack"],
  fallback: true,
  spec: { root: "a", elements: { a: el("Stack", {}, { children: ["b"] }), b: el("Mystery", { label: "fallback" }) } },
});

add({
  name: "loading suppresses missing element warnings",
  components: common,
  loading: true,
  spec: { root: "a", elements: { a: el("Stack", {}, { children: ["later"] }) } },
  steps: [
    { patches: [{ op: "add", path: "/elements/later", value: el("Text", { text: "arrived" }) }] },
    { loading: false },
    { patches: [{ op: "add", path: "/elements/a/children/-", value: "missing" }] },
  ],
});

add({
  name: "spec without root or root element renders nothing",
  components: common,
  spec: { root: "", elements: { a: el("Text") } },
  steps: [{ spec: { root: "zz", elements: { a: el("Text") } } }, { spec: { root: "a", elements: { a: el("Text", { text: "now" }) } } }],
});

add({
  name: "named slots with catalog metadata",
  components: ["Layout", "Text"],
  catalog: { components: { Layout: { slots: ["default", "header"] }, Text: { slots: [] } } },
  spec: {
    root: "layout",
    elements: {
      layout: el("Layout", {}, { children: ["main"], slots: { header: ["h"], footer: ["f", "nope"], default: ["main"] } }),
      h: el("Text", { text: "Header" }),
      main: el("Text", { text: "Main" }),
      f: el("Text", { text: "Footer" }),
    },
  },
});

add({
  name: "slots without catalog metadata",
  components: ["Layout", "Text"],
  spec: { root: "layout", elements: { layout: el("Layout", {}, { slots: { header: ["h"] } }), h: el("Text", { text: "Header" }) } },
});

add({
  name: "shared child rendered twice",
  components: common,
  spec: { root: "a", elements: { a: el("Stack", {}, { children: ["s", "s"] }), s: el("Text", { text: { $state: "/t" } }) }, state: { t: "x" } },
});

// --- Repeat ----------------------------------------------------------------

add({
  name: "repeat with keys, index and item bindings",
  components: common,
  spec: {
    root: "list",
    state: { items: [{ id: "a", done: false }, { id: "b", done: true }, { other: 1 }] },
    elements: {
      list: el("List", {}, { repeat: { statePath: "/items", key: "id" }, children: ["item", "missing"] }),
      item: el("Item", { done: { $bindItem: "done" }, index: { $index: true }, whole: { $item: "" }, label: { $template: "${id}" } }),
    },
  },
  steps: [
    { write: { node: "list/[a]/item", prop: "done", value: true } },
    { setState: { path: "/items/-", value: { id: "c", done: false } } },
    { setState: { path: "/items", value: [{ id: "b", done: true }] } },
  ],
});

add({
  name: "repeat filter splits container and item conditions",
  components: common,
  spec: {
    root: "col",
    state: { show: true, tasks: [{ id: "1", s: "todo" }, { id: "2", s: "done" }, { id: "3", s: "todo" }] },
    elements: {
      col: el("List", { count: { $index: true } }, {
        repeat: { statePath: "/tasks", key: "id" },
        visible: [{ $state: "/show" }, { $item: "s", eq: "todo" }],
        children: ["card"],
      }),
      card: el("Item", { id: { $item: "id" } }),
    },
  },
  steps: [{ setState: { path: "/show", value: false } }, { setState: { path: "/show", value: true } }, { setState: { path: "/tasks/1/s", value: "todo" } }],
});

add({
  name: "repeat or-filter mixing scopes applies per item",
  components: common,
  spec: {
    root: "col",
    state: { all: false, items: [{ id: 1, on: true }, { id: 2, on: false }] },
    elements: {
      col: el("List", {}, { repeat: { statePath: "/items", key: "id" }, visible: { $or: [{ $state: "/all" }, { $item: "on" }] }, children: ["i"] }),
      i: el("Item", { id: { $item: "id" } }),
    },
  },
  steps: [{ setState: { path: "/all", value: true } }],
});

add({
  name: "nested repeats with relative statePath",
  components: common,
  spec: {
    root: "groups",
    state: { groups: [{ name: "g1", items: ["a", "b"] }, { name: "g2", items: [] }, { name: "g3" }] },
    elements: {
      groups: el("List", {}, { repeat: { statePath: "/groups" }, children: ["title", "items"] }),
      title: el("Text", { text: { $item: "name" } }),
      items: el("List", {}, { repeat: { statePath: { $item: "items" } }, children: ["leaf"] }),
      leaf: el("Item", { value: { $item: "" }, path: { $bindItem: "" } }),
    },
  },
  steps: [{ write: { node: "groups/[0]/items/[1]/leaf", prop: "path", value: "B" } }],
});

add({
  name: "repeat edge cases",
  components: common,
  spec: {
    root: "a",
    state: { obj: { x: 1 }, str: "abc", nil: null, nums: [1, 2] },
    elements: {
      a: el("Stack", {}, { children: ["nil", "missing", "relative", "noChildren", "numbers"] }),
      nil: el("List", {}, { repeat: { statePath: "/nil" }, children: ["i"] }),
      missing: el("List", {}, { repeat: { statePath: "/nope" }, children: ["i"] }),
      relative: el("List", {}, { repeat: { statePath: { $item: "x" } }, children: ["i"] }),
      noChildren: el("List", {}, { repeat: { statePath: "/nums" }, children: [] }),
      numbers: el("List", {}, { repeat: { statePath: "/nums", key: "id" }, children: ["i"] }),
      i: el("Item", { v: { $item: "" } }),
    },
  },
});

add({
  name: "repeat over a non-array is caught by the container boundary",
  components: common,
  spec: {
    root: "a",
    state: { obj: { x: 1 } },
    elements: { a: el("Stack", {}, { children: ["bad", "ok"] }), bad: el("List", {}, { repeat: { statePath: "/obj" }, children: ["i"] }), i: el("Item"), ok: el("Text", { text: "fine" }) },
  },
});

// --- Expressions -----------------------------------------------------------

add({
  name: "prop expressions resolve against state",
  components: common,
  spec: {
    root: "t",
    state: { user: { first: "Ada", last: "Lovelace" }, n: 4, flag: true },
    elements: {
      t: el("Text", {
        cond: { $cond: { $state: "/flag" }, $then: { $state: "/user/first" }, $else: "no" },
        computed: { $computed: "fullName", args: { first: { $state: "/user/first" }, last: { $state: "/user/last" } } },
        directive: { $double: { $state: "/n" } },
        template: { $template: "${/user/first} has ${/n} (${/missing})" },
        nested: { list: [{ $state: "/n" }, { $bindState: "/n" }], deep: { $upper: "x" } },
        unknown: { $computed: "renderUnknownFunction" },
      }),
    },
  },
  steps: [{ setState: { path: "/flag", value: false } }, { setState: { path: "/n", value: 5 } }],
});

add({
  name: "functions and directives absent",
  components: common,
  functions: false,
  directives: false,
  spec: { root: "t", elements: { t: el("Text", { c: { $computed: "fullName" }, d: { $double: 2 } }) } },
});

// --- Error boundaries ------------------------------------------------------

add({
  name: "throwing child hides its parent subtree",
  components: [...common, "Thrower"],
  throwingTypes: ["Thrower"],
  spec: {
    root: "a",
    state: { fail: true },
    elements: { a: el("Stack", {}, { children: ["p", "sibling"] }), p: el("Stack", {}, { children: ["t"] }), t: el("Thrower", { fail: { $state: "/fail" } }), sibling: el("Text", { text: "still here" }) },
  },
  steps: [
    { setState: { path: "/fail", value: false } },
    { patches: [{ op: "replace", path: "/elements/t/props/extra", value: 1 }] },
    { setState: { path: "/fail", value: true } },
  ],
});

add({
  name: "malformed visible in a child fails the parent",
  components: common,
  spec: { root: "a", elements: { a: el("Stack", {}, { children: ["p", "ok"] }), p: el("Stack", {}, { children: ["bad"] }), bad: el("Text", {}, { visible: null }), ok: el("Text", { text: "ok" }) } },
  steps: [{ patches: [{ op: "replace", path: "/elements/bad/visible", value: true }] }],
});

add({
  name: "directive error in a child fails the parent",
  components: common,
  spec: { root: "a", elements: { a: el("Stack", {}, { children: ["p"] }), p: el("Stack", {}, { children: ["bad"] }), bad: el("Text", { v: { $fails: 1 } }) } },
});

add({
  name: "error in the root element escapes every boundary",
  components: common,
  spec: { root: "a", elements: { a: el("Text", { v: { $double: 1, $upper: "x" } }) } },
});

// --- Actions ---------------------------------------------------------------

add({
  name: "built-in state actions",
  components: common,
  spec: {
    root: "a",
    state: { items: ["x"], text: "draft", count: 1 },
    elements: {
      a: el("Stack", {}, { children: ["set", "push", "remove", "chain"] }),
      set: el("Button", {}, { on: { press: { action: "setState", params: { statePath: "/count", value: 2 } } } }),
      push: el("Button", {}, { on: { press: { action: "pushState", params: { statePath: "/items", value: { id: "$id", text: { $state: "/text" }, nested: { $id: true } }, clearStatePath: "/text" } } } }),
      remove: el("Button", {}, { on: { press: { action: "removeState", params: { statePath: "/items", index: 0 } } } }),
      chain: el("Button", {}, { on: { press: [
        { action: "setState", params: { statePath: "/copy", value: { $state: "/items" } } },
        { action: "pushState", params: { statePath: "/newList", value: 1 } },
        { action: "setState", params: { statePath: "/same", value: { $state: "/count" } } },
      ] } }),
    },
  },
  steps: [
    { emit: { node: "a/set", event: "press" } },
    { emit: { node: "a/push", event: "press" } },
    { emit: { node: "a/remove", event: "press" } },
    { emit: { node: "a/chain", event: "press" } },
    { emit: { node: "a/set", event: "unbound" } },
  ],
});

add({
  name: "navigation built-ins",
  components: common,
  spec: {
    root: "a",
    elements: {
      a: el("Stack", {}, { children: ["go", "go2", "back", "home"] }),
      go: el("Button", {}, { on: { press: { action: "push", params: { screen: "detail" } } } }),
      go2: el("Button", {}, { on: { press: { action: "push", params: { screen: "more" } } } }),
      back: el("Button", {}, { on: { press: { action: "pop" } } }),
      home: el("Text", { screen: { $state: "/currentScreen" } }, { visible: { $state: "/currentScreen", not: true } }),
    },
  },
  steps: [
    { emit: { node: "a/go", event: "press" } },
    { emit: { node: "a/go2", event: "press" } },
    { emit: { node: "a/back", event: "press" } },
    { emit: { node: "a/back", event: "press" } },
    { emit: { node: "a/back", event: "press" } },
  ],
});

add({
  name: "handlers with onSuccess and onError",
  components: common,
  handlers: { save: { result: "saved" }, fail: { throw: "Network down" }, toast: {} },
  spec: {
    root: "a",
    elements: {
      a: el("Stack", {}, { children: ["ok", "nav", "err", "rethrow", "follow", "missing"] }),
      ok: el("Button", {}, { on: { press: { action: "save", params: { id: { $state: "/id" }, literal: 1 }, onSuccess: { set: { "/status": "done", "/when": "now" } } } } }),
      nav: el("Button", {}, { on: { press: { action: "save", onSuccess: { navigate: "/home" } } } }),
      err: el("Button", {}, { on: { press: { action: "fail", onError: { set: { "/error": "$error.message", "/other": "x" } } } } }),
      rethrow: el("Button", {}, { on: { press: [{ action: "fail" }, { action: "save" }] } }),
      follow: el("Button", {}, { on: { press: { action: "fail", onError: { action: "toast", params: { message: "Failed" } } } } }),
      missing: el("Button", {}, { on: { press: { action: "nobody" } } }),
    },
    state: { id: 7 },
  },
  steps: [
    { emit: { node: "a/ok", event: "press" } },
    { emit: { node: "a/nav", event: "press" } },
    { emit: { node: "a/err", event: "press" } },
    { emit: { node: "a/rethrow", event: "press" } },
    { emit: { node: "a/follow", event: "press" } },
    { emit: { node: "a/missing", event: "press" } },
  ],
});

add({
  name: "confirmation dialog confirm and cancel",
  components: common,
  handlers: { remove: {} },
  spec: {
    root: "a",
    state: { name: "Report" },
    elements: {
      a: el("Stack", {}, { children: ["del"] }),
      del: el("Button", {}, { on: { press: [
        { action: "remove", params: { what: { $state: "/name" } }, confirm: { title: "Delete ${/name}?", message: "This removes ${/name} for ${/missing}.", variant: "danger", confirmLabel: "Delete" } },
        { action: "setState", params: { statePath: "/after", value: true } },
      ] } }),
    },
  },
  steps: [{ emit: { node: "a/del", event: "press" } }, { confirm: true }, { emit: { node: "a/del", event: "press" } }, { cancel: true }],
});

add({
  name: "action params resolve with repeat scope and live state",
  components: common,
  handlers: { pick: {} },
  spec: {
    root: "list",
    state: { items: [{ id: "x", title: "First" }, { id: "y", title: "Second" }], picked: [] },
    elements: {
      list: el("List", {}, { repeat: { statePath: "/items", key: "id" }, children: ["btn"] }),
      btn: el("Button", {}, { on: { press: [
        { action: "pick", params: { path: { $item: "title" }, index: { $index: true }, title: { $computed: "echo", args: { t: { $state: "/items/0/title" } } } } },
        { action: "setState", params: { statePath: { $item: "title" }, value: "Picked" } },
        { action: "removeState", params: { statePath: "/items", index: { $index: true } } },
      ] } }),
    },
  },
  steps: [{ emit: { node: "list/[y]/btn", event: "press" } }],
});

add({
  name: "execute from the host",
  components: common,
  handlers: { track: {} },
  spec: { root: "a", elements: { a: el("Text") } },
  steps: [
    { execute: { action: "track", params: { a: { $state: "/a" }, b: [1, { $state: "/a" }] } } },
    { execute: { action: "setState", params: { statePath: "/a", value: "set" } } },
    { execute: { action: 5 } },
  ],
});

// --- Forms -----------------------------------------------------------------

add({
  name: "validateForm with registered fields",
  components: common,
  fieldTypes: ["Input"],
  spec: {
    root: "a",
    state: { form: { email: "", age: 3 } },
    elements: {
      a: el("Stack", {}, { children: ["email", "age", "plain", "submit"] }),
      email: el("Input", { value: { $bindState: "/form/email" }, checks: [{ type: "required", message: "Email is required" }, { type: "email", message: "Invalid email" }] }),
      age: el("Input", { value: { $bindState: "/form/age" }, checks: [{ type: "min", args: { min: { $state: "/limits/min" } }, message: "Too young" }] }),
      plain: el("Input", { value: { $bindState: "/form/plain" } }),
      submit: el("Button", {}, { on: { press: [{ action: "validateForm", params: { statePath: "/result" } }, { action: "setState", params: { statePath: "/copy", value: { $state: "/result/valid" } } }] } }),
    },
  },
  steps: [
    { emit: { node: "a/submit", event: "press" } },
    { write: { node: "a/email", prop: "value", value: "a@b.co" } },
    { validate: { node: "a/email" } },
    { touch: { node: "a/age" } },
    { setState: { path: "/limits", value: { min: 1 } } },
    { emit: { node: "a/submit", event: "press" } },
  ],
});

// --- Watchers --------------------------------------------------------------

add({
  name: "watchers fire on change only",
  components: common,
  handlers: { load: {} },
  spec: {
    root: "a",
    state: { country: "", city: "x" },
    elements: {
      a: el("Stack", {}, { children: ["w", "hidden"] }),
      w: el("Text", {}, { watch: {
        "/country": [{ action: "load", params: { country: { $state: "/country" } } }, { action: "setState", params: { statePath: "/city", value: "" } }],
        "/city": { action: "setState", params: { statePath: "/cityChanged", value: true } },
      } }),
      hidden: el("Text", {}, { visible: false, watch: { "/country": { action: "setState", params: { statePath: "/hiddenSaw", value: { $state: "/country" } } } } }),
    },
  },
  steps: [
    { setState: { path: "/country", value: "AU" } },
    { setState: { path: "/unrelated", value: 1 } },
    { setState: { path: "/country", value: "NZ" } },
  ],
});

add({
  name: "watchers inside repeat and unmounted watchers",
  components: common,
  handlers: { seen: {} },
  spec: {
    root: "a",
    state: { show: true, items: [{ id: 1 }, { id: 2 }], v: 0 },
    elements: {
      a: el("Stack", {}, { children: ["box"] }),
      box: el("Stack", {}, { visible: { $state: "/show" }, children: ["list"] }),
      list: el("List", {}, { repeat: { statePath: "/items", key: "id" }, children: ["w"] }),
      w: el("Item", {}, { watch: { "/v": { action: "seen", params: { id: { $item: "id" }, v: { $state: "/v" } } } } }),
    },
  },
  steps: [{ setState: { path: "/v", value: 1 } }, { setState: { path: "/show", value: false } }, { setState: { path: "/v", value: 2 } }],
});

add({
  name: "watch chain stops when its element unmounts",
  components: common,
  handlers: { first: { pending: true }, second: {} },
  spec: {
    root: "root",
    state: { value: "initial" },
    elements: { root: el("Stack", {}, { children: ["watcher"] }), watcher: el("Text", {}, { watch: { "/value": [{ action: "first" }, { action: "second" }] } }) },
  },
  steps: [
    { setState: { path: "/value", value: "changed" } },
    { patches: [{ op: "replace", path: "/elements/root/children", value: [] }] },
    { release: "first" },
  ],
});

// --- Streaming -------------------------------------------------------------

add({
  name: "spec patches stream in",
  components: common,
  loading: true,
  spec: { root: "", elements: {} },
  steps: [
    { patches: [{ op: "add", path: "/root", value: "main" }] },
    { patches: [{ op: "add", path: "/elements/main", value: { type: "Stack", props: { gap: 1 }, children: ["t1", "t2"] } }] },
    { patches: [{ op: "add", path: "/elements/t1", value: { type: "Text", props: { text: { $state: "/greeting" } } } }] },
    { patches: [{ op: "add", path: "/state", value: { greeting: "hello" } }] },
    { patches: [{ op: "add", path: "/elements/t2", value: { type: "Text" } }, { op: "add", path: "/elements/t2/props", value: { text: "later" } }] },
    { patches: [{ op: "replace", path: "/elements/main/props/gap", value: 2 }, { op: "remove", path: "/elements/t1" }] },
    { loading: false },
  ],
});

add({
  name: "spec state sync overwrites and clears store keys",
  components: common,
  spec: { root: "t", state: { a: 1, b: { c: 2 } }, elements: { t: el("Text", { a: { $state: "/a" }, c: { $state: "/b/c" }, d: { $state: "/d" } }) } },
  steps: [
    { setState: { path: "/d", value: "mine" } },
    { spec: { root: "t", state: { a: 10, b: { c: 2 } }, elements: { t: el("Text", { a: { $state: "/a" }, c: { $state: "/b/c" }, d: { $state: "/d" } }) } } },
    { spec: { root: "t", elements: { t: el("Text", { a: { $state: "/a" }, c: { $state: "/b/c" }, d: { $state: "/d" } }) } } },
  ],
});

add({
  name: "fixed initial state is not synced from the spec",
  components: common,
  initialState: { a: "host" },
  spec: { root: "t", state: { a: "spec" }, elements: { t: el("Text", { a: { $state: "/a" } }) } },
  steps: [{ spec: { root: "t", state: { a: "spec2" }, elements: { t: el("Text", { a: { $state: "/a" } }) } } }],
});

writeFileSync(
  new URL("../corpus/render.json", import.meta.url),
  `${JSON.stringify({ description: "Render scenarios through the upstream React renderer. Generated by corpus-sources/render.mjs.", cases }, null, 2)}\n`,
);
console.log(`${cases.length} render scenarios`);
void U;

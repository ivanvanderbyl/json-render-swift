// Renders a scenario with the real @json-render/react JSONUIProvider and
// Renderer in jsdom, drives it step by step, and records after each step the
// normalised render tree, the state and everything observable: handler calls,
// observer events, state change callbacks, navigation, warnings and errors.
//
// The render tree comes from React's committed fiber tree, so it is exactly
// what upstream rendered. Each node is one ElementRenderer instance:
//   { id, key, type, status, props, bindings, repeat, children, slots }
// status is "rendered", "hidden" (visibility false), "noRenderer" (no
// component and no fallback) or "failed" (an error boundary caught an error).

import "./dom.mjs";
import * as core from "@json-render/core";
import {
  JSONUIProvider,
  Renderer,
  defineRegistry,
  useActions,
  useFieldValidation,
  useStateStore,
  useValidation,
} from "@json-render/react";
import React, { act, useMemo } from "react";
import { createRoot } from "react-dom/client";
import { z } from "zod";
import { decode, encode } from "../encoding.mjs";
import { computedFunctions, directives, validationFunctions } from "../fixtures.mjs";

// Generated ids are "<Date.now()>-<counter>". A fixed clock makes them
// recognisable so the goldens can replace them with a placeholder.
export const FIXED_NOW = 1111111111111;
Date.now = () => FIXED_NOW;
const GENERATED_ID = new RegExp(`^${FIXED_NOW}-\\d+$`);

/** Replaces generated ids with "<generated-id>" throughout a value. */
function normaliseIds(value) {
  if (typeof value === "string") return GENERATED_ID.test(value) ? "<generated-id>" : value;
  if (Array.isArray(value)) return value.map(normaliseIds);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, member]) => [key, normaliseIds(member)]));
  }
  return value;
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function format(args) {
  return args
    .map((arg) => (typeof arg === "string" ? arg : arg instanceof Error ? arg.message : (() => {
      try {
        return JSON.stringify(arg);
      } catch {
        return String(arg);
      }
    })()))
    .join(" ");
}

export async function runScenario(entry) {
  const log = [];
  const messages = [];
  const originalWarn = console.warn;
  const originalError = console.error;
  console.warn = (...args) => messages.push({ level: "warning", text: format(args) });
  console.error = (...args) => {
    // Error boundaries also log React's component stack, which is not stable.
    const text = format(typeof args[0] === "string" && args[0].startsWith("[json-render] Rendering error in") ? args.slice(0, 2) : args);
    // React's own development noise is not upstream json-render behaviour.
    if (text.startsWith("Warning:") || text.includes("The above error occurred") || text.startsWith("Encountered two children with the same key")) return;
    messages.push({ level: "error", text });
  };
  const unobserve = core.registerActionObserver({
    onDispatch: (event) => log.push({ event: "dispatch", name: event.name, params: event.params }),
    onSettle: (event) =>
      log.push({ event: "settle", name: event.name, ok: event.ok, ...(event.error ? { error: errorMessage(event.error) } : {}) }),
  });

  const controls = {};
  const pending = {};
  try {
    return await drive(entry, log, messages, controls, pending);
  } finally {
    unobserve();
    console.warn = originalWarn;
    console.error = originalError;
  }
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

async function drive(entry, log, messages, controls, pending) {
  const components = entry.components ?? [];
  const fieldTypes = new Set(entry.fieldTypes ?? []);
  const throwingTypes = new Set(entry.throwingTypes ?? []);

  function Probe({ element, children, slots, bindings }) {
    if (throwingTypes.has(element.type) && element.props?.fail) {
      throw new Error(`${element.type} failed to render`);
    }
    const props = element.props ?? {};
    const isField = fieldTypes.has(element.type);
    const hasValidation = isField && !!(bindings?.value && Array.isArray(props.checks) && props.checks.length);
    const config = useMemo(
      () => (hasValidation ? { checks: props.checks, validateOn: props.validateOn } : undefined),
      [hasValidation, props.checks, props.validateOn],
    );
    useFieldValidation(bindings?.value ?? "", config);
    return React.createElement(
      "jr-component",
      null,
      children,
      slots
        ? Object.entries(slots).map(([name, nodes]) =>
            React.createElement("jr-slot", { key: name, "data-slot": name }, nodes),
          )
        : null,
    );
  }

  let registry = Object.fromEntries(components.map((type) => [type, Probe]));
  if (entry.catalog) {
    // defineRegistry attaches slot metadata, which enables slot warnings.
    const catalog = core.defineCatalog(
      core.defineSchema((s) => ({
        spec: s.object({ root: s.string(), elements: s.record(s.object({ type: s.ref("catalog.components") })) }),
        catalog: s.object({ components: s.map({ props: s.zod(), slots: s.array(s.string()) }) }),
      })),
      {
        components: Object.fromEntries(
          Object.entries(entry.catalog.components).map(([name, definition]) => [
            name,
            { props: z.object({}), slots: definition.slots ?? [] },
          ]),
        ),
      },
    );
    registry = defineRegistry(catalog, {
      components: Object.fromEntries(
        components.map((type) => [type, (ctx) => React.createElement(ProbeFromRegistry, { ...ctx, type })]),
      ),
    }).registry;
  }
  function ProbeFromRegistry({ type, props, children, slots, bindings }) {
    return React.createElement(Probe, { element: { type, props }, children, slots, bindings });
  }
  const fallback = entry.fallback ? Probe : undefined;

  const handlers = {};
  for (const [name, behaviour] of Object.entries(entry.handlers ?? {})) {
    handlers[name] = (params) => {
      log.push({ event: "handler", name, params });
      if (behaviour.throw) throw new Error(behaviour.throw);
      if (behaviour.pending) {
        return new Promise((resolve) => {
          pending[name] = () => resolve(behaviour.result);
        });
      }
      return behaviour.result;
    };
  }

  function Controls() {
    controls.state = useStateStore();
    controls.actions = useActions();
    controls.validation = useValidation();
    return null;
  }

  let spec = decode(entry.spec);
  let loading = entry.loading ?? false;
  const fixedInitialState = entry.initialState ? decode(entry.initialState) : undefined;
  const providerProps = {
    registry,
    handlers,
    navigate: (path) => log.push({ event: "navigate", path }),
    validationFunctions,
    functions: entry.functions === false ? undefined : computedFunctions,
    directives: entry.directives === false ? undefined : directives,
    onStateChange: (changes) => log.push({ event: "stateChange", changes }),
  };
  let uncaught;
  const container = document.createElement("div");
  const root = createRoot(container, {
    onUncaughtError: (error) => {
      uncaught = errorMessage(error);
    },
    onCaughtError: () => {},
  });

  const view = () =>
    React.createElement(
      JSONUIProvider,
      { ...providerProps, initialState: fixedInitialState ?? spec?.state },
      React.createElement(Controls),
      React.createElement(Renderer, { spec, registry, loading, fallback }),
    );

  const steps = [];
  const record = (step) => {
    const output = {
      step,
      tree: uncaught !== undefined ? { uncaughtError: uncaught } : snapshotTree(container, registry, fallback, controls),
      state: encode(normaliseIds(controls.state?.getSnapshot())),
      log: encode(normaliseIds(log.splice(0))),
      messages: dedupe(messages.splice(0)),
      pendingConfirmation: controls.actions?.pendingConfirmation
        ? encode(normaliseIds(controls.actions.pendingConfirmation.action.confirm))
        : null,
      fieldStates: encode(normaliseIds(controls.validation?.fieldStates ?? {})),
    };
    steps.push(output);
  };

  // act() rethrows render errors that escaped every boundary.
  const settle = async (work) => {
    try {
      await act(work);
      await act(flush);
    } catch (error) {
      uncaught = errorMessage(error);
    }
  };

  await settle(async () => {
    root.render(view());
    await flush();
  });
  record("mount");

  for (const step of entry.steps ?? []) {
    await settle(async () => {
      await perform(step);
      await flush();
      await flush();
    });
    record(step);
  }

  await settle(async () => root.unmount());
  return { steps };

  async function perform(step) {
    if (step.emit) {
      const node = findNode(step.emit.node);
      if (!node?.emit) {
        log.push({ event: "harness", message: `no emit for ${step.emit.node}` });
        return;
      }
      // Components call emit without awaiting; failures surface as rejections.
      node.emit(step.emit.event)?.catch?.((error) => log.push({ event: "rejected", error: errorMessage(error) }));
      return;
    }
    if (step.write) {
      const node = findNode(step.write.node);
      const path = node?.bindings?.[step.write.prop];
      if (path) controls.state.set(path, decode(step.write.value));
      else log.push({ event: "harness", message: `no binding ${step.write.prop} on ${step.write.node}` });
      return;
    }
    if (step.validate) {
      const node = findNode(step.validate.node);
      const props = node?.element?.props ?? {};
      controls.validation.validate(node?.bindings?.value ?? "", { checks: props.checks ?? [], validateOn: props.validateOn });
      return;
    }
    if (step.touch) {
      const node = findNode(step.touch.node);
      controls.validation.touch(node?.bindings?.value ?? "");
      return;
    }
    if (step.setState) {
      controls.state.set(step.setState.path, decode(step.setState.value));
      return;
    }
    if (step.update) {
      controls.state.update(decode(step.update));
      return;
    }
    if (step.spec !== undefined) {
      spec = decode(step.spec);
      root.render(view());
      return;
    }
    if (step.patches) {
      const next = structuredClone(spec);
      for (const patch of step.patches) core.applySpecPatch(next, decode(patch));
      spec = next;
      root.render(view());
      return;
    }
    if (step.loading !== undefined) {
      loading = step.loading;
      root.render(view());
      return;
    }
    if (step.confirm) {
      controls.actions.confirm();
      return;
    }
    if (step.cancel) {
      controls.actions.cancel();
      return;
    }
    if (step.release) {
      pending[step.release]?.();
      return;
    }
    if (step.execute) {
      controls.actions.execute(decode(step.execute))?.catch?.((error) => log.push({ event: "rejected", error: errorMessage(error) }));
      return;
    }
    throw new Error(`unknown step ${JSON.stringify(step)}`);
  }

  function findNode(id) {
    return collectNodes(container, registry, fallback, controls).get(id);
  }
}

function dedupe(messages) {
  const seen = new Set();
  return messages.filter((message) => {
    const key = `${message.level}:${message.text}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// ---------------------------------------------------------------------------
// Fiber tree inspection
// ---------------------------------------------------------------------------

function fiberName(fiber) {
  const type = fiber.type;
  if (typeof type === "function") return type.name;
  if (type && typeof type === "object") return type.type?.name ?? type.render?.name ?? "";
  return typeof type === "string" ? type : "";
}

function rootFiber(container) {
  const key = Object.keys(container).find((name) => name.startsWith("__reactContainer"));
  return key ? container[key].stateNode.current : null;
}

function findFirst(fiber, predicate) {
  const stack = fiber ? [fiber] : [];
  while (stack.length > 0) {
    const current = stack.pop();
    if (predicate(current)) return current;
    if (current.sibling) stack.push(current.sibling);
    if (current.child) stack.push(current.child);
  }
  return null;
}

/** Calls visit for the nearest ReactiveElementRenderer fibers below fiber. */
function descendants(fiber, scope, visit) {
  for (let child = fiber?.child; child; child = child.sibling) {
    const name = fiberName(child);
    if (name === "ReactiveElementRenderer") {
      visit(child, scope);
      continue;
    }
    let next = scope;
    if (name === "RepeatScopeProvider") {
      const { item, index, basePath } = child.memoizedProps;
      next = { ...scope, repeat: { item, index, basePath, key: child.key } };
    } else if (name === "jr-slot") {
      next = { ...scope, slot: child.memoizedProps["data-slot"] };
    }
    descendants(child, next, visit);
  }
}

function snapshotTree(container, registry, fallback, controls) {
  const nodes = new Map();
  const renderer = findFirst(rootFiber(container), (fiber) => fiberName(fiber) === "Renderer");
  let tree = null;
  descendants(renderer, {}, (fiber, scope) => {
    tree = describe(fiber, scope, "", registry, fallback, controls, nodes);
  });
  return tree;
}

function collectNodes(container, registry, fallback, controls) {
  const nodes = new Map();
  const renderer = findFirst(rootFiber(container), (fiber) => fiberName(fiber) === "Renderer");
  descendants(renderer, {}, (fiber, scope) => describe(fiber, scope, "", registry, fallback, controls, nodes));
  return nodes;
}

function describe(fiber, scope, parentId, registry, fallback, controls, nodes) {
  const { element, elementKey } = fiber.memoizedProps;
  const repeatSegment = scope.repeat && scope.repeat.owner === parentId ? `[${scope.repeat.key}]/` : "";
  const slotSegment = scope.slot !== undefined && scope.slotOwner === parentId ? `@${scope.slot}/` : "";
  const id = parentId === "" ? elementKey : `${parentId}/${slotSegment}${repeatSegment}${elementKey}`;
  const node = { id, key: elementKey, type: encode(element?.type) };
  if (scope.repeat) node.repeat = { index: scope.repeat.index, basePath: scope.repeat.basePath };

  const boundary = fiber.child;
  if (!boundary) {
    node.status = isVisible(element, scope, controls) ? (registry[element?.type] || fallback ? "hidden" : "noRenderer") : "hidden";
    nodes.set(id, node);
    return node;
  }
  if (fiberName(boundary) === "ElementErrorBoundary" && boundary.memoizedState?.hasError) {
    node.status = "failed";
    nodes.set(id, node);
    return node;
  }
  const catalogBoundary = findFirst(boundary.child, (candidate) => fiberName(candidate).startsWith("CatalogComponentBoundary"));
  const props = catalogBoundary?.memoizedProps ?? {};
  node.status = "rendered";
  node.props = encode(normaliseIds(props.element?.props));
  if (props.bindings) node.bindings = props.bindings;
  const record = { ...node, emit: props.emit, element: props.element, bindings: props.bindings };
  nodes.set(id, record);

  const children = [];
  const slots = {};
  const component = catalogBoundary?.child;
  descendants(component, { repeat: scope.repeat, slot: undefined }, (childFiber, childScope) => {
    const ownScope = { ...childScope };
    if (childScope.repeat && childScope.repeat !== scope.repeat) ownScope.repeat = { ...childScope.repeat, owner: id };
    if (childScope.slot !== undefined) ownScope.slotOwner = id;
    const child = describe(childFiber, ownScope, id, registry, fallback, controls, nodes);
    if (childScope.slot !== undefined) (slots[childScope.slot] ??= []).push(child);
    else children.push(child);
  });
  if (children.length > 0) node.children = children;
  if (Object.keys(slots).length > 0) node.slots = slots;
  return node;
}

/** Whether a node that rendered nothing was hidden by its visible condition. */
function isVisible(element, scope, controls) {
  const ctx = { stateModel: controls.state?.getSnapshot() ?? {} };
  if (scope.repeat) {
    ctx.repeatItem = scope.repeat.item;
    ctx.repeatIndex = scope.repeat.index;
    ctx.repeatBasePath = scope.repeat.basePath;
  }
  const condition =
    element?.repeat !== undefined && !scope.repeat ? core.splitRepeatVisibility(element.visible).container : element?.visible;
  try {
    return condition === undefined ? true : core.evaluateVisibility(condition, ctx);
  } catch {
    return false;
  }
}

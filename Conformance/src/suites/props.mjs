// Prop expression resolution from @json-render/core. Unknown $computed
// warnings are deduplicated process-wide upstream, so every case that expects
// one uses a function name no other case uses.

import {
  createDirectiveRegistry,
  resolveActionParam,
  resolveBindings,
  resolveElementProps,
  resolvePropValue,
} from "@json-render/core";
import { captureConsole } from "../console.mjs";
import { capture, decode } from "../encoding.mjs";
import { computedFunctions, directives } from "../fixtures.mjs";

const registry = createDirectiveRegistry(directives);

function context(raw = {}) {
  const ctx = { stateModel: decode(raw.state ?? {}) };
  if ("repeatItem" in raw) ctx.repeatItem = decode(raw.repeatItem);
  if ("repeatIndex" in raw) ctx.repeatIndex = raw.repeatIndex;
  if ("repeatBasePath" in raw) ctx.repeatBasePath = raw.repeatBasePath;
  if (raw.functions) ctx.functions = computedFunctions;
  if (raw.directives) ctx.directives = registry;
  return ctx;
}

const ops = {
  resolve: (entry, ctx) => resolvePropValue(decode(entry.value), ctx),
  resolveProps: (entry, ctx) => resolveElementProps(decode(entry.value), ctx),
  bindings: (entry, ctx) => resolveBindings(decode(entry.value), ctx),
  actionParam: (entry, ctx) => resolveActionParam(decode(entry.value), ctx),
};

export function run(entry) {
  const op = ops[entry.op];
  if (!op) throw new Error(`unknown op ${entry.op}`);
  const ctx = context(entry.context);
  const { result, messages } = captureConsole(() => capture(() => op(entry, ctx)));
  return { ...result, messages };
}

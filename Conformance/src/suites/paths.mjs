// JSON Pointer reads and writes, repeat paths, findFormValue and
// resolveDynamicValue from @json-render/core.

import {
  addByPath,
  findFormValue,
  getByPath,
  removeByPath,
  resolveDynamicValue,
  resolveRepeatItemStatePath,
  resolveRepeatStatePath,
  setByPath,
} from "@json-render/core";
import { flattenToPointers, immutableSetByPath } from "@json-render/core/store-utils";
import { capture, decode, encode } from "../encoding.mjs";

const mutate = (fn) => (target, ...rest) => {
  try {
    fn(target, ...rest);
    return { value: encode(target) };
  } catch (error) {
    return { threw: error.message, partial: encode(target) };
  }
};

const ops = {
  get: (args) => capture(() => getByPath(...args)),
  set: (args) => mutate(setByPath)(...args),
  add: (args) => mutate(addByPath)(...args),
  remove: (args) => mutate(removeByPath)(...args),
  immutableSet: ([root, path, value]) =>
    capture(() => {
      const next = immutableSetByPath(root, path, value);
      return {
        result: next,
        sameRoot: next === root,
        sharedKeys: Object.keys(root).filter((key) => key in next && next[key] === root[key]),
      };
    }),
  repeatStatePath: (args) => capture(() => resolveRepeatStatePath(...args)),
  repeatItemStatePath: (args) => capture(() => resolveRepeatItemStatePath(...args)),
  findFormValue: (args) => capture(() => findFormValue(...args)),
  resolveDynamicValue: (args) => capture(() => resolveDynamicValue(...args)),
  flatten: (args) => capture(() => flattenToPointers(...args)),
};

export function run(entry) {
  const op = ops[entry.op];
  if (!op) throw new Error(`unknown op ${entry.op}`);
  return op(decode(entry.args));
}

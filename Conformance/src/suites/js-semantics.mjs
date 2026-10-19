// JavaScript language behaviour that json-render relies on: number and
// string conversion, JSON parsing order, truthiness and string comparison.
// These come from the Node engine itself, not from a guess.

import { capture, decode } from "../encoding.mjs";

const ops = {
  numberToString: (input) => String(input),
  toString: (input) => String(input),
  stringToNumber: (input) => Number(input),
  stringify: (input) => JSON.stringify(input),
  parseStringify: (input) => {
    const parsed = JSON.parse(input);
    return {
      stringified: JSON.stringify(parsed),
      keys: parsed && typeof parsed === "object" ? Object.keys(parsed) : null,
    };
  },
  truthy: (input) => Boolean(input),
  trim: (input) => input.trim(),
  length: (input) => input.length,
  lessThan: ([a, b]) => a < b,
  typeOf: (input) => typeof input,
  entries: (input) => Object.entries(input),
};

export function run(entry) {
  const op = ops[entry.op];
  if (!op) throw new Error(`unknown op ${entry.op}`);
  return capture(() => op(decode(entry.input)));
}

// Builds zod schemas from a small JSON description so the corpus can describe
// them as data. Each node is an array: [kind, ...arguments].

import { z } from "zod";

export function build(node) {
  const [kind, a, b, c] = node;
  switch (kind) {
    case "string": return applyString(z.string(), a ?? {});
    case "number": return applyNumber(z.number(), a ?? {});
    case "int": return applyNumber(z.int(), a ?? {});
    case "boolean": return z.boolean();
    case "null": return z.null();
    case "any": return z.any();
    case "unknown": return z.unknown();
    case "literal": return z.literal(a);
    case "enum": return z.enum(a);
    case "email": return z.email();
    case "url": return z.url();
    case "uuid": return z.uuid();
    case "array": return applyArray(z.array(build(a)), b ?? {});
    case "tuple": return b ? z.tuple(a.map(build), build(b)) : z.tuple(a.map(build));
    case "object": {
      const shape = Object.fromEntries(Object.entries(a).map(([key, value]) => [key, build(value)]));
      const options = b ?? {};
      if (options.strict) return z.strictObject(shape);
      if (options.loose) return z.looseObject(shape);
      if (options.catchall) return z.object(shape).catchall(build(options.catchall));
      return z.object(shape);
    }
    case "record": return z.record(build(a), build(b));
    case "union": return z.union(a.map(build));
    case "discriminated": return z.discriminatedUnion(a, b.map(build));
    case "intersection": return z.intersection(build(a), build(b));
    case "optional": return build(a).optional();
    case "nullable": return build(a).nullable();
    case "default": return build(a).default(b);
    case "tree": return treeSchema();
    default: throw new Error(`unknown zod node ${kind}`);
  }
  void c;
}

function applyString(schema, checks) {
  // Checks apply in the order the corpus lists them, as zod runs them in chain order.
  for (const [check, value] of Object.entries(checks)) {
    if (check === "min") schema = schema.min(value);
    if (check === "max") schema = schema.max(value);
    if (check === "length") schema = schema.length(value);
    if (check === "regex") schema = schema.regex(new RegExp(value));
  }
  return schema;
}

function applyNumber(schema, checks) {
  if (checks.min !== undefined) schema = schema.min(checks.min);
  if (checks.max !== undefined) schema = schema.max(checks.max);
  if (checks.gt !== undefined) schema = schema.gt(checks.gt);
  if (checks.lt !== undefined) schema = schema.lt(checks.lt);
  if (checks.multipleOf !== undefined) schema = schema.multipleOf(checks.multipleOf);
  return schema;
}

function applyArray(schema, checks) {
  if (checks.length !== undefined) schema = schema.length(checks.length);
  if (checks.min !== undefined) schema = schema.min(checks.min);
  if (checks.max !== undefined) schema = schema.max(checks.max);
  return schema;
}

/** The parts of a zod issue the Swift tests compare. */
export function issues(error) {
  return error.issues.map((issue) => ({ code: issue.code, path: issue.path, message: issue.message }));
}

/** A recursive tree schema, for `$ref: "#"` coverage. */
export function treeSchema() {
  const tree = z.object({
    name: z.string(),
    get children() {
      return z.array(tree);
    },
  });
  return tree;
}

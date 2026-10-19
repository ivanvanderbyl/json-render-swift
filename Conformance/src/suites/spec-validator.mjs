// Structural spec validation from @json-render/core.

import { autoFixSpec, formatSpecIssues, validateSpec } from "@json-render/core";
import { capture, decode } from "../encoding.mjs";

export function run(entry) {
  switch (entry.op) {
    case "validate":
      return capture(() => validateSpec(decode(entry.spec), decode(entry.options ?? {})));
    case "autoFix":
      return capture(() => autoFixSpec(decode(entry.spec), decode(entry.options ?? {})));
    case "format":
      return capture(() => formatSpecIssues(decode(entry.issues)));
    default:
      throw new Error(`unknown op ${entry.op}`);
  }
}

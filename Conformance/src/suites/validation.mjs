// Form validation from @json-render/core.

import { builtInValidationFunctions, runValidation, runValidationCheck } from "@json-render/core";
import { captureConsole } from "../console.mjs";
import { capture, decode } from "../encoding.mjs";
import { validationFunctions } from "../fixtures.mjs";

function context(raw = {}) {
  const ctx = { value: decode(raw.value), stateModel: decode(raw.state ?? {}) };
  if (raw.custom) ctx.customFunctions = validationFunctions;
  return ctx;
}

export function run(entry) {
  const { result, messages } = captureConsole(() =>
    capture(() => {
      switch (entry.op) {
        case "builtin":
          return "args" in entry
            ? builtInValidationFunctions[entry.fn](decode(entry.value), decode(entry.args))
            : builtInValidationFunctions[entry.fn](decode(entry.value));
        case "check":
          return runValidationCheck(decode(entry.check), context(entry.context));
        case "run":
          return runValidation(decode(entry.config), context(entry.context));
        default:
          throw new Error(`unknown op ${entry.op}`);
      }
    }),
  );
  return { ...result, messages };
}

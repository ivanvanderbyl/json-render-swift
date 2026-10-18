// Action resolution and execution from @json-render/core.

import { actionBinding, executeAction, interpolateString, resolveAction } from "@json-render/core";
import { capture, decode, encode } from "../encoding.mjs";

export async function run(entry) {
  switch (entry.op) {
    case "resolve":
      return capture(() => resolveAction(decode(entry.binding), decode(entry.state ?? {})));
    case "interpolate":
      return capture(() => interpolateString(entry.template, decode(entry.state ?? {})));
    case "builder":
      return capture(() => actionBinding[entry.builder](...decode(entry.args)));
    case "execute": {
      const calls = [];
      const behaviour = entry.handler ?? {};
      const context = {
        action: decode(entry.action),
        handler: async (params) => {
          calls.push({ fn: "handler", params: encode(params) });
          if (behaviour.reject !== undefined) throw new Error(behaviour.reject);
          return behaviour.resolve;
        },
        setState: (path, value) => {
          calls.push({ fn: "setState", path, value: encode(value) });
          if (behaviour.setStateThrows) throw new Error("setState failed");
        },
      };
      if (entry.navigate) context.navigate = (path) => calls.push({ fn: "navigate", path: encode(path) });
      if (entry.executeAction) {
        context.executeAction = async (binding) => {
          calls.push({ fn: "executeAction", binding: encode(binding) });
          if (entry.executeActionRejects) throw new Error("follow-up failed");
        };
      }
      try {
        await executeAction(context);
        return { calls, outcome: "resolved" };
      } catch (error) {
        return { calls, outcome: "rejected", error: error.message };
      }
    }
    default:
      throw new Error(`unknown op ${entry.op}`);
  }
}

// Visibility conditions from @json-render/core.

import {
  conditionUsesItemScope,
  evaluateVisibility,
  splitRepeatVisibility,
  VisibilityConditionStrictSchema,
} from "@json-render/core";
import { capture, decode } from "../encoding.mjs";

export function run(entry) {
  const condition = decode(entry.condition);
  const context = decode(entry.context ?? { stateModel: {} });
  switch (entry.op) {
    case "evaluate":
      return capture(() => evaluateVisibility(condition, context));
    case "usesItemScope":
      return capture(() => conditionUsesItemScope(condition));
    case "split":
      return capture(() => splitRepeatVisibility(condition));
    case "strictValid":
      return capture(() => VisibilityConditionStrictSchema.safeParse(condition).success);
    default:
      throw new Error(`unknown op ${entry.op}`);
  }
}

// createStateStore from @json-render/core: a sequence of reads and writes,
// recording the snapshot, notifications and which top-level values kept
// their identity after each step.

import { createStateStore } from "@json-render/core";
import { capture, decode, encode } from "../encoding.mjs";

export function run(entry) {
  const store = createStateStore(decode(entry.initial ?? {}));
  let notifications = 0;
  store.subscribe(() => {
    notifications += 1;
  });
  return entry.steps.map((step) => {
    const before = store.getSnapshot();
    const count = notifications;
    const result = capture(() => {
      if (step.op === "set") return store.set(step.path, decode(step.value));
      if (step.op === "update") return store.update(decode(step.updates));
      if (step.op === "get") return store.get(step.path);
      throw new Error(`unknown op ${step.op}`);
    });
    const after = store.getSnapshot();
    return {
      result,
      notified: notifications - count,
      snapshotChanged: before !== after,
      sharedKeys: Object.keys(before).filter((key) => key in after && after[key] === before[key]),
      snapshot: encode(after),
    };
  });
}

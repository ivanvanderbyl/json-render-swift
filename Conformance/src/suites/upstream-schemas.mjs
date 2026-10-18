// The zod schemas @json-render/core exports, as JSON Schema (io: "input").
// The Swift package embeds these documents; its tests check they still match.

import * as core from "@json-render/core";
import { z } from "zod";

export function run(entry) {
  const schema = z.toJSONSchema(core[entry.export], { io: "input" });
  delete schema.$schema;
  return schema;
}

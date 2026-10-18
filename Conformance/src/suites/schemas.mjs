// zod schemas exported with z.toJSONSchema(schema, { io: "input" }), and the
// verdicts zod reaches for sample values. The Swift tests import the exported
// JSON Schema and must reach the same verdicts, data and issues.

import { z } from "zod";
import { decode, encode } from "../encoding.mjs";
import { build, issues } from "../zod-dsl.mjs";

export function run(entry) {
  const schema = build(entry.zod);
  return {
    jsonSchema: z.toJSONSchema(schema, { io: "input" }),
    results: entry.values.map((raw) => {
      const result = schema.safeParse(decode(raw));
      return result.success
        ? { success: true, data: encode(result.data) }
        : { success: false, issues: issues(result.error) };
    }),
  };
}

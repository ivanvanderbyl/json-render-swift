// Named functions and directives the corpus can refer to. The Swift tests
// register equivalents with the same names (Tests/ConformanceTests/Support/Fixtures.swift).

import { defineDirective, resolvePropValue } from "@json-render/core";
import { z } from "zod";

export const computedFunctions = {
  fullName: (args) => `${args.first} ${args.last}`,
  double: (args) => args.value * 2,
  echo: (args) => args,
  argCount: (args) => Object.keys(args).length,
  fails: () => {
    throw new Error("computed failed");
  },
};

export const directives = [
  defineDirective({
    name: "$double",
    schema: z.object({ $double: z.unknown() }),
    resolve: (value, ctx) => resolvePropValue(value.$double, ctx) * 2,
  }),
  defineDirective({
    name: "$upper",
    schema: z.object({ $upper: z.unknown() }),
    resolve: (value, ctx) => String(resolvePropValue(value.$upper, ctx)).toUpperCase(),
  }),
  defineDirective({
    name: "$join",
    schema: z.object({ $join: z.array(z.unknown()), separator: z.string().optional() }),
    resolve: (value, ctx) =>
      value.$join.map((part) => resolvePropValue(part, ctx)).join(value.separator ?? ","),
  }),
  defineDirective({
    name: "$fails",
    schema: z.object({ $fails: z.unknown() }),
    resolve: () => {
      throw new Error("directive failed");
    },
  }),
];

export const validationFunctions = {
  startsWithA: (value) => typeof value === "string" && value.startsWith("A"),
  isEven: (value) => typeof value === "number" && value % 2 === 0,
  hasArg: (value, args) => args !== undefined && Object.keys(args).length > 0,
};

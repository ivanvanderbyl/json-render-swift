// Tagged JSON lets the corpus and goldens carry JavaScript values that plain
// JSON cannot: undefined, NaN, the infinities, negative zero, functions and
// errors. The Swift tests decode the same tags.
//
//   {"$js": "undefined" | "NaN" | "Infinity" | "-Infinity" | "-0" | "function"}
//   {"$js": "error", "message": "..."}
//   {"$js": "object", "value": {...}}   an object that has its own "$js" key
//   {"$js": "hole"}                      an empty array slot

export function encode(value, seen = new Set()) {
  if (value === undefined) return { $js: "undefined" };
  if (typeof value === "number") {
    if (Number.isNaN(value)) return { $js: "NaN" };
    if (value === Infinity) return { $js: "Infinity" };
    if (value === -Infinity) return { $js: "-Infinity" };
    if (Object.is(value, -0)) return { $js: "-0" };
    return value;
  }
  if (typeof value === "function") return { $js: "function" };
  if (value === null || typeof value !== "object") return value;
  if (value instanceof Error) return { $js: "error", message: value.message };
  if (seen.has(value)) return { $js: "cycle" };
  seen.add(value);
  try {
    if (Array.isArray(value)) {
      const out = [];
      for (let i = 0; i < value.length; i++) {
        out.push(i in value ? encode(value[i], seen) : { $js: "hole" });
      }
      return out;
    }
    const out = {};
    for (const key of Object.keys(value)) out[key] = encode(value[key], seen);
    return "$js" in value ? { $js: "object", value: out } : out;
  } finally {
    seen.delete(value);
  }
}

export function decode(value) {
  if (Array.isArray(value)) {
    const out = [];
    value.forEach((item, index) => {
      if (item && typeof item === "object" && item.$js === "hole") {
        out.length = index + 1;
      } else {
        out[index] = decode(item);
      }
    });
    return out;
  }
  if (value === null || typeof value !== "object") return value;
  if ("$js" in value) {
    switch (value.$js) {
      case "undefined":
        return undefined;
      case "NaN":
        return NaN;
      case "Infinity":
        return Infinity;
      case "-Infinity":
        return -Infinity;
      case "-0":
        return -0;
      case "object":
        return decodeObject(value.value);
      default:
        throw new Error(`cannot decode tag ${value.$js}`);
    }
  }
  return decodeObject(value);
}

function decodeObject(value) {
  const out = {};
  for (const key of Object.keys(value)) out[key] = decode(value[key]);
  return out;
}

/** Run fn, returning {value} or {threw: message}. */
export function capture(fn) {
  try {
    return { value: encode(fn()) };
  } catch (error) {
    return { threw: error instanceof Error ? error.message : String(error) };
  }
}

export async function captureAsync(fn) {
  try {
    return { value: encode(await fn()) };
  } catch (error) {
    return { threw: error instanceof Error ? error.message : String(error) };
  }
}

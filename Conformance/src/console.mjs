// Captures console.warn and console.error so goldens record the diagnostics
// upstream emits. The Swift tests compare them with Diagnostics messages.

function format(args) {
  return args
    .map((arg) => {
      if (typeof arg === "string") return arg;
      if (arg instanceof Error) return arg.message;
      try {
        return JSON.stringify(arg);
      } catch {
        return String(arg);
      }
    })
    .join(" ");
}

export function captureConsole(fn) {
  const messages = [];
  const { warn, error } = console;
  console.warn = (...args) => messages.push({ level: "warning", text: format(args) });
  console.error = (...args) => messages.push({ level: "error", text: format(args) });
  try {
    const result = fn();
    return { result, messages };
  } finally {
    console.warn = warn;
    console.error = error;
  }
}

export async function captureConsoleAsync(fn) {
  const messages = [];
  const { warn, error } = console;
  console.warn = (...args) => messages.push({ level: "warning", text: format(args) });
  console.error = (...args) => messages.push({ level: "error", text: format(args) });
  try {
    const result = await fn();
    return { result, messages };
  } finally {
    console.warn = warn;
    console.error = error;
  }
}

// Streaming from @json-render/core and @json-render/react: SpecStream lines,
// spec patches, compilers, mixed text and JSONL parsing, the AI SDK chunk
// transform, nested specs, message parts and the React Native useUIStream hook.

import "../render/dom.mjs";
import {
  applySpecPatch,
  compileSpecStream,
  createJsonRenderTransform,
  createMixedStreamParser,
  createSpecStreamCompiler,
  nestedToFlat,
  parseSpecStreamLine,
} from "@json-render/core";
import { buildSpecFromParts, flatToTree, getTextFromParts } from "@json-render/react";
import { useUIStream } from "@json-render/react-native";
import React, { act } from "react";
import { createRoot } from "react-dom/client";
import { captureConsoleAsync } from "../console.mjs";
import { capture, captureAsync, decode, encode } from "../encoding.mjs";

const ops = {
  parseLine: (entry) => capture(() => parseSpecStreamLine(entry.line)),
  applySpec: (entry) => {
    const spec = decode(entry.spec);
    const steps = [];
    for (const patch of entry.patches) {
      try {
        applySpecPatch(spec, decode(patch));
        steps.push({ value: encode(spec) });
      } catch (error) {
        steps.push({ threw: error.message, partial: encode(spec) });
        break;
      }
    }
    return steps;
  },
  compile: (entry) => capture(() => compileSpecStream(entry.stream, decode(entry.initial ?? {}))),
  compiler: (entry) => {
    const compiler = createSpecStreamCompiler(decode(entry.initial ?? {}));
    const pushes = entry.chunks.map((chunk) =>
      capture(() => {
        const { result, newPatches } = compiler.push(chunk);
        return { result, newPatches };
      }),
    );
    const result = capture(() => compiler.getResult());
    return { pushes, result, patches: encode(compiler.getPatches()) };
  },
  mixed: (entry) => {
    const events = [];
    const parser = createMixedStreamParser({
      onPatch: (patch) => events.push({ patch: encode(patch) }),
      onText: (text) => events.push({ text }),
    });
    for (const chunk of entry.chunks) parser.push(chunk);
    if (entry.flush !== false) parser.flush();
    return events;
  },
  transform: (entry) => captureAsync(() => transform(entry.chunks)),
  nested: (entry) => capture(() => nestedToFlat(decode(entry.nested))),
  specFromParts: (entry) => capture(() => buildSpecFromParts(decode(entry.parts))),
  textFromParts: (entry) => capture(() => getTextFromParts(decode(entry.parts))),
  flatToTree: (entry) => capture(() => flatToTree(decode(entry.elements))),
  uiStream: (entry) => uiStream(entry),
};

async function transform(chunks) {
  const stream = createJsonRenderTransform();
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();
  const output = [];
  const reading = (async () => {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      output.push(value);
    }
  })();
  for (const chunk of chunks) await writer.write(chunk);
  await writer.close();
  await reading;
  return output;
}

/**
 * Streams scripted responses through @json-render/react-native's useUIStream,
 * recording the hook's state once it has handled each chunk. Each request the
 * hook makes takes the next scripted response.
 */
async function uiStream(entry) {
  const encoder = new TextEncoder();
  const responses = entry.responses ?? [{ status: entry.status, errorBody: entry.errorBody, chunks: entry.chunks ?? [] }];
  const requests = [];
  const opened = [];
  const fetch = async (url, init) => {
    requests.push({ url, method: init.method, headers: init.headers, body: encode(JSON.parse(init.body)) });
    const response = responses[requests.length - 1] ?? { chunks: [] };
    if (response.status && response.status !== 200) {
      const body = "rawErrorBody" in response ? response.rawErrorBody : JSON.stringify(response.errorBody ?? {});
      return new Response(body, { status: response.status });
    }
    let controller;
    const body = new ReadableStream({ start: (c) => (controller = c) });
    init.signal.addEventListener("abort", () => {
      try {
        controller.error(new DOMException("This operation was aborted", "AbortError"));
      } catch {}
    });
    opened.push({ controller, response });
    return new Response(body, { status: 200 });
  };

  let latest;
  const completed = [];
  const errors = [];
  function Probe() {
    latest = useUIStream({
      api: "/stream",
      fetch,
      validate: entry.validate,
      maxRetries: entry.maxRetries,
      onComplete: (spec) => completed.push(encode(spec)),
      onError: (error) => errors.push(error.message),
    });
    return null;
  }
  const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
  const snapshot = () => ({
    spec: encode(latest.spec),
    rawLines: latest.rawLines,
    isStreaming: latest.isStreaming,
    error: latest.error ? latest.error.message : null,
  });
  const bytes = (chunk) => (typeof chunk === "string" ? encoder.encode(chunk) : new Uint8Array(chunk.bytes));

  const { result: steps, messages } = await captureConsoleAsync(async () => {
    const root = createRoot(document.createElement("div"));
    await act(async () => root.render(React.createElement(Probe)));
    let sending;
    await act(async () => {
      sending = latest.send("prompt", entry.context ? decode(entry.context) : undefined);
      await flush();
    });
    const steps = [snapshot()];
    while (opened.length > 0) {
      const { controller, response } = opened.shift();
      for (const chunk of response.chunks ?? []) {
        await act(async () => {
          try {
            controller.enqueue(bytes(chunk));
          } catch {}
          await flush();
          await flush();
        });
        steps.push(snapshot());
      }
      if (response.stop) {
        await act(async () => {
          latest.stop();
          await flush();
          await flush();
        });
        steps.push(snapshot());
        break;
      }
      await act(async () => {
        try {
          controller.close();
        } catch {}
        await flush();
        await flush();
      });
      steps.push(snapshot());
    }
    await act(async () => {
      await sending;
      await flush();
    });
    steps.push(snapshot());
    await act(async () => root.unmount());
    return steps;
  });
  return { steps, completed, errors, requests, messages };
}

export function run(entry) {
  const op = ops[entry.op];
  if (!op) throw new Error(`unknown op ${entry.op}`);
  return op(entry);
}

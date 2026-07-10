// chrome_bench.mjs — drive HEADED Chrome via the DevTools Protocol, scrape the one
// `BENCH: {json}` console line the web_bench overlay emits, then read JS-heap memory.
//
//   node chrome_bench.mjs <url> [timeout_ms]
//
// HEADED on purpose: a headless/SwiftShader GPU would not be the real ceiling. The BENCH
// json already carries the WebGL renderer string so the run self-verifies it hit real GPU.
// Node 22 globals only (WebSocket + fetch) — no npm deps, same runtime policy as tools/.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const url = process.argv[2];
const timeoutMs = Number(process.argv[3] ?? 60000);
const port = 9333 + Math.floor(Math.random() * 400);
if (!url) {
  console.error("usage: node chrome_bench.mjs <url> [timeout_ms]");
  process.exit(2);
}

const profile = mkdtempSync(join(tmpdir(), "chrome-bench-"));
const chrome = spawn(CHROME, [
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${profile}`,
  "--no-first-run",
  "--no-default-browser-check",
  "--new-window",
  "--window-size=1300,820",
  "--use-angle=metal", // real GPU path on macOS
  url,
], { stdio: "ignore" });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function cleanup(code) {
  try { chrome.kill("SIGKILL"); } catch {}
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
  process.exit(code);
}

// Find the page target's websocket debugger URL (poll until Chrome is up).
async function pageWsUrl() {
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json`);
      const targets = await res.json();
      const page = targets.find((t) => t.type === "page" && t.webSocketDebuggerUrl);
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await sleep(250);
  }
  throw new Error("chrome CDP endpoint never came up");
}

async function main() {
  const wsUrl = await pageWsUrl();
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const mid = ++id;
      pending.set(mid, resolve);
      ws.send(JSON.stringify({ id: mid, method, params }));
    });

  let benchLine = null;
  let done = false;

  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg.result);
      pending.delete(msg.id);
      return;
    }
    if (msg.method === "Runtime.consoleAPICalled") {
      const text = (msg.params.args || [])
        .map((a) => (a.value !== undefined ? a.value : ""))
        .join(" ");
      if (text.startsWith("BENCH:") && !done) {
        benchLine = text;
        done = true;
      }
    }
  });

  await new Promise((r) => ws.addEventListener("open", r));
  await send("Runtime.enable");
  await send("Performance.enable");

  const deadline = Date.now() + timeoutMs;
  while (!done && Date.now() < deadline) await sleep(200);

  if (!benchLine) {
    console.error("TIMEOUT: no BENCH line within " + timeoutMs + " ms");
    cleanup(1);
    return;
  }

  // JS-heap memory right after the measure window closed.
  const metrics = await send("Performance.getMetrics");
  const m = Object.fromEntries((metrics.metrics || []).map((x) => [x.name, x.value]));
  const heapMb = m.JSHeapUsedSize ? (m.JSHeapUsedSize / 1048576).toFixed(1) : "n/a";
  const heapTotalMb = m.JSHeapTotalSize ? (m.JSHeapTotalSize / 1048576).toFixed(1) : "n/a";

  console.log(benchLine);
  console.log(`MEM: {"js_heap_used_mb":${heapMb},"js_heap_total_mb":${heapTotalMb}}`);
  cleanup(0);
}

main().catch((e) => {
  console.error("ERROR:", e.message);
  cleanup(1);
});

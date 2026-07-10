// chrome_console.mjs — load a URL in HEADED Chrome, auto-attach to every frame/target, and
// collect ALL console messages + thrown exceptions for a fixed window, then print them.
// Used for the Grafana-iframe attempts: the Godot boot error (or success) happens INSIDE the
// embedded iframe, so we auto-attach (flatten) to capture the child frame's console too.
//
//   node chrome_console.mjs <url> [seconds]
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const url = process.argv[2];
const seconds = Number(process.argv[3] ?? 18);
const port = 9800 + Math.floor(Math.random() * 150);
const profile = mkdtempSync(join(tmpdir(), "chrome-con-"));
const chrome = spawn(CHROME, [
  `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check", "--new-window",
  "--window-size=1300,900", "--use-angle=metal", url,
], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const lines = [];
function cleanup(code) { try { chrome.kill("SIGKILL"); } catch {} try { rmSync(profile, { recursive: true, force: true }); } catch {} process.exit(code); }

async function pageWsUrl() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/json`);
      const t = await r.json();
      const p = t.find((x) => x.type === "page" && x.webSocketDebuggerUrl);
      if (p) return p.webSocketDebuggerUrl;
    } catch {}
    await sleep(250);
  }
  throw new Error("CDP never came up");
}

function wire(ws, tag) {
  let id = 0;
  const send = (method, params = {}, sessionId) =>
    ws.send(JSON.stringify({ id: ++id + (sessionId ? 100000 : 0), method, params, sessionId }));
  ws.addEventListener("message", (ev) => {
    const m = JSON.parse(ev.data);
    const sid = m.sessionId ? `[${tag}:${m.sessionId.slice(0, 6)}]` : `[${tag}]`;
    if (m.method === "Runtime.consoleAPICalled") {
      const txt = (m.params.args || []).map((a) => (a.value !== undefined ? a.value : a.description || "")).join(" ");
      lines.push(`${sid} console.${m.params.type}: ${txt}`);
    } else if (m.method === "Runtime.exceptionThrown") {
      const d = m.params.exceptionDetails;
      lines.push(`${sid} EXCEPTION: ${d.exception?.description || d.text}`);
    } else if (m.method === "Log.entryAdded") {
      lines.push(`${sid} log.${m.params.entry.level}: ${m.params.entry.text}`);
    } else if (m.method === "Target.attachedToTarget") {
      const s = m.params.sessionId;
      // enable domains on the freshly attached child target
      ws.send(JSON.stringify({ id: ++id + 200000, method: "Runtime.enable", sessionId: s }));
      ws.send(JSON.stringify({ id: ++id + 200000, method: "Log.enable", sessionId: s }));
      ws.send(JSON.stringify({ id: ++id + 200000, method: "Runtime.runIfWaitingForDebugger", sessionId: s }));
    }
  });
  return send;
}

async function main() {
  const wsUrl = await pageWsUrl();
  const ws = new WebSocket(wsUrl);
  await new Promise((r) => ws.addEventListener("open", r));
  const send = wire(ws, "top");
  send("Runtime.enable");
  send("Log.enable");
  send("Page.enable");
  send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });
  await sleep(seconds * 1000);
  console.log(lines.join("\n"));
  console.log(`--- collected ${lines.length} console/log/exception lines in ${seconds}s ---`);
  cleanup(0);
}
main().catch((e) => { console.error("ERROR:", e.message); cleanup(1); });

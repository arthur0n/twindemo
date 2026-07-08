// S2 spike simulator: WebSocket server publishing JSON tag frames at 10 Hz.
// Seeded PRNG (mulberry32) => deterministic across runs (test fixture pattern).
// Usage: node server.js [--seed 42] [--port 8765] [--hz 10]
'use strict';

const { WebSocketServer } = require('ws');
const fs = require('fs');
const path = require('path');

// --- CLI args ---
function arg(name, def) {
  const i = process.argv.indexOf('--' + name);
  return i !== -1 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : def;
}
const SEED = Number(arg('seed', 42));
const PORT = Number(arg('port', 8765));
const HZ = Number(arg('hz', 10));

// --- mulberry32 seeded PRNG ---
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = mulberry32(SEED);

// --- tags: base sine + seeded jitter, deterministic per (seed, tick) ---
const TAGS = [
  { tag: 'pump_1.temp',      min: 40,  max: 90,   period: 80 },
  { tag: 'pump_2.temp',      min: 40,  max: 90,   period: 130 },
  { tag: 'valve_3.pressure', min: 1,   max: 8,    period: 60 },
  { tag: 'tank_1.level',     min: 0,   max: 100,  period: 200 },
  { tag: 'motor_2.rpm',      min: 900, max: 1800, period: 100 },
];

function valueFor(t, tick) {
  const mid = (t.min + t.max) / 2;
  const amp = (t.max - t.min) / 2;
  // 80% sine + 20% seeded noise; PRNG consumed in fixed order (one call per tag per tick)
  const s = Math.sin((2 * Math.PI * tick) / t.period);
  const n = (rand() - 0.5) * 2;
  const v = mid + amp * (0.8 * s + 0.2 * n);
  return Math.round(v * 100) / 100;
}

const wss = new WebSocketServer({ port: PORT });
let clients = new Set();
wss.on('connection', (ws) => {
  clients.add(ws);
  console.log(`[sim] client connected (${clients.size} total)`);
  ws.on('close', () => {
    clients.delete(ws);
    console.log(`[sim] client disconnected (${clients.size} total)`);
  });
  ws.on('error', () => {});
});

let tick = 0;
const seq = Object.fromEntries(TAGS.map((t) => [t.tag, 0]));
let framesSent = 0; // frames actually delivered to >=1 client
let framesGenerated = 0;

const interval = setInterval(() => {
  for (const t of TAGS) {
    const frame = {
      tag: t.tag,
      value: valueFor(t, tick),
      seq: seq[t.tag]++,
      sent_ms: Date.now(),
    };
    framesGenerated++;
    if (clients.size > 0) {
      const msg = JSON.stringify(frame);
      for (const ws of clients) if (ws.readyState === 1) ws.send(msg);
      framesSent++;
    }
  }
  tick++;
}, 1000 / HZ);

function writeStats() {
  const stats = {
    seed: SEED,
    hz: HZ,
    ticks: tick,
    frames_generated: framesGenerated,
    frames_sent_to_clients: framesSent,
    per_tag_last_seq: { ...seq },
  };
  fs.writeFileSync(path.join(__dirname, 'stats.json'), JSON.stringify(stats, null, 2));
  return stats;
}
setInterval(writeStats, 1000);

process.on('SIGINT', () => {
  clearInterval(interval);
  console.log('[sim] final stats:', JSON.stringify(writeStats()));
  process.exit(0);
});
process.on('SIGTERM', () => {
  clearInterval(interval);
  writeStats();
  process.exit(0);
});

console.log(`[sim] ws://localhost:${PORT} @ ${HZ} Hz, seed=${SEED}, ${TAGS.length} tags`);

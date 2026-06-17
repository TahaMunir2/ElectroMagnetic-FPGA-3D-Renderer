// Single source of truth for the PS WebSocket link.
// Ported from the original app.js. Any component can import `status` and the
// send helpers; only this file knows about the socket.

import { writable } from "svelte/store";

// "disconnected" | "connecting" | "connected" | "error"
export const status = writable("disconnected");
export const lastMessage = writable("Not connected.");
export const hardwareValues = writable(null);  // live knob/panel values in hardware mode
export let lastServerUrl = "http://127.0.0.1:8000";
export function getServerUrl() { return lastServerUrl; }

let socket = null;
let manualDisconnect = false;
let reconnectTimer = null;

// Pending params are coalesced and flushed at ~30 Hz, exactly like app.js.
let pending = {};
let dirty = false;

function httpToWs(httpUrl) {
  const url = new URL(httpUrl);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = "/ws/control";
  url.search = "";
  url.hash = "";
  return url.toString();
}

export function connect(serverUrl) {
  clearTimeout(reconnectTimer);
  manualDisconnect = false;

  let wsUrl;
  try {
    const raw = serverUrl.trim() || "http://127.0.0.1:8000";
    lastServerUrl = raw.match(/^https?:\/\//) ? raw : ("http://" + raw);
    const withScheme = /^[a-z]+:\/\//i.test(raw) ? raw : `http://${raw}`;
    wsUrl = httpToWs(withScheme);
  } catch (e) {
    status.set("error");
    lastMessage.set("Invalid server URL.");
    return;
  }

  status.set("connecting");
  lastMessage.set(`Opening ${wsUrl}`);
  socket = new WebSocket(wsUrl);

  socket.addEventListener("open", () => {
    status.set("connected");
    lastMessage.set("WebSocket connected.");
  });

  socket.addEventListener("message", (event) => {
    try {
      const data = JSON.parse(event.data);
      if (data.type === "hardware") { hardwareValues.set(data.values || null); return; }
      if (data.ok === false) lastMessage.set(`Server error: ${data.error}`);
      else if (typeof data.count === "number") lastMessage.set(`Wrote ${data.count} registers.`);
    } catch {
      lastMessage.set(event.data);
    }
  });

  socket.addEventListener("close", () => {
    socket = null;
    if (manualDisconnect) {
      status.set("disconnected");
      lastMessage.set("Disconnected.");
      return;
    }
    status.set("error");
    lastMessage.set("Connection lost. Reconnecting in 1 s.");
    reconnectTimer = setTimeout(() => connect(serverUrl), 1000);
  });

  socket.addEventListener("error", () => {
    status.set("error");
    lastMessage.set("WebSocket error.");
  });
}

export function disconnect() {
  manualDisconnect = true;
  clearTimeout(reconnectTimer);
  if (socket) socket.close();
  socket = null;
  status.set("disconnected");
}

// Queue a single parameter; it goes out on the next 30 Hz flush.
export function setParam(key, value) {
  pending[key] = value;
  dirty = true;
}

// Flush immediately (e.g. on a button press).
export function flushNow() {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  socket.send(JSON.stringify({ type: "params", ...pending }));
  dirty = false;
}

// Start the 30 Hz throttle loop once, at module load.
setInterval(() => {
  if (!dirty) return;
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  socket.send(JSON.stringify({ type: "params", ...pending }));
  dirty = false;
}, 33);

// Load an overlay on the PS (2d or 3d). HTTP POST, not WebSocket.
export async function loadOverlay(serverUrl, mode) {
  const base = serverUrl.replace(/\/$/, "");
  const res = await fetch(`${base}/overlay/load`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mode }),
  });
  if (!res.ok) throw new Error(`overlay load failed: ${res.status}`);
  return res.json();
}

// Set the PS input authority: "ui" or "hardware". HTTP POST.
export async function setInputSource(serverUrl, source) {
  const base = (serverUrl || getServerUrl()).replace(/\/$/, "");
  const res = await fetch(`${base}/input/source`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ source }),
  });
  if (!res.ok) throw new Error(`input source failed: ${res.status}`);
  return res.json();
}

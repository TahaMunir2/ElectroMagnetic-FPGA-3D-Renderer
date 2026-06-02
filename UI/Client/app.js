const controls = [
  "yaw",
  "pitch",
  "camera_x",
  "camera_y",
  "camera_z",
  "height_scale",
  "colour_mode",
  "render_mode",
  "max_depth",
  "step_size",
];

const defaults = {
  yaw: 1024,
  pitch: 128,
  camera_x: 0,
  camera_y: 0,
  camera_z: 8192,
  height_scale: 180,
  colour_mode: 0,
  render_mode: 0,
  max_depth: 64,
  step_size: 1,
};

const els = {
  serverUrl: document.getElementById("serverUrl"),
  connectBtn: document.getElementById("connectBtn"),
  disconnectBtn: document.getElementById("disconnectBtn"),
  statusDot: document.getElementById("statusDot"),
  statusText: document.getElementById("statusText"),
  previewToggle: document.getElementById("previewToggle"),
  refreshPreviewBtn: document.getElementById("refreshPreviewBtn"),
  previewImage: document.getElementById("previewImage"),
  previewPlaceholder: document.getElementById("previewPlaceholder"),
  previewStatus: document.getElementById("previewStatus"),
  lastMessage: document.getElementById("lastMessage"),
  resetBtn: document.getElementById("resetBtn"),
};

let socket = null;
let connected = false;
let dirty = true;
let reconnectTimer = null;
let manualDisconnect = false;

function normalizeServerUrl(raw) {
  const value = raw.trim() || "http://192.168.2.99:8000";
  const withScheme = /^[a-z]+:\/\//i.test(value) ? value : `http://${value}`;
  return new URL(withScheme);
}

function websocketUrl(httpUrl) {
  const url = new URL(httpUrl);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = "/ws/control";
  url.search = "";
  url.hash = "";
  return url.toString();
}

function previewUrl(httpUrl) {
  const url = new URL(httpUrl);
  url.pathname = "/preview.mjpg";
  url.search = `t=${Date.now()}`;
  url.hash = "";
  return url.toString();
}

function setStatus(state, text) {
  els.statusDot.className = `status-dot ${state}`;
  els.statusText.textContent = text;
}

function setMessage(text) {
  els.lastMessage.textContent = text;
}

function getControlValue(id) {
  const el = document.getElementById(id);
  return Number.parseInt(el.value, 10);
}

function collectParams() {
  return controls.reduce(
    (payload, id) => {
      payload[id] = getControlValue(id);
      return payload;
    },
    { type: "params" },
  );
}

function updateOutput(id) {
  const output = document.getElementById(`${id}Value`);
  if (output) {
    output.value = document.getElementById(id).value;
  }
}

function markDirty() {
  dirty = true;
}

function sendCurrentParams(force = false) {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    return;
  }
  if (!dirty && !force) {
    return;
  }
  socket.send(JSON.stringify(collectParams()));
  dirty = false;
}

function enableUiForConnection(isConnected) {
  connected = isConnected;
  els.connectBtn.disabled = isConnected;
  els.disconnectBtn.disabled = !isConnected;
}

function connect() {
  clearTimeout(reconnectTimer);
  manualDisconnect = false;

  let serverUrl;
  let wsUrl;
  try {
    serverUrl = normalizeServerUrl(els.serverUrl.value);
    wsUrl = websocketUrl(serverUrl);
    els.serverUrl.value = serverUrl.toString().replace(/\/$/, "");
  } catch (error) {
    setStatus("error", "Invalid server URL");
    setMessage(error.message);
    return;
  }

  setStatus("connecting", "Connecting");
  setMessage(`Opening ${wsUrl}`);
  socket = new WebSocket(wsUrl);

  socket.addEventListener("open", () => {
    enableUiForConnection(true);
    setStatus("connected", "Connected");
    setMessage("WebSocket connected.");
    updatePreview();
    sendCurrentParams(true);
  });

  socket.addEventListener("message", (event) => {
    try {
      const data = JSON.parse(event.data);
      if (data.ok === false) {
        setMessage(`Server error: ${data.error}`);
      } else if (typeof data.count === "number") {
        setMessage(`Wrote ${data.count} registers.`);
      }
    } catch {
      setMessage(event.data);
    }
  });

  socket.addEventListener("close", () => {
    enableUiForConnection(false);
    socket = null;
    if (manualDisconnect) {
      setStatus("disconnected", "Disconnected");
      setMessage("Disconnected.");
      return;
    }
    setStatus("error", "Disconnected");
    setMessage("Connection lost. Reconnecting in 1 second.");
    reconnectTimer = setTimeout(connect, 1000);
  });

  socket.addEventListener("error", () => {
    setStatus("error", "Error");
    setMessage("WebSocket error.");
  });
}

function disconnect() {
  manualDisconnect = true;
  clearTimeout(reconnectTimer);
  if (socket) {
    socket.close();
  }
  socket = null;
  enableUiForConnection(false);
  setStatus("disconnected", "Disconnected");
}

function updatePreview() {
  if (!els.previewToggle.checked) {
    els.previewImage.removeAttribute("src");
    els.previewImage.classList.remove("active");
    els.previewPlaceholder.classList.remove("hidden");
    els.previewStatus.textContent = "Disabled";
    return;
  }

  try {
    const url = previewUrl(normalizeServerUrl(els.serverUrl.value));
    els.previewImage.src = url;
    els.previewStatus.textContent = "Loading";
  } catch (error) {
    els.previewStatus.textContent = "Invalid URL";
    setMessage(error.message);
  }
}

function resetView() {
  for (const [id, value] of Object.entries(defaults)) {
    const el = document.getElementById(id);
    el.value = String(value);
    updateOutput(id);
  }
  markDirty();
  sendCurrentParams(true);
}

function initControls() {
  for (const id of controls) {
    const el = document.getElementById(id);
    updateOutput(id);
    el.addEventListener("input", () => {
      updateOutput(id);
      markDirty();
    });
    el.addEventListener("change", () => {
      updateOutput(id);
      markDirty();
      sendCurrentParams(true);
    });
  }
}

els.connectBtn.addEventListener("click", connect);
els.disconnectBtn.addEventListener("click", disconnect);
els.previewToggle.addEventListener("change", updatePreview);
els.refreshPreviewBtn.addEventListener("click", updatePreview);
els.resetBtn.addEventListener("click", resetView);

els.previewImage.addEventListener("load", () => {
  els.previewImage.classList.add("active");
  els.previewPlaceholder.classList.add("hidden");
  els.previewStatus.textContent = "Live";
});

els.previewImage.addEventListener("error", () => {
  els.previewImage.classList.remove("active");
  els.previewPlaceholder.classList.remove("hidden");
  els.previewStatus.textContent = "Unavailable";
});

initControls();
updatePreview();
setInterval(() => sendCurrentParams(false), 33);


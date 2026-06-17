<script>
  import HdmiPreview from "../components/HdmiPreview.svelte";
  import Equation from "../components/Equation.svelte";
  import { setParam, flushNow, loadOverlay, getServerUrl, hardwareValues } from "../lib/connection.js";

  // slider position as a whole-number percentage of its own range
  const pct = (v, lo, hi) => {
    const p = Math.round(((v - lo) / (hi - lo)) * 100);
    const c = Math.max(0, Math.min(100, p));
    return c < 100 ? String(c).padStart(2, "0") : "100";
  };

  let live = false;
  // serverUrl now comes from the shared connection (set via the status pill)
  let loadState = "idle";
  let loadMsg = "";

  // camera defaults match the board's isometric view
  let cam = { yaw: 233, pitch: 67, dist: 1.28 };
  // wave controls (3D overlay runs the same FDTD solver)
  let p = { amplitude: 0.15, phase_step: 0.15, height: 3, speed: 400000, moving: false, vx: 0.0 };
  let magMode = 2;  // 0=|E| 1=|S| 2=Ey 3=Bz
  function onMag() { setParam("mag_mode", magMode); flushNow(); }

  // Mirror live hardware knob values onto the sliders (hardware mode).
  hardwareValues.subscribe((hv) => {
    if (!hv) return;
    if (hv.amplitude !== undefined) p.amplitude = hv.amplitude;
    if (hv.speed !== undefined) p.speed = hv.speed;
    if (hv.yaw !== undefined) cam.yaw = hv.yaw;
    if (hv.pitch !== undefined) cam.pitch = hv.pitch;
    if (hv.dist !== undefined) cam.dist = hv.dist;
    p = p; cam = cam;  // trigger Svelte reactivity
  });


  async function load3D() {
    loadState = "loading"; loadMsg = "Loading 3D terrain…";
    try {
      await loadOverlay(getServerUrl(), "3d");
      loadState = "ready"; loadMsg = "3D terrain running.";
    } catch (e) {
      loadState = "error"; loadMsg = String(e);
    }
  }

  // camera: send all three together so the PS recomputes the full basis
  function sendCam() {
    setParam("yaw", cam.yaw);
    setParam("pitch", cam.pitch);
    setParam("dist", cam.dist);
    flushNow();
  }

  function send(key, value) { setParam(key, value); }
  function onMoving() {
    if (p.moving) { setParam("vx", p.vx); flushNow(); }
    else { setParam("vx", 0); flushNow(); }
  }
  function clearFields() {
    // full reset: restore all defaults, push to board, clear the wave
    p = { amplitude: 0.15, phase_step: 0.15, height: 3, speed: 400000, moving: false, vx: 0.0 };
    cam = { yaw: 233, pitch: 67, dist: 1.28 };
    magMode = 2;
    setParam("amplitude", p.amplitude);
    setParam("phase_step", p.phase_step);
    setParam("height", p.height);
    setParam("speed", p.speed);
    setParam("mag_mode", magMode);
    setParam("vx", 0);
    setParam("yaw", cam.yaw);
    setParam("pitch", cam.pitch);
    setParam("dist", cam.dist);
    setParam("clear", 1);
    flushNow();
  }
  function resetCam() { cam = { yaw: 233, pitch: 67, dist: 1.28 }; sendCam(); }
</script>

<section class="cockpit">
  <!-- LEFT: camera -->
  <aside class="panel controls">
    <h2>3D Camera</h2>
    <button class="load" on:click={load3D} disabled={loadState === "loading"}>
      {loadState === "ready" ? "Reload 3D" : "Load 3D terrain"}
    </button>
    {#if loadMsg}<p class="loadmsg muted">{loadMsg}</p>{/if}

    <label class="ctrl">
      <span>Yaw <b>{pct(cam.yaw,0,360)}%</b></span>
      <input type="range" min="0" max="360" step="1" bind:value={cam.yaw} on:input={sendCam}>
    </label>
    <label class="ctrl">
      <span>Pitch <b>{pct(cam.pitch,2,89)}%</b></span>
      <input type="range" min="2" max="89" step="1" bind:value={cam.pitch} on:input={sendCam}>
    </label>
    <label class="ctrl">
      <span>Distance <b>{pct(cam.dist,0.4,2.0)}%</b></span>
      <input type="range" min="0.4" max="2.0" step="0.02" bind:value={cam.dist} on:input={sendCam}>
    </label>
    <button class="ghost" on:click={resetCam}>⌂ Reset view</button>
  </aside>

  <!-- CENTRE -->
  <div class="stage">
    <div class="stage-head">
      <h2>3D wave terrain</h2>
      <button class="ghost" on:click={() => (live = !live)}>
        {live ? "Stop capture" : "Start capture"}
      </button>
    </div>
    <HdmiPreview {live} />
  </div>

  <!-- RIGHT: wave controls -->
  <aside class="panel side">
    <h2>Wave field</h2>
    <label class="ctrl">
      <span>Amplitude <b>{pct(p.amplitude,0,0.5)}%</b></span>
      <input type="range" min="0" max="0.5" step="0.01" bind:value={p.amplitude} on:input={() => send("amplitude", p.amplitude)}>
    </label>
    <label class="ctrl">
      <span>Frequency <b>{pct(p.phase_step,0.05,0.6)}%</b></span>
      <input type="range" min="0.05" max="0.6" step="0.01" bind:value={p.phase_step} on:input={() => send("phase_step", p.phase_step)}>
    </label>
    <label class="ctrl">
      <span>Relief height <b>{pct(p.height,0,15)}%</b></span>
      <input type="range" min="0" max="15" step="1" bind:value={p.height} on:input={() => send("height", p.height)}>
    </label>
    <label class="ctrl">
      <span>Speed <b>{pct(p.speed,0,600000)}%</b></span>
      <input type="range" min="0" max="600000" step="10000" bind:value={p.speed} on:input={() => send("speed", p.speed)}>
    </label>
    <button class="ghost" on:click={clearFields}>↺ Reset field</button>

    <h2>Moving source</h2>
    <label class="switch">
      <input type="checkbox" bind:checked={p.moving} on:change={onMoving}>
      <span>Enable Doppler</span>
    </label>
    <label class="ctrl">
      <span>Velocity X <b>{pct(p.vx,-0.5,0.5)}%</b></span>
      <input type="range" min="-0.5" max="0.5" step="0.01" bind:value={p.vx} on:input={onMoving} disabled={!p.moving}>
    </label>

    <h2>Display quantity</h2>
    <select bind:value={magMode} on:change={onMag}>
      <option value={2}>Eᵧ (signed wave)</option>
      <option value={0}>|E| (field magnitude)</option>
      <option value={1}>|S| (Poynting / energy flow)</option>
    </select>

    <h2>Governing equation</h2>
    <Equation tex={"\\nabla^2 \\mathbf{E} = \\mu_0 \\varepsilon_0 \\frac{\\partial^2 \\mathbf{E}}{\\partial t^2}"} />
  </aside>
</section>

<style>
  .cockpit { display: grid; grid-template-columns: 300px minmax(0,1fr) 320px; gap: 16px; padding: 16px; align-items: start; }
  .panel { display: grid; gap: 12px; align-content: start; }
  h2 { font-size: 0.95rem; margin-top: 6px; }
  .ctrl { display: grid; gap: 6px; }
  .ctrl span { display: flex; justify-content: space-between; color: var(--muted); font-size: 0.85rem; }
  .ctrl b { color: var(--text); font-variant-numeric: tabular-nums; }
  input[type="range"] { width: 100%; accent-color: var(--accent); }
  .switch { display: flex; align-items: center; gap: 8px; color: var(--muted); font-size: 0.85rem; }
  .load { background: var(--accent); color: #06121a; border: 0; padding: 9px 12px; border-radius: 8px; cursor: pointer; font: inherit; font-weight: 600; }
  .load:disabled { opacity: 0.6; cursor: not-allowed; }
  .loadmsg { font-size: 0.8rem; margin: 0; }
  .ghost { background: transparent; border: 1px solid var(--line); color: var(--text); padding: 8px 12px; border-radius: 8px; cursor: pointer; font: inherit; width: fit-content; }
  .ghost:hover { background: var(--panel); }
  .stage { display: grid; gap: 12px; }
  .stage-head { display: flex; align-items: center; justify-content: space-between; }
  @media (max-width: 1100px) { .cockpit { grid-template-columns: 1fr; } }
</style>

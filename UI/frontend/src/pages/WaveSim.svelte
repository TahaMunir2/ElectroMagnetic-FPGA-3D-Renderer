<script>
  import HdmiPreview from "../components/HdmiPreview.svelte";
  import Equation from "../components/Equation.svelte";
  import { setParam, flushNow, loadOverlay, getServerUrl, hardwareValues } from "../lib/connection.js";
  import { CVD_TYPES, computePalette } from "../lib/palette.js";

  let live = false;
  // serverUrl now comes from the shared connection (set via the status pill)
  let loadState = "idle"; // idle | loading | ready | error
  let loadMsg = "";

  // 2D params (defaults match the board: height 6, speed 300000).
  let p = {
    amplitude: 0.3,
    phase_step: 0.18,
    height: 6,
    speed: 300000,
    cvd: "none",
    vx: 0.0,
    vy: 0.0,
    moving: false,
  };
  let magMode = 2;  // 0=|E| 1=|S| 2=Ey 3=Bz
  function onMag() { setParam("mag_mode", magMode); flushNow(); }

  // slider position as a whole-number percentage of its own range
  const pct = (v, lo, hi) => {
    const q = Math.round(((v - lo) / (hi - lo)) * 100);
    const c = Math.max(0, Math.min(100, q));
    return c < 100 ? String(c).padStart(2, "0") : "100";
  };

  // Mirror live hardware knob values onto the 2D sliders (hardware mode).
  hardwareValues.subscribe((hv) => {
    if (!hv) return;
    if (hv.amplitude !== undefined) p.amplitude = hv.amplitude;
    if (hv.speed !== undefined) p.speed = hv.speed;
    p = p;
  });

  const cvdLabels = {
    none: "None", protanopia: "Protanopia", deuteranopia: "Deuteranopia", tritanopia: "Tritanopia",
  };
  $: palette = computePalette(p.cvd);

  async function load2D() {
    loadState = "loading"; loadMsg = "Loading 2D overlay…";
    try {
      await loadOverlay(getServerUrl(), "2d");
      loadState = "ready"; loadMsg = "2D simulation running.";
    } catch (e) {
      loadState = "error"; loadMsg = String(e);
    }
  }

  function send(key, value) { setParam(key, value); }

  function onCvd() { setParam("cvd_mode", CVD_TYPES.indexOf(p.cvd)); }
  function onMoving() {
    if (p.moving) { setParam("vx", p.vx); setParam("vy", p.vy); flushNow(); }
    else { setParam("vx", 0); setParam("vy", 0); flushNow(); }
  }
  function clearFields() {
    // full reset: restore all defaults, push to board, clear the wave
    p.amplitude = 0.15; p.phase_step = 0.18; p.height = 6; p.speed = 300000;
    p.moving = false; p.vx = 0; p.vy = 0; p.cvd = "none";
    magMode = 2;
    p = p;
    setParam("amplitude", p.amplitude);
    setParam("phase_step", p.phase_step);
    setParam("height", p.height);
    setParam("speed", p.speed);
    setParam("mag_mode", magMode);
    setParam("cvd_mode", 0);
    setParam("vx", 0); setParam("vy", 0);
    setParam("clear", 1);
    flushNow();
  }
</script>

<section class="cockpit">
  <!-- LEFT: controls -->
  <aside class="panel controls">
    <h2>Simulation</h2>
    <button class="load" on:click={load2D} disabled={loadState === "loading"}>
      {loadState === "ready" ? "Reload 2D" : "Load 2D simulation"}
    </button>
    {#if loadMsg}<p class="loadmsg muted">{loadMsg}</p>{/if}

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

    <h2>Moving source (Doppler)</h2>
    <label class="switch">
      <input type="checkbox" bind:checked={p.moving} on:change={onMoving}>
      <span>Enable moving source</span>
    </label>
    <label class="ctrl">
      <span>Velocity X <b>{pct(p.vx,-0.5,0.5)}%</b></span>
      <input type="range" min="-0.5" max="0.5" step="0.01" bind:value={p.vx} on:input={onMoving} disabled={!p.moving}>
    </label>
    <p class="hint muted">Sweep velocity up: rings → Doppler → Mach cone.</p>
  </aside>

  <!-- CENTRE -->
  <div class="stage">
    <div class="stage-head">
      <h2>2D FDTD wave field</h2>
      <button class="ghost" on:click={() => (live = !live)}>
        {live ? "Stop capture" : "Start capture"}
      </button>
    </div>
    <HdmiPreview {live} />
  </div>

  <!-- RIGHT: palette + equation -->
  <aside class="panel side">
    <h2>Colour vision</h2>
    <select bind:value={p.cvd} on:change={onCvd}>
      {#each CVD_TYPES as t}<option value={t}>{cvdLabels[t]}</option>{/each}
    </select>
    <div class="bar">
      {#each palette as [r,g,b]}<div class="sw" style="background: rgb({r},{g},{b})"></div>{/each}
    </div>
    <span class="caption muted">16-band palette, adapted for the selected vision type.</span>

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
  select { background: var(--panel-2); color: var(--text); border: 1px solid var(--line); border-radius: 8px; padding: 7px 8px; width: 100%; }
  .switch { display: flex; align-items: center; gap: 8px; color: var(--muted); font-size: 0.85rem; }
  .load { background: var(--accent); color: #06121a; border: 0; padding: 9px 12px; border-radius: 8px; cursor: pointer; font: inherit; font-weight: 600; }
  .load:disabled { opacity: 0.6; cursor: not-allowed; }
  .loadmsg { font-size: 0.8rem; margin: 0; }
  .ghost { background: transparent; border: 1px solid var(--line); color: var(--text); padding: 8px 12px; border-radius: 8px; cursor: pointer; font: inherit; width: fit-content; }
  .ghost:hover { background: var(--panel); }
  .hint { font-size: 0.8rem; }
  .stage { display: grid; gap: 12px; }
  .stage-head { display: flex; align-items: center; justify-content: space-between; }
  .bar { display: grid; grid-template-columns: repeat(16,1fr); height: 26px; border-radius: 6px; overflow: hidden; }
  .sw { width: 100%; height: 100%; }
  .caption { font-size: 0.78rem; }
  @media (max-width: 1100px) { .cockpit { grid-template-columns: 1fr; } }
</style>

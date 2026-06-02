<script>
  import HdmiPreview from "../components/HdmiPreview.svelte";
  import Equation from "../components/Equation.svelte";
  import { mockReadouts } from "../lib/mockData.js";
  import CameraPanel from "../components/CameraPanel.svelte";
  import { setParam } from "../lib/connection.js";

  let live = false;

  let params = {
    src_x: 32,
    src_y: 32,
    amplitude: 2048,
    frequency: 32,
    material_eps: 1.0,
    pml: true,
    display_mode: 0,
    speed: 4,
  };

  const displayLabels = ["|E| field", "|B| field", "|S| Poynting", "Energy density"];
  let runState = "pause";
  const readouts = mockReadouts();

  function send(key, value) {
    setParam(key, value);
  }
  function onParam(key) {
    return (e) => {
      const v = e.target.type === "checkbox" ? (e.target.checked ? 1 : 0)
              : Number(e.target.value);
      params[key] = e.target.type === "checkbox" ? e.target.checked : v;
      send(key, v);
    };
  }
  function setRun(state) { runState = state; send("run_state", state === "run" ? 1 : 0); }
  function stepOnce() { send("run_state", 2); }
  function reset() { send("run_state", 3); }
</script>

<section class="cockpit">
  <aside class="panel controls">
    <h2>Wave Source</h2>

    <label class="ctrl">
      <span>Source X <b>{params.src_x}</b></span>
      <input type="range" min="0" max="63" bind:value={params.src_x} on:input={onParam("src_x")}>
    </label>
    <label class="ctrl">
      <span>Source Y <b>{params.src_y}</b></span>
      <input type="range" min="0" max="63" bind:value={params.src_y} on:input={onParam("src_y")}>
    </label>
    <label class="ctrl">
      <span>Amplitude <b>{params.amplitude}</b></span>
      <input type="range" min="0" max="4095" bind:value={params.amplitude} on:input={onParam("amplitude")}>
    </label>
    <label class="ctrl">
      <span>Frequency <b>{params.frequency}</b></span>
      <input type="range" min="1" max="256" bind:value={params.frequency} on:input={onParam("frequency")}>
    </label>

    <h2>Medium</h2>
    <label class="ctrl">
      <span>Permittivity &epsilon; <b>{params.material_eps.toFixed(1)}</b></span>
      <input type="range" min="1" max="10" step="0.1" bind:value={params.material_eps} on:input={onParam("material_eps")}>
    </label>
    <label class="switch">
      <input type="checkbox" bind:checked={params.pml} on:change={onParam("pml")}>
      <span>PML absorbing boundary</span>
    </label>

    <h2>Display</h2>
    <label class="ctrl">
      <span>Quantity</span>
      <select bind:value={params.display_mode} on:change={onParam("display_mode")}>
        {#each displayLabels as label, i}
          <option value={i}>{label}</option>
        {/each}
      </select>
    </label>

    <p class="hint muted">Multiple sources &amp; walls — coming with FDTD Deliverable 4.</p>
  </aside>

  <div class="stage">
    <div class="stage-head">
      <h2>{displayLabels[params.display_mode]}</h2>
      <button class="ghost" on:click={() => (live = !live)}>
        {live ? "Stop capture" : "Start capture"}
      </button>
    </div>

    <CameraPanel />
    <HdmiPreview {live} />

    <div class="transport">
      <button class:active={runState === "run"} on:click={() => setRun("run")}>&#9654; Run</button>
      <button class:active={runState === "pause"} on:click={() => setRun("pause")}>&#9208; Pause</button>
      <button on:click={stepOnce}>&#9197; Step</button>
      <button on:click={reset}>&#8634; Reset</button>
      <label class="speed">
        Speed <b>{params.speed}&times;</b>
        <input type="range" min="1" max="16" bind:value={params.speed} on:input={onParam("speed")}>
      </label>
    </div>
  </div>

  <aside class="panel side">
    <h2>Governing equation</h2>
    <Equation tex={"\\nabla^2 \\mathbf{E} = \\mu_0 \\varepsilon_0 \\frac{\\partial^2 \\mathbf{E}}{\\partial t^2}"} />
    <Equation tex={"\\nabla \\times \\mathbf{E} = -\\frac{\\partial \\mathbf{B}}{\\partial t}"} />
    <Equation tex={"\\mathbf{S} = \\frac{1}{\\mu_0}\\,\\mathbf{E} \\times \\mathbf{B}"} />

    <h2>Live readouts</h2>
    <div class="readouts">
      <div class="ro"><span class="muted">Timestep</span><b>{readouts.timestep}</b></div>
      <div class="ro"><span class="muted">FPS</span><b>{readouts.fps}</b></div>
      <div class="ro"><span class="muted">Throughput</span><b>{readouts.throughput} MPix/s</b></div>
      <div class="ro"><span class="muted">CPU baseline</span><b>{readouts.cpuFps} FPS</b></div>
    </div>
  </aside>
</section>

<style>
  .cockpit {
    display: grid;
    grid-template-columns: 300px minmax(0, 1fr) 320px;
    gap: 16px;
    padding: 16px;
    align-items: start;
  }
  .panel { display: grid; gap: 12px; align-content: start; }
  h2 { font-size: 0.95rem; margin-top: 6px; }

  .ctrl { display: grid; gap: 6px; }
  .ctrl span { display: flex; justify-content: space-between; color: var(--muted); font-size: 0.85rem; }
  .ctrl b { color: var(--text); font-variant-numeric: tabular-nums; }
  input[type="range"] { width: 100%; accent-color: var(--accent); }
  select {
    background: var(--panel-2); color: var(--text);
    border: 1px solid var(--line); border-radius: 8px; padding: 7px 8px; width: 100%;
  }
  .switch { display: flex; align-items: center; gap: 8px; color: var(--muted); font-size: 0.85rem; }
  .hint { font-size: 0.8rem; margin-top: 8px; }

  .stage { display: grid; gap: 12px; }
  .stage-head { display: flex; align-items: center; justify-content: space-between; }
  .ghost {
    background: transparent; border: 1px solid var(--line); color: var(--text);
    padding: 7px 12px; border-radius: 8px; cursor: pointer; font: inherit;
  }
  .ghost:hover { background: var(--panel); }

  .transport { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .transport button {
    background: var(--panel); border: 1px solid var(--line); color: var(--text);
    padding: 8px 12px; border-radius: 8px; cursor: pointer; font: inherit;
  }
  .transport button.active { border-color: var(--accent); color: var(--accent); }
  .speed { display: flex; align-items: center; gap: 8px; color: var(--muted); font-size: 0.85rem; margin-left: auto; }
  .speed input { width: 110px; }

  .readouts { display: grid; gap: 8px; }
  .ro {
    display: flex; justify-content: space-between;
    background: var(--panel-2); border: 1px solid var(--line);
    border-radius: 8px; padding: 8px 10px;
  }
  .ro b { font-variant-numeric: tabular-nums; }

  @media (max-width: 1100px) {
    .cockpit { grid-template-columns: 1fr; }
  }
</style>

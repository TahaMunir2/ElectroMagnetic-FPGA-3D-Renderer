<script>
  import HdmiPreview from "../components/HdmiPreview.svelte";
  import Equation from "../components/Equation.svelte";
  import { mockReadouts } from "../lib/mockData.js";
  import CameraPanel from "../components/CameraPanel.svelte";
  import { setParam } from "../lib/connection.js";

  let live = false;

  // Static-mode parameters (Laplace / real electrode measurement).
  let params = {
    pos_x: 16, pos_y: 32,   // positive electrode
    neg_x: 48, neg_y: 32,   // negative electrode
    voltage: 3000,
    probe_x: 32, probe_y: 32,
    sigma: 1.0,
    display_mode: 0,        // 0 = potential V, 1 = |E| field
  };

  const displayLabels = ["Potential V(x,y)", "|E| field"];
  const readouts = mockReadouts();

  function send(key, value) {
    setParam(key, value);
  }
  function onParam(key) {
    return (e) => {
      const v = Number(e.target.value);
      params[key] = v;
      send(key, v);
    };
  }
</script>

<section class="cockpit">
  <aside class="panel controls">
    <h2>Electrodes</h2>

    <label class="ctrl">
      <span>+ Electrode X <b>{params.pos_x}</b></span>
      <input type="range" min="0" max="63" bind:value={params.pos_x} on:input={onParam("pos_x")}>
    </label>
    <label class="ctrl">
      <span>+ Electrode Y <b>{params.pos_y}</b></span>
      <input type="range" min="0" max="63" bind:value={params.pos_y} on:input={onParam("pos_y")}>
    </label>
    <label class="ctrl">
      <span>&minus; Electrode X <b>{params.neg_x}</b></span>
      <input type="range" min="0" max="63" bind:value={params.neg_x} on:input={onParam("neg_x")}>
    </label>
    <label class="ctrl">
      <span>&minus; Electrode Y <b>{params.neg_y}</b></span>
      <input type="range" min="0" max="63" bind:value={params.neg_y} on:input={onParam("neg_y")}>
    </label>
    <label class="ctrl">
      <span>Voltage <b>{params.voltage}</b></span>
      <input type="range" min="0" max="4095" bind:value={params.voltage} on:input={onParam("voltage")}>
    </label>

    <h2>Probe</h2>
    <label class="ctrl">
      <span>Probe X <b>{params.probe_x}</b></span>
      <input type="range" min="0" max="63" bind:value={params.probe_x} on:input={onParam("probe_x")}>
    </label>
    <label class="ctrl">
      <span>Probe Y <b>{params.probe_y}</b></span>
      <input type="range" min="0" max="63" bind:value={params.probe_y} on:input={onParam("probe_y")}>
    </label>

    <h2>Medium</h2>
    <label class="ctrl">
      <span>Sheet conductivity &sigma; <b>{params.sigma.toFixed(1)}</b></span>
      <input type="range" min="0.1" max="10" step="0.1" bind:value={params.sigma} on:input={onParam("sigma")}>
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

    <p class="caption muted">
      Real static field measured from electrodes on a conducting sheet.
      The surface height shows electric potential: the + electrode is a peak,
      the &minus; electrode a valley, and the smooth surface between them is the Laplace solution.
    </p>
  </div>

  <aside class="panel side">
    <h2>Governing equation</h2>
    <Equation tex={"\\nabla^2 V = 0"} />
    <p class="muted note">
      With &part;/&part;t = 0, Maxwell&rsquo;s equations reduce to Laplace&rsquo;s equation
      for the electrostatic potential V.
    </p>

    <h2>Probe reading</h2>
    <div class="readouts">
      <div class="ro"><span class="muted">V at probe</span><b>&mdash;</b></div>
      <div class="ro"><span class="muted">|E| at probe</span><b>&mdash;</b></div>
      <div class="ro"><span class="muted">FPS</span><b>{readouts.fps}</b></div>
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

  .stage { display: grid; gap: 12px; }
  .stage-head { display: flex; align-items: center; justify-content: space-between; }
  .ghost {
    background: transparent; border: 1px solid var(--line); color: var(--text);
    padding: 7px 12px; border-radius: 8px; cursor: pointer; font: inherit;
  }
  .ghost:hover { background: var(--panel); }
  .caption { font-size: 0.85rem; line-height: 1.5; }

  .note { font-size: 0.82rem; line-height: 1.5; }
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

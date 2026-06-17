<script>
  import { setParam, flushNow } from "../lib/connection.js";

  const DEFAULTS = { camera_x: -2867, camera_y: -2867, camera_z: 3686, yaw: 512, pitch: -512 };
  let cam = { ...DEFAULTS };

  function onCam(key) {
    return (e) => {
      cam[key] = Number(e.target.value);
      setParam(key, cam[key]);
    };
  }

  function reset() {
    cam = { ...DEFAULTS };
    for (const [k, v] of Object.entries(cam)) setParam(k, v);
    flushNow();
  }
</script>

<div class="cambar">
  <span class="title">Camera</span>
  <label><span>X <b>{cam.camera_x}</b></span>
    <input type="range" min="-8192" max="8192" bind:value={cam.camera_x} on:input={onCam("camera_x")}></label>
  <label><span>Y <b>{cam.camera_y}</b></span>
    <input type="range" min="-8192" max="8192" bind:value={cam.camera_y} on:input={onCam("camera_y")}></label>
  <label><span>Z <b>{cam.camera_z}</b></span>
    <input type="range" min="-8192" max="8192" bind:value={cam.camera_z} on:input={onCam("camera_z")}></label>
  <label><span>Yaw <b>{cam.yaw}</b></span>
    <input type="range" min="0" max="4095" bind:value={cam.yaw} on:input={onCam("yaw")}></label>
  <label><span>Pitch <b>{cam.pitch}</b></span>
    <input type="range" min="-1024" max="1024" bind:value={cam.pitch} on:input={onCam("pitch")}></label>
  <button class="reset" on:click={reset}>↺ Reset</button>
</div>

<style>
  .cambar {
    display: grid;
    grid-template-columns: auto repeat(5, 1fr) auto;
    align-items: center; gap: 12px;
    background: var(--panel); border: 1px solid var(--line);
    border-radius: var(--radius); padding: 10px 14px;
  }
  .title { font-size: 0.85rem; color: var(--accent); font-weight: 600; }
  label { display: grid; gap: 4px; }
  label span { display: flex; justify-content: space-between; color: var(--muted); font-size: 0.78rem; }
  label b { color: var(--text); font-variant-numeric: tabular-nums; }
  input[type="range"] { width: 100%; accent-color: var(--accent); }
  .reset {
    background: transparent; border: 1px solid var(--line); color: var(--text);
    padding: 7px 12px; border-radius: 8px; cursor: pointer; font: inherit; white-space: nowrap;
  }
  .reset:hover { background: var(--panel-2); }
  @media (max-width: 1100px) { .cambar { grid-template-columns: 1fr; } }
</style>

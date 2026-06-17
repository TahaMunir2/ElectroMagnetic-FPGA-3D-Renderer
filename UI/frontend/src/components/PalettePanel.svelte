<script>
  import { CVD_TYPES, computePalette } from "../lib/palette.js";
  import { setParam } from "../lib/connection.js";

  let cvd = "none";
  $: palette = computePalette(cvd);

  const labels = {
    none: "None", protanopia: "Protanopia (red-weak)",
    deuteranopia: "Deuteranopia (green-weak)", tritanopia: "Tritanopia (blue-weak)",
  };

  function onChange() {
    // For now just send the choice; the PS will compute + write 16 regs later.
    setParam("cvd_mode", CVD_TYPES.indexOf(cvd));
  }
</script>

<div class="palpanel">
  <div class="row">
    <span class="title">Colour vision</span>
    <select bind:value={cvd} on:change={onChange}>
      {#each CVD_TYPES as t}<option value={t}>{labels[t]}</option>{/each}
    </select>
  </div>

  <div class="bar">
    {#each palette as [r,g,b], i}
      <div class="swatch" style="background: rgb({r},{g},{b})" title={`band ${i}`}></div>
    {/each}
  </div>
  <span class="caption muted">16-band contour palette, adapted for the selected vision type.</span>
</div>

<style>
  .palpanel {
    display: grid; gap: 10px;
    background: var(--panel); border: 1px solid var(--line);
    border-radius: var(--radius); padding: 12px 14px;
  }
  .row { display: flex; align-items: center; gap: 12px; justify-content: space-between; }
  .title { font-size: 0.85rem; color: var(--accent); font-weight: 600; }
  select {
    background: var(--panel-2); color: var(--text);
    border: 1px solid var(--line); border-radius: 8px; padding: 6px 8px;
  }
  .bar { display: grid; grid-template-columns: repeat(16, 1fr); height: 28px; border-radius: 6px; overflow: hidden; }
  .swatch { width: 100%; height: 100%; }
  .caption { font-size: 0.78rem; }
</style>

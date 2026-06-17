<script>
  import { onMount, onDestroy } from "svelte";

  // When false, shows the "awaiting HDMI" placeholder (current state, no capture card yet).
  // When true, tries to open a video capture device and paint it into the canvas.
  export let live = false;

  let videoEl;        // hidden <video> that receives the capture stream
  let canvasEl;       // visible 4:3 canvas we paint into
  let stream = null;
  let rafId = null;
  let error = "";
  let devices = [];
  let selectedId = "";

  // List available video inputs (webcam now, capture card on demo day).
  async function listDevices() {
    try {
      const all = await navigator.mediaDevices.enumerateDevices();
      devices = all.filter((d) => d.kind === "videoinput");
      if (devices.length && !selectedId) selectedId = devices[0].deviceId;
    } catch (e) {
      error = "Cannot list capture devices.";
    }
  }

  async function start() {
    error = "";
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: selectedId ? { deviceId: { exact: selectedId } } : true,
        audio: false,
      });
      videoEl.srcObject = stream;
      await videoEl.play();
      await listDevices(); // labels become available after permission granted
      drawLoop();
    } catch (e) {
      error = "No capture device / permission denied.";
    }
  }

  function stop() {
    if (rafId) cancelAnimationFrame(rafId);
    rafId = null;
    if (stream) stream.getTracks().forEach((t) => t.stop());
    stream = null;
  }

  // Paint the video onto the canvas every frame, letterboxed to keep aspect.
  function drawLoop() {
    const ctx = canvasEl.getContext("2d");
    const render = () => {
      if (videoEl.videoWidth) {
        const cw = canvasEl.width, ch = canvasEl.height;
        const vw = videoEl.videoWidth, vh = videoEl.videoHeight;
        const scale = Math.min(cw / vw, ch / vh);
        const dw = vw * scale, dh = vh * scale;
        ctx.fillStyle = "#000";
        ctx.fillRect(0, 0, cw, ch);
        ctx.drawImage(videoEl, (cw - dw) / 2, (ch - dh) / 2, dw, dh);
      }
      rafId = requestAnimationFrame(render);
    };
    render();
  }

  // React to the `live` prop flipping.
  $: if (videoEl && canvasEl) {
    if (live && !stream) start();
    if (!live && stream) stop();
  }

  onMount(() => { canvasEl.width = 640; canvasEl.height = 480; });
  onDestroy(stop);
</script>

<div class="preview">
  <div class="frame">
    <!-- hidden source; canvas is what the user sees -->
    <video bind:this={videoEl} playsinline muted></video>
    <canvas bind:this={canvasEl} class:hidden={!live}></canvas>

    {#if !live}
      <div class="placeholder">
        <strong>Awaiting HDMI feed</strong>
        <span class="muted">PL render → capture card → here</span>
      </div>
    {/if}
  </div>

  <div class="controls">
    {#if live && devices.length > 1}
      <select bind:value={selectedId} on:change={() => { stop(); start(); }}>
        {#each devices as d}
          <option value={d.deviceId}>{d.label || "Camera"}</option>
        {/each}
      </select>
    {/if}
    {#if error}<span class="err">{error}</span>{/if}
  </div>
</div>

<style>
  .preview { display: grid; gap: 8px; }
  .frame {
    position: relative;
    width: 100%;
    aspect-ratio: 4 / 3;       /* locks 640x480 shape regardless of width */
    background: #000;
    border: 1px solid var(--line);
    border-radius: var(--radius);
    overflow: hidden;
  }
  video { display: none; }
  canvas { width: 100%; height: 100%; display: block; }
  canvas.hidden { display: none; }
  .placeholder {
    position: absolute; inset: 0;
    display: grid; place-items: center; gap: 6px;
    text-align: center;
  }
  .controls { display: flex; align-items: center; gap: 10px; min-height: 20px; }
  select {
    background: var(--panel-2); color: var(--text);
    border: 1px solid var(--line); border-radius: 8px; padding: 6px 8px;
  }
  .err { color: var(--danger); font-size: 0.85rem; }
</style>
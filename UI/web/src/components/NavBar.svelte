<script>
  import { status, lastMessage, connect, disconnect, setInputSource, getServerUrl } from "../lib/connection.js";

  export let current = "wave";
  export let setPage = () => {};

  const links = [
    { id: "wave",    label: "Wave Simulation" },
    { id: "terrain", label: "3D Terrain" },
    { id: "physics", label: "The Physics" },
    { id: "explorer",label: "Field Explorer" },
    { id: "about",   label: "About" },
  ];

  const statusText = {
    disconnected: "Disconnected",
    connecting: "Connecting",
    connected: "Connected",
    error: "Error",
  };

  let serverUrl = "http://127.0.0.1:8000";
  let showConn = false;
  let inputSource = "ui";  // "ui" | "hardware"
  let srcBusy = false;

  async function toggleSource() {
    const next = inputSource === "ui" ? "hardware" : "ui";
    srcBusy = true;
    try {
      const r = await setInputSource(getServerUrl(), next);
      inputSource = r.input_source || next;
    } catch (e) {
      // leave as-is on failure
    } finally {
      srcBusy = false;
    }
  }
</script>

<nav>
  <div class="brand">
    <span class="mark"></span>
    <strong>EM Visualiser</strong>
  </div>

  <div class="links">
    {#each links as link}
      <button
        class:active={current === link.id}
        on:click={() => setPage(link.id)}
      >{link.label}</button>
    {/each}
  </div>

  <button class="srctoggle {inputSource}" on:click={toggleSource} disabled={srcBusy} title="Switch control between UI sliders and physical knobs/panel">
    <span class="srcdot"></span>
    {inputSource === "hardware" ? "Hardware" : "UI"} control
  </button>

  <div class="conn">
    <button class="pill" on:click={() => (showConn = !showConn)}>
      <span class="dot {$status}"></span>
      <span class="muted">{statusText[$status]}</span>
    </button>

    {#if showConn}
      <div class="popover panel">
        <label class="field">
          <span class="muted">Server URL</span>
          <input bind:value={serverUrl} spellcheck="false" />
        </label>
        <div class="row">
          <button class="go" on:click={() => connect(serverUrl)}>Connect</button>
          <button class="ghost" on:click={disconnect}>Disconnect</button>
        </div>
        <p class="msg muted">{$lastMessage}</p>
      </div>
    {/if}
  </div>
</nav>

<style>
  nav {
    display: flex; align-items: center; justify-content: space-between;
    gap: 16px; padding: 12px 20px;
    background: var(--panel-2); border-bottom: 1px solid var(--line);
    position: sticky; top: 0; z-index: 10;
  }
  .brand { display: flex; align-items: center; gap: 10px; }
  .mark { width: 22px; height: 22px; border-radius: 6px;
    background: linear-gradient(135deg, var(--accent), var(--accent-2)); }
  .links { display: flex; gap: 6px; flex-wrap: wrap; }
  .links button {
    background: transparent; border: 1px solid transparent; color: var(--muted);
    padding: 7px 12px; border-radius: 8px; cursor: pointer; font: inherit;
  }
  .links button:hover { color: var(--text); }
  .links button.active { color: var(--text); background: var(--panel); border-color: var(--line); }

  .conn { position: relative; }
  .pill {
    display: flex; align-items: center; gap: 8px;
    background: transparent; border: 1px solid var(--line);
    border-radius: 999px; padding: 6px 12px; cursor: pointer; font: inherit;
  }
  .dot { width: 10px; height: 10px; border-radius: 50%; background: var(--muted); }
  .dot.connected { background: var(--ok); }
  .dot.connecting { background: var(--warn); }
  .dot.error, .dot.disconnected { background: var(--danger); }

  .popover {
    position: absolute; right: 0; top: 44px; width: 280px;
    display: grid; gap: 10px; z-index: 20;
  }
  .field { display: grid; gap: 6px; }
  .field input {
    background: var(--panel-2); color: var(--text);
    border: 1px solid var(--line); border-radius: 8px; padding: 8px 10px;
  }
  .row { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
  .go { background: var(--accent); color: #06121a; border: 0;
    padding: 8px; border-radius: 8px; cursor: pointer; font: inherit; }
  .ghost { background: transparent; border: 1px solid var(--line); color: var(--text);
    padding: 8px; border-radius: 8px; cursor: pointer; font: inherit; }
  .msg { font-size: 0.8rem; margin: 0; }

  .srctoggle { display: flex; align-items: center; gap: 7px; background: var(--panel-2); color: var(--text); border: 1px solid var(--line); border-radius: 999px; padding: 6px 12px; cursor: pointer; font: inherit; font-size: 0.85rem; margin-right: 10px; }
  .srctoggle:hover { background: var(--panel); }
  .srctoggle:disabled { opacity: 0.6; cursor: wait; }
  .srctoggle .srcdot { width: 8px; height: 8px; border-radius: 50%; background: var(--accent); }
  .srctoggle.hardware { border-color: var(--accent); }
  .srctoggle.hardware .srcdot { background: #ff9f43; box-shadow: 0 0 6px #ff9f43; }
</style>

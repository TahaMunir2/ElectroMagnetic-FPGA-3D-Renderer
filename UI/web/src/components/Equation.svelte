<script>
  import katex from "katex";
  import "katex/dist/katex.min.css";
  export let tex = "";
  let el;
  $: if (el) katex.render(tex, el, { throwOnError: false, displayMode: true });
</script>

<div class="eq" bind:this={el}></div>

<style>
  .eq {
    background: var(--panel-2);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 12px;
    overflow-x: auto;
    color: var(--text);
  }
</style>

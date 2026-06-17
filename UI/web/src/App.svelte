<script>
  import "./lib/theme.css";
  import NavBar from "./components/NavBar.svelte";
  import WaveSim from "./pages/WaveSim.svelte";
  import Terrain from "./pages/Terrain.svelte";
  import Physics from "./pages/Physics.svelte";
  import Explorer from "./pages/Explorer.svelte";
  import About from "./pages/About.svelte";

  let page = "wave";
  const setPage = (id) => (page = id);

  const pages = { wave: WaveSim, terrain: Terrain, physics: Physics, explorer: Explorer, about: About };
  $: Current = pages[page];
</script>

<NavBar current={page} {setPage} />
<main><svelte:component this={Current} /></main>

<style>
  main { max-width: 1400px; margin: 0 auto; }
</style>

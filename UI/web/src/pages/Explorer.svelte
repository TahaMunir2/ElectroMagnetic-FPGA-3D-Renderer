<script>
  import Equation from "../components/Equation.svelte";

  const phenomena = [
    {
      title: "Reflection & Diffraction",
      tex: "\\theta_i = \\theta_r",
      body: "A wave hitting a wall reflects; passing an edge or slit, it bends and spreads. Both fall straight out of the FDTD update with a boundary in the grid.",
    },
    {
      title: "Refraction at a dielectric",
      tex: "n_1 \\sin\\theta_1 = n_2 \\sin\\theta_2",
      body: "Raise permittivity in a region and waves slow down and bend at the interface. Snell's law emerges from the change in wave speed c = 1/\\sqrt{\\mu_0 \\varepsilon}.",
    },
    {
      title: "Standing waves",
      tex: "E(x,t) = 2A\\sin(kx)\\cos(\\omega t)",
      body: "Two opposing sources interfere into fixed nodes and antinodes \u2014 a standing wave. Watch the pattern lock in place rather than travel.",
    },
    {
      title: "Energy density",
      tex: "u = \\tfrac{1}{2}\\varepsilon_0 E^2 + \\tfrac{1}{2\\mu_0} B^2",
      body: "Stored energy in the field. Switch the display quantity to see where energy concentrates as the wave evolves.",
    },
    {
      title: "Near field vs far field",
      tex: "S = \\frac{1}{\\mu_0}\\,\\mathbf{E}\\times\\mathbf{B}",
      body: "Close to a source the field is complex and reactive; far away it settles into clean radiating wavefronts carrying energy outward via the Poynting vector.",
    },
  ];
</script>

<section class="page">
  <header>
    <h1>Field Explorer</h1>
    <p class="muted">Classic electromagnetic phenomena you can reproduce in Wave Simulation mode.</p>
  </header>

  <div class="grid">
    {#each phenomena as p}
      <article class="panel card">
        <h2>{p.title}</h2>
        <Equation tex={p.tex} />
        <p class="muted">{p.body}</p>
      </article>
    {/each}
  </div>
</section>

<style>
  .page { padding: 24px; display: grid; gap: 20px; max-width: 1100px; margin: 0 auto; }
  header { display: grid; gap: 6px; }
  h1 { font-size: 1.6rem; }
  h2 { font-size: 1.05rem; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .card { display: grid; gap: 10px; align-content: start; }
  .card p { line-height: 1.55; font-size: 0.9rem; }
  @media (max-width: 900px) { .grid { grid-template-columns: 1fr; } }
</style>

<section class="page">
  <header>
    <h1>About</h1>
    <p class="muted">A real-time 3D simulator for static and dynamic electromagnetic fields.</p>
  </header>

  <div class="panel block">
    <h2>The idea</h2>
    <p class="muted">
      Maxwell&rsquo;s equations describe everything electromagnetic, but their quantities
      are invisible and abstract. This system makes them visible: a PYNQ-Z1 FPGA solves the
      fields in real time and renders them as a 3D surface over HDMI, controlled live from
      this interface.
    </p>
  </div>

  <div class="two">
    <div class="panel block">
      <h2>Two modes</h2>
      <p class="muted">
        <b>Static Field</b> &mdash; a real electrostatic potential measured from electrodes
        on a conducting sheet (Laplace).<br><br>
        <b>Wave Simulation</b> &mdash; live electromagnetic waves solved on a 2D Yee grid
        with FDTD, with sources, materials and absorbing boundaries.
      </p>
    </div>

    <div class="panel block">
      <h2>Pipeline</h2>
      <p class="muted">
        Analog inputs (electrodes &amp; probes) &rarr; FDTD solver on the FPGA &rarr;
        3D ray-marching renderer &rarr; HDMI display. This UI sets parameters over the
        network and mirrors the HDMI output via a capture device.
      </p>
    </div>
  </div>

  <div class="panel block">
    <h2>Team</h2>
    <p class="muted">
      Cyril, Marzouk, Mingze, Run, Taha and Yi &mdash; Imperial College London,
      EE2 Mathematics Accelerator project.
    </p>
  </div>
</section>

<style>
  .page { padding: 24px; display: grid; gap: 20px; max-width: 1100px; margin: 0 auto; }
  header { display: grid; gap: 6px; }
  h1 { font-size: 1.6rem; }
  h2 { font-size: 1.05rem; margin-bottom: 4px; }
  .block { display: grid; gap: 10px; }
  .block p { line-height: 1.6; }
  .two { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
  @media (max-width: 900px) { .two { grid-template-columns: 1fr; } }
</style>

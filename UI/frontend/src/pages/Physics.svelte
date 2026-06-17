<script>
  import Equation from "../components/Equation.svelte";
</script>

<section class="page">
  <header>
    <h1>The Physics</h1>
    <p class="muted">Everything this system shows comes from four equations.</p>
  </header>

  <div class="panel block">
    <h2>Maxwell&rsquo;s equations</h2>
    <Equation tex={"\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\varepsilon_0}"} />
    <Equation tex={"\\nabla \\cdot \\mathbf{B} = 0"} />
    <Equation tex={"\\nabla \\times \\mathbf{E} = -\\frac{\\partial \\mathbf{B}}{\\partial t}"} />
    <Equation tex={"\\nabla \\times \\mathbf{B} = \\mu_0 \\mathbf{J} + \\mu_0 \\varepsilon_0 \\frac{\\partial \\mathbf{E}}{\\partial t}"} />
    <p class="muted note">
      These describe every electric and magnetic field &mdash; but the quantities are invisible.
      The two modes below make them visible in 3D.
    </p>
  </div>

  <div class="two">
    <div class="panel block">
      <h2>Static &mdash; &part;/&part;t = 0</h2>
      <p class="muted">
        When nothing changes in time, the time derivatives vanish and Maxwell&rsquo;s
        equations collapse to Laplace&rsquo;s equation for the electrostatic potential:
      </p>
      <Equation tex={"\\nabla^2 V = 0"} />
      <p class="muted note">
        This is <b>Static Field</b> mode: a real potential measured from electrodes on a
        conducting sheet. The 3D surface is V(x,y).
      </p>
    </div>

    <div class="panel block">
      <h2>Dynamic &mdash; &part;/&part;t &ne; 0</h2>
      <p class="muted">
        Keep the time derivatives and the curl equations feed each other &mdash;
        &nabla;&times;E updates B, &nabla;&times;B updates E &mdash; and a wave emerges:
      </p>
      <Equation tex={"\\nabla^2 \\mathbf{E} = \\mu_0 \\varepsilon_0 \\frac{\\partial^2 \\mathbf{E}}{\\partial t^2}"} />
      <p class="muted note">
        This is <b>Wave Simulation</b> mode, solved directly on a 2D grid via FDTD.
        We also derive the Poynting vector for energy flow:
      </p>
      <Equation tex={"\\mathbf{S} = \\frac{1}{\\mu_0}\\,\\mathbf{E} \\times \\mathbf{B}"} />
    </div>
  </div>
</section>

<style>
  .page { padding: 24px; display: grid; gap: 20px; max-width: 1100px; margin: 0 auto; }
  header { display: grid; gap: 6px; }
  h1 { font-size: 1.6rem; }
  h2 { font-size: 1.05rem; margin-bottom: 4px; }
  .block { display: grid; gap: 12px; }
  .two { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
  .note { line-height: 1.55; font-size: 0.9rem; }
  @media (max-width: 900px) { .two { grid-template-columns: 1fr; } }
</style>

# MVP2 Vivado Integration

The active block design is `mvp2_ftdt_bd`.

Current block-design structure:

- `cordic_0`: Xilinx CORDIC IP.
- `cordic_source_adapter_0`: converts sample requests into CORDIC phase input
  and Q3.13 source samples.
- `fdtd_solver_bd_adapter_0`: wraps Taha's 2D FDTD solver and maps its logical
  field-memory ports onto the physical BRAM IPs.
- `ey_bram`, `ex_bram`, `bz_bram`: physical true-dual-port field memories.
- `s_mag_bram`: reserved for the later `|S|`/`|E|` rendering pipeline.

The solver adapter currently uses BRAM port-B muxing for adjacent read/write
sharing. It is intentionally left as an RTL/module-ref style integration rather
than a packaged custom IP because PML, `|S|`, and timing-pipeline changes are
still expected to alter the interface.

Known checkpoint status:

- Implementation routes and preserves the solver BRAM structure.
- 100 MHz timing does not yet close; solver/address datapath pipelining is the
  next hardware step.

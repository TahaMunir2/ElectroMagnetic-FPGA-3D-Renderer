# FSM and Top-Level Module

## Overview

Finite State Machine (FSM) and top-level module to orchestrate the 1D FDTD solver, integrating:
- BRAM module
- CORDIC Input Generator
- FDTD Solver
- Control and synchronization logic

## State Machine

```
States:
  - IDLE: Waiting for start command
  - INIT: Initialize BRAM and state
  - SOURCE_GEN: Generate CORDIC source wave
  - SOLVE: Execute FDTD solver iterations
  - READ_OUT: Output results
  - DONE: Simulation complete
```

## Module Hierarchy

```
top_fdtd_solver
├── bram_module (Yi)
├── cordic_generator (Yi)
├── fdtd_solver (Taha)
├── fsm_controller
└── output_interface
```

## Implementation Status

- [ ] FSM state diagram design
- [ ] Module interconnection specification
- [ ] Control signal definitions
- [ ] Testbench development
- [ ] Simulation and verification
- [ ] Timing analysis and closure

## Next Steps

1. Complete individual modules
2. Define precise control signals between modules
3. Implement FSM logic
4. Create comprehensive testbenches
5. Integrate and verify on target FPGA

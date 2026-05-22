# BRAM Module

**Owner**: Yi

## Overview

Block RAM (BRAM) module for storing field values (Ey and Bz) in the 1D FDTD solver.

## Specifications

- Dual-port RAM configuration
- 64 cells for Ey component
- 64 cells for Bz component
- Q3.13 fixed-point precision (16-bit words)
- Synchronous read/write operations

## Interface

```
Inputs:
  - clk: Clock signal
  - rst: Reset signal
  - we: Write enable
  - addr: Memory address (6-bit for 64 addresses)
  - din: Data input (16-bit Q3.13)
  - ey_addr: Ey port address
  - bz_addr: Bz port address

Outputs:
  - ey_dout: Ey data output (16-bit Q3.13)
  - bz_dout: Bz data output (16-bit Q3.13)
```

## Implementation Status

- [x] Design specification complete
- [x] Verilog implementation
- [x] Simulation tests
- [ ] Synthesis and place & route
- [ ] Integration with FDTD solver

## Notes

- The current implementation is portable inferred RAM with a Vivado `ram_style = "block"` hint.
- Runtime reset clears output registers; memory contents are initialized to zero for simulation/synthesis initialization. Use the system INIT phase for runtime memory clearing if needed.
- Read/write behavior is synchronous and write-first for same-cycle writes.

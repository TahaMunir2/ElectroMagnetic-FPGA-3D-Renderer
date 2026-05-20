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

- [ ] Design specification complete
- [ ] Verilog/VHDL implementation
- [ ] Simulation tests
- [ ] Synthesis and place & route
- [ ] Integration with FDTD solver

## Notes

- Consider using Xilinx IP core for optimal utilization on target FPGA
- Implement initialization routine for field reset

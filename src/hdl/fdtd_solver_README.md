# FDTD Solver Module

**Owner**: Taha

## Overview

Core FDTD (Finite-Difference Time-Domain) solver implementing the 1D electromagnetic field update equations.

## Specifications

- 1D field components: Ey (electric field) and Bz (magnetic field)
- 64-cell grid for each component
- Q3.13 fixed-point arithmetic
- Time-stepping FDTD algorithm
- Hard source excitation

## Algorithm

The update equations for 1D FDTD:
```
Ey(n+1, k) = Ey(n, k) + C_e * (Bz(n, k+1) - Bz(n, k))
Bz(n+1, k) = Bz(n, k) + C_m * (Ey(n, k) - Ey(n, k-1))
```

Where:
- C_e and C_m are FDTD coefficients
- n represents time step
- k represents spatial position

## Interface

```
Inputs:
  - clk: Clock signal
  - rst: Reset signal
  - source_in: Hard source input (16-bit Q3.13)
  - source_valid: Input valid signal

Outputs:
  - ey_out: Ey field values (array of 64 x 16-bit)
  - bz_out: Bz field values (array of 64 x 16-bit)
  - out_valid: Output valid signal
```

## Implementation Status

- [ ] Algorithm verification with Python reference
- [ ] Verilog/VHDL implementation
- [ ] Fixed-point arithmetic verification
- [ ] Simulation with reference inputs
- [ ] Boundary condition implementation
- [ ] Integration with BRAM and source

## Notes

- Use synchronous design for FPGA implementation
- Implement fixed-point multiply and add operations carefully
- Boundary cells (k=0 and k=63) should be zeroed
- Pipeline stages may be necessary for timing closure

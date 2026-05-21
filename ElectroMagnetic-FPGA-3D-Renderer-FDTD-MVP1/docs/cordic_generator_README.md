# CORDIC Input Generator

**Owner**: Yi

## Overview

CORDIC (COordinate Rotation DIgital Computer) engine wrapper for generating sine waves as hard source input to the FDTD solver.

## Specifications

- Uses Xilinx CORDIC IP for sine/cosine generation
- Q3.13 fixed-point output precision
- Configurable frequency and amplitude
- Real-time waveform generation

## Interface

```
Inputs:
  - clk: Clock signal
  - rst: Reset signal
  - phase: Phase input for CORDIC (16-bit angle)
  - valid_in: Input valid signal

Outputs:
  - sin_out: Sine output (16-bit Q3.13)
  - cos_out: Cosine output (16-bit Q3.13)
  - valid_out: Output valid signal
```

## Implementation Status

- [x] Vivado CORDIC IP instantiation point
- [x] Phase accumulator design
- [x] Fixed-point output formatting for Icarus behavioral model
- [x] Simulation verification
- [ ] Integration with FDTD solver

## Notes

- Define `VIVADO_CORDIC_IP` in Vivado after generating a CORDIC IP named `cordic_0`.
- Configure the IP for 16-bit phase input and 16-bit sine/cosine output packed as `{sin, cos}` in `m_axis_dout_tdata`.
- Without `VIVADO_CORDIC_IP`, the module uses a behavioral `$sin/$cos` model for Icarus tests only.

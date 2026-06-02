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

- [ ] CORDIC IP core instantiation
- [ ] Phase accumulator design
- [ ] Fixed-point output formatting
- [ ] Simulation verification
- [ ] Integration with FDTD solver

## Notes

- Reference Xilinx CORDIC IP documentation for configuration
- Consider pipeline depth for timing requirements
- Implement phase accumulator for frequency control

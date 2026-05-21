# MVP Development Guide

This document outlines the first Minimum Viable Product (MVP) for the 1D FDTD electromagnetic solver.

## Overview

The MVP implements a 1D Finite-Difference Time-Domain (FDTD) electromagnetic solver targeting FPGA hardware.

### Key Specifications

| Parameter | Value |
|-----------|-------|
| Field Components | 1D Ey and Bz |
| Precision | Q3.13 fixed-point (16-bit) |
| Grid Size | 64 cells per component |
| Source Type | Hard source (CORDIC sine wave) |
| Boundary Conditions | Zeroed (causing reflections) |

## Module Breakdown

### 1. BRAM Module (Yi)
**Purpose**: Dual-port memory for storing field values

- 64-cell storage for Ey
- 64-cell storage for Bz
- Q3.13 fixed-point values
- Synchronous dual-port configuration

**Deliverables**:
- [ ] Verilog/VHDL implementation
- [ ] Simulation testbench
- [ ] Synthesis verified

**References**: See [bram_module_README.md](bram_module_README.md)

---

### 2. CORDIC Input Generator (Yi)
**Purpose**: Generate sine wave excitation using CORDIC IP

- Uses Xilinx CORDIC IP core
- Generates Q3.13 fixed-point outputs
- Phase accumulator for frequency control

**Deliverables**:
- [ ] IP core instantiation
- [ ] Phase accumulator implementation
- [ ] Output formatting in Q3.13
- [ ] Simulation with reference sine wave

**References**: See [cordic_generator_README.md](cordic_generator_README.md)

---

### 3. FDTD Solver (Taha)
**Purpose**: Core algorithm implementing field updates

Implements the update equations:
```
Ey(n+1, k) = Ey(n, k) + C_e * (Bz(n, k+1) - Bz(n, k))
Bz(n+1, k) = Bz(n, k) + C_m * (Ey(n, k) - Ey(n, k-1))
```

**Deliverables**:
- [ ] Fixed-point arithmetic operations
- [ ] Update equation implementation
- [ ] Boundary condition logic
- [ ] Verilog/VHDL implementation

**References**: See [fdtd_solver_README.md](fdtd_solver_README.md)

---

### 4. FSM and Top-Level Module
**Purpose**: Orchestrate module interactions

State diagram:
```
IDLE → INIT → SOURCE_GEN → SOLVE → READ_OUT → DONE
```

**Deliverables**:
- [ ] FSM state machine design
- [ ] Module interconnection
- [ ] Control signal definitions
- [ ] Top-level integration testbench

**References**: See [fsm_toplevel_README.md](fsm_toplevel_README.md)

---

### 5. Python Reference Implementation
**Purpose**: Verify algorithm correctness before hardware

**Deliverables**:
- [ ] Q3.13 fixed-point arithmetic
- [ ] 1D FDTD algorithm in Python
- [ ] Source signal generation
- [ ] Verification test cases

**File**: [fdtd_reference.py](../python/fdtd_reference.py)

---

## Timeline

**Target**: Complete all modules with FSM integration

### Phase 1: Individual Modules
- BRAM implementation and verification
- CORDIC generator instantiation
- FDTD solver implementation
- Python reference complete

### Phase 2: Integration
- FSM design and implementation
- Top-level module creation
- Module interconnection verification
- Full system simulation

### Phase 3: FPGA Deployment
- Synthesis and place & route
- Timing analysis
- Board deployment and validation

---

## Getting Started

1. **Review Specifications**: Read [1d_fdtd_reference.md](1d_fdtd_reference.md)
2. **Run Python Reference**: Execute `src/python/fdtd_reference.py` to understand algorithm behavior
3. **Module Development**: Each module owner should follow their corresponding README
4. **Integration**: Coordinate FSM and top-level module development with module owners

---

## Testing Strategy

- **Unit Tests**: Test each module independently
- **Integration Tests**: Verify module interactions
- **System Tests**: End-to-end FDTD simulation validation
- **Regression Tests**: Compare against Python reference implementation

---

## Resources

- Xilinx CORDIC IP Documentation
- FDTD Theory References
- Fixed-Point Arithmetic Guidelines
- FPGA Design Best Practices

---

**Last Updated**: May 20, 2026

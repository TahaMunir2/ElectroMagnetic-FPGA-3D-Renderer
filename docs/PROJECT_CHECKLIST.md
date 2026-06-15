# Project Checklist

## MVP Development Checklist

### BRAM Module (Yi)

- [x] **Design Phase**
  - [x] Memory architecture specification
  - [x] Address decoding scheme
  - [x] Data format documentation

- [x] **Implementation**
  - [x] Verilog/VHDL code complete
  - [x] Dual-port configuration tested
  - [x] Q3.13 data format verified

- [ ] **Verification**
  - [x] Testbench created
  - [x] Read/write operations tested
  - [x] Initial conditions verified
  - [ ] Synthesis successful

- [ ] **Integration**
  - [ ] Interface signals match specification
  - [ ] Timing requirements met
  - [ ] Ready for integration

### CORDIC Input Generator (Yi)

- [ ] **Design Phase**
  - [x] IP core selection complete
  - [x] Phase accumulator design
  - [x] Frequency calculation method

- [ ] **Implementation**
  - [ ] IP instantiated
  - [x] Phase accumulator coded
  - [x] Output formatting in Q3.13

- [ ] **Verification**
  - [x] Sine wave output validated
  - [x] Fixed-point precision verified
  - [x] Frequency accuracy checked
  - [x] Testbench passed

- [ ] **Integration**
  - [ ] Output interface standardized
  - [ ] Timing synchronized
  - [ ] Ready for FDTD solver

### FDTD Solver (Taha)

- [ ] **Algorithm Design**
  - [ ] FDTD equations documented
  - [ ] Coefficient calculation method
  - [ ] Boundary condition strategy

- [ ] **Fixed-Point Arithmetic**
  - [ ] Q3.13 multiply operation
  - [ ] Q3.13 add operation
  - [ ] Saturation handling
  - [ ] Accuracy verified vs float

- [ ] **Implementation**
  - [ ] Update equations coded
  - [ ] Field array management
  - [ ] Boundary logic implemented

- [ ] **Verification**
  - [ ] Compare against Python reference
  - [ ] Field stability verified
  - [ ] Edge cases tested
  - [ ] Testbench comprehensive

- [ ] **Integration**
  - [ ] BRAM interface correct
  - [ ] Source signal integration
  - [ ] Output format standardized

### FSM and Top-Level Module

- [ ] **Design Phase**
  - [ ] State diagram complete
  - [ ] Module interconnection schematic
  - [ ] Control signal specification
  - [ ] Data flow documented

- [ ] **Implementation**
  - [ ] FSM state machine coded
  - [ ] Module instantiation
  - [ ] Signal routing verified
  - [ ] Clock/reset distribution

- [ ] **Verification**
  - [ ] State transitions tested
  - [ ] Module coordination verified
  - [ ] Full system simulation
  - [ ] Timing closure analysis

- [ ] **Documentation**
  - [ ] Architecture documented
  - [ ] Control flow diagrams
  - [ ] Interface specifications
  - [ ] Integration guide

### Python Reference Implementation

- [ ] **Core Algorithm**
  - [ ] Q3.13 fixed-point conversion
  - [ ] FDTD update equations
  - [ ] Field initialization

- [ ] **Source Generation**
  - [ ] Sine wave generator
  - [ ] Hard source placement
  - [ ] Amplitude and frequency control

- [ ] **Verification**
  - [ ] Boundary condition testing
  - [ ] Field evolution analysis
  - [ ] Numerical stability
  - [ ] Physical reasonableness

- [ ] **Documentation**
  - [ ] Code comments complete
  - [ ] Usage examples
  - [ ] Parameter documentation
  - [ ] Output format specification

### System Integration

- [ ] **Full System Tests**
  - [ ] All modules instantiated
  - [ ] Testbenches comprehensive
  - [ ] Simulation results match reference
  - [ ] Performance metrics recorded

- [ ] **Documentation**
  - [ ] Architecture overview
  - [ ] Module interface specifications
  - [ ] Testing procedures
  - [ ] Troubleshooting guide

- [ ] **Deployment Ready**
  - [ ] Synthesis successful
  - [ ] Place & route completed
  - [ ] Timing constraints met
  - [ ] Ready for board testing

---

**Project Lead**: TBD
**Status**: In Progress
**Last Updated**: May 20, 2026

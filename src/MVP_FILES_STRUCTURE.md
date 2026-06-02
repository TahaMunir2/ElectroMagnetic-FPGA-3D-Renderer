# MVP Source Files Structure

## File Organization

```
src/
├── hdl/
│   ├── bram_module_README.md           # BRAM module specification (Yi)
│   ├── bram_module.v                   # [TODO] BRAM Verilog implementation
│   ├── cordic_generator_README.md      # CORDIC generator specification (Yi)
│   ├── cordic_generator.v              # [TODO] CORDIC Verilog implementation
│   ├── fdtd_solver_README.md           # FDTD solver specification (Taha)
│   ├── fdtd_solver.v                   # [TODO] FDTD solver Verilog implementation
│   ├── fsm_toplevel_README.md          # FSM and top-level specification
│   ├── fsm_controller.v                # [TODO] FSM controller Verilog
│   ├── top_fdtd_solver.v               # [TODO] Top-level module
│   ├── tb_bram.v                       # [TODO] BRAM testbench
│   ├── tb_cordic_gen.v                 # [TODO] CORDIC testbench
│   ├── tb_fdtd_solver.v                # [TODO] FDTD solver testbench
│   └── tb_top_system.v                 # [TODO] System testbench
│
└── python/
    ├── fdtd_reference.py               # Q3.13 reference FDTD implementation
    ├── test_fdtd_reference.py          # [TODO] Unit tests for reference
    ├── verify_hardware.py              # [TODO] Verification against hardware output
    └── utils.py                        # [TODO] Utility functions (Q3.13 ops, etc.)
```

## File Creation Order

1. **Specifications First** (DONE)
   - [ ] Module README files with interface specs

2. **Python Reference** (DONE - Core implementation)
   - [ ] Verification tests needed

3. **HDL Skeleton**
   - [ ] Module interface definitions
   - [ ] Placeholder implementations

4. **Testbenches**
   - [ ] Unit test fixtures
   - [ ] Integration test framework

5. **Implementation**
   - [ ] BRAM module (Yi)
   - [ ] CORDIC generator (Yi)
   - [ ] FDTD solver (Taha)
   - [ ] FSM and top-level

6. **System Integration**
   - [ ] Module interconnection
   - [ ] Full system simulation
   - [ ] Performance validation

---

## Next Steps

1. Create stub files for all Verilog modules
2. Define precise port lists in each module
3. Create matching testbench skeletons
4. Begin parallel module development
5. Establish integration schedule

---

**Status**: Template structure prepared
**Last Updated**: May 20, 2026

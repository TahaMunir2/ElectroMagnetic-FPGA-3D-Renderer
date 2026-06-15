# =============================================================================
#  add_ps_integration.tcl
#
#  Opens the existing MVP2_pingpong project, opens the BD, and adds:
#    - Zynq PS7 (PYNQ-Z1 board preset, 25 MHz FCLK0, M_AXI_GP0)
#    - proc_sys_reset
#    - AXI GPIO x4  (control / status / smag_a access / smag_b access)
#    - AXI Interconnect (PS GP0 -> 4 GPIO slaves)
#
#  All external BD ports are removed and driven via PS/AXI, giving a
#  self-contained design that can be bitstreamed for PYNQ.
#
#  PYNQ address map:
#    0x41200000  axi_gpio_ctrl    CH1[31:0] out: {amplitude_q313, phase_step_q313}
#                                 CH2[31:0] out: {17'b0, sample_req, mag_mode, solver_enable, source_addr}
#    0x41210000  axi_gpio_status  CH1[31:0] in : solver_checksum
#                                 CH2[31:0] in : {source_q313[15:0], 9'b0, pp_frame_ready,
#                                                 pp_read_sel, source_latched, mag_busy,
#                                                 mag_done, source_valid, solver_done}
#    0x41220000  axi_gpio_smag_a  CH1[31:0] out: {19'b0, smag_a_enb, smag_a_addrb}
#                                 CH2[31:0] in : {16'b0, smag_a_doutb}
#    0x41230000  axi_gpio_smag_b  same layout for smag_b
# =============================================================================

set proj_dir "E:/Vivado/Projects/desperate_yi/MVP2_pingpong"
set bd_name  "mvp2_pingpong_bd"

open_project [file join $proj_dir MVP2_pingpong.xpr]
open_bd_design [get_files -filter {NAME =~ *mvp2_pingpong_bd.bd}]

# ---------------------------------------------------------------------------
#  Helper: capture pins on a BD port's net then delete the port.
#  Returns {source_pin sink_pin_list} for output ports (driven by IP)
#  and {sink_pin_list} for input ports (driven by the port / to be re-driven).
# ---------------------------------------------------------------------------
proc port_sources {port_name} {
    return [get_bd_pins -quiet \
        -of_objects [get_bd_nets -of_objects [get_bd_ports $port_name]] \
        -filter {DIR == O}]
}
proc port_sinks {port_name} {
    return [get_bd_pins -quiet \
        -of_objects [get_bd_nets -of_objects [get_bd_ports $port_name]] \
        -filter {DIR == I}]
}

# ---------------------------------------------------------------------------
#  1. Snapshot existing clk / rst connections then remove the ports
# ---------------------------------------------------------------------------
set clk_sinks [port_sinks clk]
set rst_sinks [port_sinks rst]
delete_bd_objs [get_bd_ports clk] [get_bd_ports rst]

# ---------------------------------------------------------------------------
#  2. Add PS7 (PYNQ-Z1 board preset, 25 MHz FCLK0, M_AXI_GP0)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} \
    [get_bd_cells processing_system7_0]
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {25} \
    CONFIG.PCW_USE_M_AXI_GP0            {1}  \
] [get_bd_cells processing_system7_0]

# proc_sys_reset
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins proc_sys_reset_0/slowest_sync_clk] \
               [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins proc_sys_reset_0/ext_reset_in]

# Reconnect old clk / rst sinks to PS sources
foreach pin $clk_sinks {
    catch { connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] $pin }
}
foreach pin $rst_sinks {
    catch { connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_reset] $pin }
}

# ---------------------------------------------------------------------------
#  3. AXI Interconnect (1 PS master -> 4 GPIO slaves)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property CONFIG.NUM_MI {4} [get_bd_cells axi_interconnect_0]

set fclk [get_bd_pins processing_system7_0/FCLK_CLK0]
set ic_aresetn [get_bd_pins proc_sys_reset_0/interconnect_aresetn]
set per_aresetn [get_bd_pins proc_sys_reset_0/peripheral_aresetn]

connect_bd_net $fclk \
    [get_bd_pins axi_interconnect_0/ACLK] \
    [get_bd_pins axi_interconnect_0/S00_ACLK] \
    [get_bd_pins axi_interconnect_0/M00_ACLK] \
    [get_bd_pins axi_interconnect_0/M01_ACLK] \
    [get_bd_pins axi_interconnect_0/M02_ACLK] \
    [get_bd_pins axi_interconnect_0/M03_ACLK]
connect_bd_net $ic_aresetn [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net $per_aresetn \
    [get_bd_pins axi_interconnect_0/S00_ARESETN] \
    [get_bd_pins axi_interconnect_0/M00_ARESETN] \
    [get_bd_pins axi_interconnect_0/M01_ARESETN] \
    [get_bd_pins axi_interconnect_0/M02_ARESETN] \
    [get_bd_pins axi_interconnect_0/M03_ARESETN]
connect_bd_intf_net \
    [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
    [get_bd_intf_pins axi_interconnect_0/S00_AXI]

# ---------------------------------------------------------------------------
#  Helper procs for slices / concats
# ---------------------------------------------------------------------------
proc make_slice {cell_name from to total_width} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 $cell_name
    set_property -dict [list \
        CONFIG.DIN_FROM    $from        \
        CONFIG.DIN_TO      $to          \
        CONFIG.DIN_WIDTH   $total_width \
        CONFIG.DOUT_WIDTH  [expr {$from - $to + 1}] \
    ] [get_bd_cells $cell_name]
}
proc make_const {cell_name width val} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 $cell_name
    set_property -dict [list \
        CONFIG.CONST_WIDTH $width \
        CONFIG.CONST_VAL   $val   \
    ] [get_bd_cells $cell_name]
}

# ---------------------------------------------------------------------------
#  4. axi_gpio_ctrl — control outputs PS -> PL
#     CH1[31:0] out: {amplitude_q313[15:0], phase_step_q313[15:0]}
#     CH2[31:0] out: {17'b0, sample_req, mag_mode, solver_enable, source_addr[11:0]}
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH    {32} \
    CONFIG.C_GPIO2_WIDTH   {32} \
    CONFIG.C_ALL_OUTPUTS   {1}  \
    CONFIG.C_ALL_OUTPUTS_2 {1}  \
    CONFIG.C_IS_DUAL       {1}  \
] [get_bd_cells axi_gpio_ctrl]
connect_bd_net $fclk       [get_bd_pins axi_gpio_ctrl/s_axi_aclk]
connect_bd_net $per_aresetn [get_bd_pins axi_gpio_ctrl/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
                    [get_bd_intf_pins axi_gpio_ctrl/S_AXI]

# CH1 slices
make_slice slice_phase_step 15 0 32
make_slice slice_amplitude  31 16 32
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] \
               [get_bd_pins slice_phase_step/Din] \
               [get_bd_pins slice_amplitude/Din]

# CH2 slices
make_slice slice_source_addr   11 0  32
make_slice slice_solver_en     12 12 32
make_slice slice_mag_mode      13 13 32
make_slice slice_sample_req    14 14 32
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio2_io_o] \
               [get_bd_pins slice_source_addr/Din] \
               [get_bd_pins slice_solver_en/Din]   \
               [get_bd_pins slice_mag_mode/Din]    \
               [get_bd_pins slice_sample_req/Din]

# Reconnect old input ports to GPIO slices
foreach pin [port_sinks phase_step_q313] { set ps_phase $pin }
delete_bd_objs [get_bd_ports phase_step_q313]
foreach pin [port_sinks amplitude_q313]  { set ps_amp $pin }
delete_bd_objs [get_bd_ports amplitude_q313]

# Capture sinks before deleting ports
set se_sinks  [port_sinks solver_enable]
set mm_sinks  [port_sinks mag_mode]
set sr_sinks  [port_sinks sample_req]
set sa_sinks  [port_sinks source_addr]
foreach p {solver_enable mag_mode sample_req source_addr} { delete_bd_objs [get_bd_ports $p] }

# Actually source_addr, phase_step, amplitude have multi-bit sinks — use net approach
# Re-get pins directly from known cells
connect_bd_net [get_bd_pins slice_phase_step/Dout] \
               [get_bd_pins cordic_source_adapter_0/phase_step_q313]
connect_bd_net [get_bd_pins slice_amplitude/Dout] \
               [get_bd_pins cordic_source_adapter_0/amplitude_q313]
connect_bd_net [get_bd_pins slice_source_addr/Dout] \
               [get_bd_pins fdtd_solver_bd_adapter_0/source_addr]
connect_bd_net [get_bd_pins slice_solver_en/Dout] \
               [get_bd_pins fdtd_solver_bd_adapter_0/solver_enable]
connect_bd_net [get_bd_pins slice_mag_mode/Dout] \
               [get_bd_pins field_magnitude_bd_adapter_0/mag_mode]
connect_bd_net [get_bd_pins slice_sample_req/Dout] \
               [get_bd_pins cordic_source_adapter_0/sample_req]

# ---------------------------------------------------------------------------
#  5. axi_gpio_status — status inputs PL -> PS
#     CH1[31:0] in: solver_checksum[31:0]
#     CH2[31:0] in: {source_q313[15:0], 9'b0, pp_frame_ready, pp_read_sel,
#                    source_latched, mag_busy, mag_done, source_valid, solver_done}
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_status
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH   {32} \
    CONFIG.C_GPIO2_WIDTH  {32} \
    CONFIG.C_ALL_INPUTS   {1}  \
    CONFIG.C_ALL_INPUTS_2 {1}  \
    CONFIG.C_IS_DUAL      {1}  \
] [get_bd_cells axi_gpio_status]
connect_bd_net $fclk        [get_bd_pins axi_gpio_status/s_axi_aclk]
connect_bd_net $per_aresetn [get_bd_pins axi_gpio_status/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M01_AXI] \
                    [get_bd_intf_pins axi_gpio_status/S_AXI]

# CH1: solver_checksum directly (32-bit match)
delete_bd_objs [get_bd_ports solver_checksum]
connect_bd_net [get_bd_pins fdtd_solver_bd_adapter_0/solver_checksum] \
               [get_bd_pins axi_gpio_status/gpio_io_i]

# CH2: concat {source_q313[15:0], 9'b0, pp_frame_ready, pp_read_sel, source_latched,
#              mag_busy, mag_done, source_valid, solver_done}
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 status_ch2_concat
set_property -dict [list \
    CONFIG.NUM_PORTS {9}  \
    CONFIG.IN0_WIDTH {1}  \
    CONFIG.IN1_WIDTH {1}  \
    CONFIG.IN2_WIDTH {1}  \
    CONFIG.IN3_WIDTH {1}  \
    CONFIG.IN4_WIDTH {1}  \
    CONFIG.IN5_WIDTH {1}  \
    CONFIG.IN6_WIDTH {1}  \
    CONFIG.IN7_WIDTH {9}  \
    CONFIG.IN8_WIDTH {16} \
] [get_bd_cells status_ch2_concat]

make_const zero9 9 0

# Delete output ports and connect sources to concat inputs
foreach p {solver_done source_valid mag_done mag_busy source_latched pp_read_sel pp_frame_ready source_q313} {
    delete_bd_objs [get_bd_ports $p]
}
connect_bd_net [get_bd_pins fdtd_solver_bd_adapter_0/solver_done]   [get_bd_pins status_ch2_concat/In0]
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_valid]   [get_bd_pins status_ch2_concat/In1]
connect_bd_net [get_bd_pins field_magnitude_bd_adapter_0/done]      [get_bd_pins status_ch2_concat/In2]
connect_bd_net [get_bd_pins field_magnitude_bd_adapter_0/busy]      [get_bd_pins status_ch2_concat/In3]
connect_bd_net [get_bd_pins fdtd_solver_bd_adapter_0/source_latched] [get_bd_pins status_ch2_concat/In4]
connect_bd_net [get_bd_pins s_mag_pingpong_ctrl_0/read_sel]         [get_bd_pins status_ch2_concat/In5]
connect_bd_net [get_bd_pins s_mag_pingpong_ctrl_0/frame_ready]      [get_bd_pins status_ch2_concat/In6]
connect_bd_net [get_bd_pins zero9/dout]                              [get_bd_pins status_ch2_concat/In7]
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_q313]    [get_bd_pins status_ch2_concat/In8]
connect_bd_net [get_bd_pins status_ch2_concat/dout] [get_bd_pins axi_gpio_status/gpio2_io_i]

# ---------------------------------------------------------------------------
#  6. axi_gpio_smag_a — smag_a BRAM access
#     CH1[31:0] out: {19'b0, smag_a_enb, smag_a_addrb[11:0]}
#     CH2[32:0] in:  {16'b0, smag_a_doutb[15:0]}
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_smag_a
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH    {32} \
    CONFIG.C_GPIO2_WIDTH   {32} \
    CONFIG.C_ALL_OUTPUTS   {1}  \
    CONFIG.C_ALL_INPUTS_2  {1}  \
    CONFIG.C_IS_DUAL       {1}  \
] [get_bd_cells axi_gpio_smag_a]
connect_bd_net $fclk        [get_bd_pins axi_gpio_smag_a/s_axi_aclk]
connect_bd_net $per_aresetn [get_bd_pins axi_gpio_smag_a/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M02_AXI] \
                    [get_bd_intf_pins axi_gpio_smag_a/S_AXI]

make_slice slice_smag_a_addr 11  0 32
make_slice slice_smag_a_enb  12 12 32
connect_bd_net [get_bd_pins axi_gpio_smag_a/gpio_io_o] \
               [get_bd_pins slice_smag_a_addr/Din] \
               [get_bd_pins slice_smag_a_enb/Din]

# CH2 input: concat {16'b0, smag_a_doutb[15:0]}
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 smag_a_in_concat
set_property -dict [list \
    CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {16} CONFIG.IN1_WIDTH {16} \
] [get_bd_cells smag_a_in_concat]
make_const zero16_a 16 0
connect_bd_net [get_bd_pins zero16_a/dout] [get_bd_pins smag_a_in_concat/In1]

# Remove smag_a ports and connect to slices / concat
foreach p {smag_a_addrb smag_a_enb smag_a_doutb} { delete_bd_objs [get_bd_ports $p] }
connect_bd_net [get_bd_pins slice_smag_a_addr/Dout] [get_bd_pins s_mag_bram_a/addrb]
connect_bd_net [get_bd_pins slice_smag_a_enb/Dout]  [get_bd_pins s_mag_bram_a/enb]
connect_bd_net [get_bd_pins s_mag_bram_a/doutb]     [get_bd_pins smag_a_in_concat/In0]
connect_bd_net [get_bd_pins smag_a_in_concat/dout]  [get_bd_pins axi_gpio_smag_a/gpio2_io_i]

# ---------------------------------------------------------------------------
#  7. axi_gpio_smag_b — smag_b BRAM access (same layout)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_smag_b
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH    {32} \
    CONFIG.C_GPIO2_WIDTH   {32} \
    CONFIG.C_ALL_OUTPUTS   {1}  \
    CONFIG.C_ALL_INPUTS_2  {1}  \
    CONFIG.C_IS_DUAL       {1}  \
] [get_bd_cells axi_gpio_smag_b]
connect_bd_net $fclk        [get_bd_pins axi_gpio_smag_b/s_axi_aclk]
connect_bd_net $per_aresetn [get_bd_pins axi_gpio_smag_b/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M03_AXI] \
                    [get_bd_intf_pins axi_gpio_smag_b/S_AXI]

make_slice slice_smag_b_addr 11  0 32
make_slice slice_smag_b_enb  12 12 32
connect_bd_net [get_bd_pins axi_gpio_smag_b/gpio_io_o] \
               [get_bd_pins slice_smag_b_addr/Din] \
               [get_bd_pins slice_smag_b_enb/Din]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 smag_b_in_concat
set_property -dict [list \
    CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {16} CONFIG.IN1_WIDTH {16} \
] [get_bd_cells smag_b_in_concat]
make_const zero16_b 16 0
connect_bd_net [get_bd_pins zero16_b/dout] [get_bd_pins smag_b_in_concat/In1]

foreach p {smag_b_addrb smag_b_enb smag_b_doutb} { delete_bd_objs [get_bd_ports $p] }
connect_bd_net [get_bd_pins slice_smag_b_addr/Dout] [get_bd_pins s_mag_bram_b/addrb]
connect_bd_net [get_bd_pins slice_smag_b_enb/Dout]  [get_bd_pins s_mag_bram_b/enb]
connect_bd_net [get_bd_pins s_mag_bram_b/doutb]     [get_bd_pins smag_b_in_concat/In0]
connect_bd_net [get_bd_pins smag_b_in_concat/dout]  [get_bd_pins axi_gpio_smag_b/gpio2_io_i]

# ---------------------------------------------------------------------------
#  8. AXI address assignment
# ---------------------------------------------------------------------------
assign_bd_address [get_bd_addr_segs {axi_gpio_ctrl/S_AXI/Reg}]    -range 64K -offset 0x41200000
assign_bd_address [get_bd_addr_segs {axi_gpio_status/S_AXI/Reg}]  -range 64K -offset 0x41210000
assign_bd_address [get_bd_addr_segs {axi_gpio_smag_a/S_AXI/Reg}]  -range 64K -offset 0x41220000
assign_bd_address [get_bd_addr_segs {axi_gpio_smag_b/S_AXI/Reg}]  -range 64K -offset 0x41230000

# ---------------------------------------------------------------------------
#  9. Validate, save, regenerate wrapper
# ---------------------------------------------------------------------------
regenerate_bd_layout -routing
validate_bd_design
save_bd_design

set bd_file [get_property FILE_NAME [get_bd_designs $bd_name]]
set_property synth_checkpoint_mode None [get_files $bd_file]
generate_target all [get_files $bd_file]

set wrapper [make_wrapper -files [get_files $bd_file] -top]
add_files -norecurse -force $wrapper
set_property top ${bd_name}_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts ""
puts "INFO: ============================================================"
puts "INFO: PS integration complete."
puts "INFO: AXI GPIO addresses:"
puts "INFO:   0x41200000  axi_gpio_ctrl   (control)"
puts "INFO:   0x41210000  axi_gpio_status (status + checksum)"
puts "INFO:   0x41220000  axi_gpio_smag_a (smag_a BRAM read)"
puts "INFO:   0x41230000  axi_gpio_smag_b (smag_b BRAM read)"
puts "INFO: Run implementation then generate bitstream."
puts "INFO: ============================================================"
puts ""

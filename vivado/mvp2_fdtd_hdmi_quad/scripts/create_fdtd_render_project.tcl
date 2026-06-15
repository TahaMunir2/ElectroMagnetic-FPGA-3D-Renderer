# =============================================================================
#  create_fdtd_render_project.tcl
#
#  Builds MVP2_fdtd_hdmi — the FDTD solver + ping-pong s_mag buffers feeding the
#  D1S48 ray-march renderer out over HDMI, all PS-controllable.
#
#  Pipeline (single 25 MHz clk_pix domain for the whole datapath):
#    CORDIC -> fdtd_solver -> field_magnitude -> ping-pong s_mag BRAMs
#           -> s_mag_to_heightmap_bridge -> 52 writable heightmap BRAMs
#           -> D1S48 ray_unit -> rgb2dvi -> HDMI
#
#  Clocks:
#    external 125 MHz (H16) -> clk_wiz -> clk_out1 25 MHz (clk_pix, whole datapath)
#                                      -> clk_out2 125 MHz (rgb2dvi serial)
#    PS FCLK_CLK0 50 MHz -> AXI domain (renderer camera AXI-Lite + FDTD GPIO)
#
#  AXI address map:
#    0x40000000  renderer camera control (AXI4-Lite, from camera_ctrl_axi)
#    0x41200000  axi_gpio_ctrl    CH1: {amplitude_q313, phase_step_q313}
#                                 CH2: {16'b0, free_run, sample_req, mag_mode,
#                                       solver_enable, source_addr[11:0]}
#    0x41220000  axi_gpio_status  CH1: solver_checksum[31:0]
#                                 CH2: {source_q313[15:0], 8'b0, bridge_busy,
#                                       pp_frame_ready, pp_read_sel, source_latched,
#                                       mag_busy, mag_done, source_valid, solver_done}
#
#  Run from a Vivado Tcl console (project must NOT already be open), or batch:
#    vivado -mode batch -source create_fdtd_render_project.tcl
#  Env: RUN_SYNTH=1 also runs synth (+ impl/bit if RUN_IMPL=1). VIVADO_JOBS=N.
# =============================================================================

set proj_name "MVP2_fdtd_hdmi_quad"
set proj_dir  "E:/Vivado/Projects/desperate_yi/MVP2_fdtd_hdmi_quad"
set part      "xc7z020clg400-1"
set rtl_dir   [file join $proj_dir rtl]
set ip_repo   [file join $proj_dir ip_repo]
set ip_work   [file join $proj_dir .ip_packager_work]
set dvi_lib   "E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/third_party/vivado-library/ip"
set bd_name   "fdtd_hdmi_bd"
set jobs      4
if {[info exists ::env(VIVADO_JOBS)]} { set jobs $::env(VIVADO_JOBS) }
set run_synth 0
set run_impl  0
if {[info exists ::env(RUN_SYNTH)] && $::env(RUN_SYNTH) eq "1"} { set run_synth 1 }
if {[info exists ::env(RUN_IMPL)]  && $::env(RUN_IMPL)  eq "1"} { set run_impl  1 ; set run_synth 1 }

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
proc ensure_port {name dir args} {
    if {[llength [get_bd_ports -quiet $name]] == 0} {
        eval create_bd_port -dir $dir $args $name
    }
    return [get_bd_ports $name]
}

proc package_ip {part ip_repo_dir work_dir ip_name top_module v_files sv_files desc} {
    set ip_root [file join $ip_repo_dir $ip_name]
    set pkg_dir [file join $work_dir    $ip_name]
    if {[file exists $ip_root]} { file delete -force $ip_root }
    if {[file exists $pkg_dir]} { file delete -force $pkg_dir }
    file mkdir $ip_repo_dir
    file mkdir $work_dir

    puts "INFO: Packaging $top_module -> user.org:user:${ip_name}:1.0"
    create_project ${ip_name}_pkg $pkg_dir -part $part -force
    set_property source_mgmt_mode None [current_project]

    foreach f $v_files {
        set f [file normalize $f]
        if {![file exists $f]} { error "Missing Verilog file for $ip_name: $f" }
        add_files -norecurse $f
        set_property file_type Verilog [get_files $f]
    }
    foreach f $sv_files {
        set f [file normalize $f]
        if {![file exists $f]} { error "Missing SystemVerilog file for $ip_name: $f" }
        add_files -norecurse $f
        set_property file_type SystemVerilog [get_files $f]
    }

    set_property top $top_module [get_filesets sources_1]
    update_compile_order -fileset sources_1

    ipx::package_project -root_dir $ip_root \
        -vendor user.org -library user -taxonomy /UserIP -force -import_files
    set core [ipx::current_core]
    set_property name         $ip_name $core
    set_property display_name $ip_name $core
    set_property description  $desc    $core
    ipx::update_checksums $core
    ipx::save_core $core
    close_project
}

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
    set_property -dict [list CONFIG.CONST_WIDTH $width CONFIG.CONST_VAL $val] \
        [get_bd_cells $cell_name]
}

# ---------------------------------------------------------------------------
#  Step 1 — Package custom FDTD IPs (renderer is added as a module reference)
# ---------------------------------------------------------------------------
# Quad-lane FDTD adapter: Taha's 4-lane core + magnitude scanner + free-run +
# clear, self-contained (field BRAMs inferred inside bram_module).
set quad_v [list \
    [file join $rtl_dir integration fdtd_quad_bd_adapter.v] \
    [file join $rtl_dir integration field_magnitude_quad.v] \
    [file join $rtl_dir fdtd_quad_import bram_module.v]     \
]
set quad_sv [list \
    [file join $rtl_dir integration fdtd_quad_core.sv]  \
    [file join $rtl_dir fdtd_quad_import fdtd_solver.sv] \
    [file join $rtl_dir fdtd_quad_import fdtd_engine.sv] \
    [file join $rtl_dir fdtd_quad_import pml.sv]         \
    [file join $rtl_dir fdtd_quad_import Ey.sv]          \
    [file join $rtl_dir fdtd_quad_import Ex.sv]          \
    [file join $rtl_dir fdtd_quad_import Bz.sv]          \
]

package_ip $part $ip_repo $ip_work \
    cordic_source_adapter cordic_source_adapter \
    [list [file join $rtl_dir cordic_source_adapter.v]] [list] \
    "MVP2 CORDIC source adapter."

package_ip $part $ip_repo $ip_work \
    fdtd_quad_bd_adapter fdtd_quad_bd_adapter \
    $quad_v $quad_sv \
    "Quad-lane FDTD adapter (4 lanes, 2048 cyc/iter, magnitude + free-run + clear)."

package_ip $part $ip_repo $ip_work \
    s_mag_pingpong_ctrl s_mag_pingpong_ctrl \
    [list [file join $rtl_dir s_mag_pingpong_ctrl.v]] [list] \
    "MVP2 s_mag ping-pong double-buffer controller."

package_ip $part $ip_repo $ip_work \
    smag_bram smag_bram \
    [list [file join $rtl_dir smag_bram.v]] [list] \
    "MVP2 s_mag BRAM 16x4096 simple-dual-port."

package_ip $part $ip_repo $ip_work \
    s_mag_to_heightmap_bridge s_mag_to_heightmap_bridge \
    [list] [list [file join $rtl_dir integration s_mag_to_heightmap_bridge.sv]] \
    "FDTD s_mag -> renderer heightmap bridge (vblank-gated, 52-way broadcast)."

# ---------------------------------------------------------------------------
#  Step 2 — Create main project
# ---------------------------------------------------------------------------
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set ip_paths [list $ip_repo]
if {[file exists [file join $dvi_lib rgb2dvi component.xml]]} {
    lappend ip_paths $dvi_lib
} else {
    puts "WARNING: rgb2dvi not found at $dvi_lib — HDMI serialiser will be missing."
}
set_property ip_repo_paths $ip_paths [current_project]
update_ip_catalog -rebuild

set pynq_boards [get_board_parts -quiet *pynq-z1*]
if {[llength $pynq_boards] > 0} {
    set_property board_part [lindex $pynq_boards 0] [current_project]
}

# Renderer sources (module reference d1s48_renderer_core_axi_bd) + writable heightmap
set rend_files [list \
    [file join $rtl_dir renderer d1s48_renderer_core_axi_bd.v] \
    [file join $rtl_dir renderer d1s48_renderer_core_axi.sv]   \
    [file join $rtl_dir renderer camera_ctrl_axi.sv]           \
    [file join $rtl_dir renderer design1_video_timing_640x480.sv] \
    [file join $rtl_dir renderer design1_ray_unit.sv]          \
    [file join $rtl_dir renderer design1_ray_gen.sv]           \
    [file join $rtl_dir renderer design1_march_step.sv]        \
    [file join $rtl_dir renderer design1_marcher.sv]           \
    [file join $rtl_dir renderer design1_normal.sv]            \
    [file join $rtl_dir renderer design1_shader.sv]            \
    [file join $rtl_dir integration heightmap_bram_rw.sv]      \
]
foreach f $rend_files {
    add_files -norecurse $f
    if {[string match *.sv $f]} { set_property file_type SystemVerilog [get_files $f] }
}
add_files -norecurse -fileset constrs_1 [file join $rtl_dir renderer pynq_z1_hdmi.xdc]
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
#  Step 3 — Block design
# ---------------------------------------------------------------------------
create_bd_design $bd_name
current_bd_design $bd_name

# External board ports (match pynq_z1_hdmi.xdc)
create_bd_port -dir I -type clk clk
set_property CONFIG.FREQ_HZ 125000000 [get_bd_ports clk]
create_bd_port -dir I -type rst rst
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports rst]
create_bd_port -dir O hdmi_tx_clk_p
create_bd_port -dir O hdmi_tx_clk_n
create_bd_port -dir O -from 2 -to 0 hdmi_tx_p
create_bd_port -dir O -from 2 -to 0 hdmi_tx_n

# ---- PS7 ----
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} [get_bd_cells ps7_0]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
] [get_bd_cells ps7_0]

# ---- clk_wiz: 125 -> 25 (pixel) + 125 (serial) ----
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list \
    CONFIG.PRIMITIVE {MMCM} \
    CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
] [get_bd_cells clk_wiz_0]
connect_bd_net [get_bd_ports clk] [get_bd_pins clk_wiz_0/clk_in1]
connect_bd_net [get_bd_ports rst] [get_bd_pins clk_wiz_0/reset]

set CLKP [get_bd_pins clk_wiz_0/clk_out1]
set CLK5 [get_bd_pins clk_wiz_0/clk_out2]
set FCLK [get_bd_pins ps7_0/FCLK_CLK0]

# ---- resets ----
# 50 MHz PS/AXI domain
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps_50M
connect_bd_net $FCLK [get_bd_pins rst_ps_50M/slowest_sync_clk] [get_bd_pins ps7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_RESET0_N] [get_bd_pins rst_ps_50M/ext_reset_in]
set PS_ARSTN [get_bd_pins rst_ps_50M/peripheral_aresetn]
set IC_ARSTN [get_bd_pins rst_ps_50M/interconnect_aresetn]

# 25 MHz pixel/datapath domain
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_pix_25M
connect_bd_net $CLKP [get_bd_pins rst_pix_25M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7_0/FCLK_RESET0_N] [get_bd_pins rst_pix_25M/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_pix_25M/dcm_locked]
set PIX_RST   [get_bd_pins rst_pix_25M/peripheral_reset]    ;# active high
set PIX_ARSTN [get_bd_pins rst_pix_25M/peripheral_aresetn]  ;# active low

# ---------------------------------------------------------------------------
#  CORDIC + source adapter (clk_pix)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:cordic:6.0 cordic_0
set_property -dict [list \
    CONFIG.Functional_Selection {Sin_and_Cos} \
    CONFIG.Architectural_Configuration {Parallel} \
    CONFIG.Pipelining_Mode {Optimal} \
    CONFIG.Input_Width {16} CONFIG.Output_Width {16} \
    CONFIG.Phase_Format {Scaled_Radians} \
    CONFIG.Round_Mode {Nearest_Even} \
    CONFIG.Coarse_Rotation {false} \
    CONFIG.Compensation_Scaling {No_Scale_Compensation} \
] [get_bd_cells cordic_0]
create_bd_cell -type ip -vlnv user.org:user:cordic_source_adapter:1.0 cordic_source_adapter_0
connect_bd_net $CLKP [get_bd_pins cordic_0/aclk] [get_bd_pins cordic_source_adapter_0/clk]
connect_bd_net $PIX_RST [get_bd_pins cordic_source_adapter_0/rst]
connect_bd_net [get_bd_pins cordic_source_adapter_0/s_axis_phase_tdata]  [get_bd_pins cordic_0/s_axis_phase_tdata]
connect_bd_net [get_bd_pins cordic_source_adapter_0/s_axis_phase_tvalid] [get_bd_pins cordic_0/s_axis_phase_tvalid]
connect_bd_net [get_bd_pins cordic_0/m_axis_dout_tdata]  [get_bd_pins cordic_source_adapter_0/m_axis_dout_tdata]
connect_bd_net [get_bd_pins cordic_0/m_axis_dout_tvalid] [get_bd_pins cordic_source_adapter_0/m_axis_dout_tvalid]

# ---------------------------------------------------------------------------
#  Quad-lane FDTD adapter (clk_pix) — 4 lanes + magnitude + free-run + clear,
#  self-contained (field BRAMs inferred inside). Outputs s_mag writes directly.
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv user.org:user:fdtd_quad_bd_adapter:1.0 fdtd_quad_0
connect_bd_net $CLKP    [get_bd_pins fdtd_quad_0/clk]
connect_bd_net $PIX_RST [get_bd_pins fdtd_quad_0/rst]
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_q313]  [get_bd_pins fdtd_quad_0/source_q313]
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_valid] [get_bd_pins fdtd_quad_0/source_valid]

# ---------------------------------------------------------------------------
#  Ping-pong controller + s_mag BRAMs (clk_pix). Port B -> bridge (not PS).
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv user.org:user:s_mag_pingpong_ctrl:1.0 s_mag_pingpong_ctrl_0
connect_bd_net $CLKP    [get_bd_pins s_mag_pingpong_ctrl_0/clk]
connect_bd_net $PIX_RST [get_bd_pins s_mag_pingpong_ctrl_0/rst]
foreach sig {s_mag_addra s_mag_ena s_mag_wea s_mag_dina} {
    connect_bd_net [get_bd_pins fdtd_quad_0/${sig}] [get_bd_pins s_mag_pingpong_ctrl_0/${sig}]
}
connect_bd_net [get_bd_pins fdtd_quad_0/mag_done] [get_bd_pins s_mag_pingpong_ctrl_0/mag_done]

create_bd_cell -type ip -vlnv user.org:user:smag_bram:1.0 s_mag_bram_a
create_bd_cell -type ip -vlnv user.org:user:smag_bram:1.0 s_mag_bram_b
foreach {ctrl_pfx bram} {bram_a s_mag_bram_a bram_b s_mag_bram_b} {
    connect_bd_net $CLKP [get_bd_pins $bram/clka]
    connect_bd_net $CLKP [get_bd_pins $bram/clkb]
    foreach sig {addra ena wea dina} {
        connect_bd_net [get_bd_pins s_mag_pingpong_ctrl_0/${ctrl_pfx}_${sig}] [get_bd_pins $bram/${sig}]
    }
}

# ---------------------------------------------------------------------------
#  s_mag -> heightmap bridge (clk_pix)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv user.org:user:s_mag_to_heightmap_bridge:1.0 bridge_0
connect_bd_net $CLKP    [get_bd_pins bridge_0/clk]
connect_bd_net $PIX_RST [get_bd_pins bridge_0/rst]
connect_bd_net [get_bd_pins s_mag_pingpong_ctrl_0/read_sel] [get_bd_pins bridge_0/read_sel]
# bridge drives s_mag port B (both buffers share addr/enb; doutb muxed by read_sel)
connect_bd_net [get_bd_pins bridge_0/s_mag_addrb] [get_bd_pins s_mag_bram_a/addrb] [get_bd_pins s_mag_bram_b/addrb]
connect_bd_net [get_bd_pins bridge_0/s_mag_enb]   [get_bd_pins s_mag_bram_a/enb]   [get_bd_pins s_mag_bram_b/enb]
connect_bd_net [get_bd_pins s_mag_bram_a/doutb]   [get_bd_pins bridge_0/s_mag_a_doutb]
connect_bd_net [get_bd_pins s_mag_bram_b/doutb]   [get_bd_pins bridge_0/s_mag_b_doutb]

# ---------------------------------------------------------------------------
#  Renderer core (module reference) + rgb2dvi + HDMI
# ---------------------------------------------------------------------------
create_bd_cell -type module -reference d1s48_renderer_core_axi_bd renderer_0
connect_bd_net $CLKP      [get_bd_pins renderer_0/clk_pix]
connect_bd_net $PIX_ARSTN [get_bd_pins renderer_0/rst_pix_n]
connect_bd_net $FCLK      [get_bd_pins renderer_0/s_axi_aclk]
connect_bd_net $PS_ARSTN  [get_bd_pins renderer_0/s_axi_aresetn]
# heightmap write port from bridge ; vblank back to bridge
connect_bd_net [get_bd_pins bridge_0/hm_we]    [get_bd_pins renderer_0/hm_we]
connect_bd_net [get_bd_pins bridge_0/hm_waddr] [get_bd_pins renderer_0/hm_waddr]
connect_bd_net [get_bd_pins bridge_0/hm_wdata] [get_bd_pins renderer_0/hm_wdata]
connect_bd_net [get_bd_pins renderer_0/vblank] [get_bd_pins bridge_0/vblank]

create_bd_cell -type ip -vlnv digilentinc.com:ip:rgb2dvi:1.4 rgb2dvi_0
catch {
    set_property -dict [list \
        CONFIG.kGenerateSerialClk {false} \
        CONFIG.kRstActiveHigh {true} \
        CONFIG.kClkRange {2} \
    ] [get_bd_cells rgb2dvi_0]
}
connect_bd_net $CLKP    [get_bd_pins rgb2dvi_0/PixelClk]
connect_bd_net $CLK5    [get_bd_pins rgb2dvi_0/SerialClk]
connect_bd_net $PIX_RST [get_bd_pins rgb2dvi_0/aRst]
connect_bd_net [get_bd_pins renderer_0/vid_pData]  [get_bd_pins rgb2dvi_0/vid_pData]
connect_bd_net [get_bd_pins renderer_0/vid_pVDE]   [get_bd_pins rgb2dvi_0/vid_pVDE]
connect_bd_net [get_bd_pins renderer_0/vid_pHSync] [get_bd_pins rgb2dvi_0/vid_pHSync]
connect_bd_net [get_bd_pins renderer_0/vid_pVSync] [get_bd_pins rgb2dvi_0/vid_pVSync]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_p]  [get_bd_ports hdmi_tx_clk_p]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_n]  [get_bd_ports hdmi_tx_clk_n]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_p] [get_bd_ports hdmi_tx_p]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_n] [get_bd_ports hdmi_tx_n]

# ---------------------------------------------------------------------------
#  AXI interconnect: PS GP0 -> renderer camera + 2 GPIO
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic_0
set_property CONFIG.NUM_MI {3} [get_bd_cells axi_ic_0]
connect_bd_net $FCLK [get_bd_pins axi_ic_0/ACLK] [get_bd_pins axi_ic_0/S00_ACLK] \
    [get_bd_pins axi_ic_0/M00_ACLK] [get_bd_pins axi_ic_0/M01_ACLK] [get_bd_pins axi_ic_0/M02_ACLK]
connect_bd_net $IC_ARSTN [get_bd_pins axi_ic_0/ARESETN]
connect_bd_net $PS_ARSTN [get_bd_pins axi_ic_0/S00_ARESETN] \
    [get_bd_pins axi_ic_0/M00_ARESETN] [get_bd_pins axi_ic_0/M01_ARESETN] [get_bd_pins axi_ic_0/M02_ARESETN]
connect_bd_intf_net [get_bd_intf_pins ps7_0/M_AXI_GP0] [get_bd_intf_pins axi_ic_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M00_AXI] [get_bd_intf_pins renderer_0/S_AXI]

# ---- axi_gpio_ctrl (M01) ----
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_IS_DUAL {1}] [get_bd_cells axi_gpio_ctrl]
connect_bd_net $FCLK     [get_bd_pins axi_gpio_ctrl/s_axi_aclk]
connect_bd_net $PS_ARSTN [get_bd_pins axi_gpio_ctrl/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M01_AXI] [get_bd_intf_pins axi_gpio_ctrl/S_AXI]
# CH1: phase_step[15:0], amplitude[31:16]
make_slice slice_phase_step 15 0  32
make_slice slice_amplitude  31 16 32
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins slice_phase_step/Din] [get_bd_pins slice_amplitude/Din]
connect_bd_net [get_bd_pins slice_phase_step/Dout] [get_bd_pins cordic_source_adapter_0/phase_step_q313]
connect_bd_net [get_bd_pins slice_amplitude/Dout]  [get_bd_pins cordic_source_adapter_0/amplitude_q313]
# CH2: source_addr[11:0], solver_en[12], mag_mode[13], sample_req[14], free_run[15],
#      height_ctl[20:16] (signed 5-bit runtime terrain-height scale)
make_slice slice_source_addr 11 0  32
make_slice slice_solver_en   12 12 32
make_slice slice_mag_mode    13 13 32
make_slice slice_sample_req  14 14 32
make_slice slice_free_run    15 15 32
make_slice slice_height_ctl  20 16 32
make_slice slice_mag_mode_hi 21 21 32
make_slice slice_clear_req   22 22 32
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio2_io_o] \
    [get_bd_pins slice_source_addr/Din] [get_bd_pins slice_solver_en/Din] \
    [get_bd_pins slice_mag_mode/Din] [get_bd_pins slice_sample_req/Din] \
    [get_bd_pins slice_free_run/Din] [get_bd_pins slice_height_ctl/Din] \
    [get_bd_pins slice_mag_mode_hi/Din] [get_bd_pins slice_clear_req/Din]
connect_bd_net [get_bd_pins slice_source_addr/Dout] [get_bd_pins fdtd_quad_0/source_addr]
connect_bd_net [get_bd_pins slice_solver_en/Dout]   [get_bd_pins fdtd_quad_0/solver_enable]
connect_bd_net [get_bd_pins slice_free_run/Dout]    [get_bd_pins fdtd_quad_0/free_run]
connect_bd_net [get_bd_pins slice_sample_req/Dout]  [get_bd_pins cordic_source_adapter_0/sample_req]
connect_bd_net [get_bd_pins slice_height_ctl/Dout]  [get_bd_pins bridge_0/height_ctl]
connect_bd_net [get_bd_pins slice_clear_req/Dout]   [get_bd_pins fdtd_quad_0/clear_req]
# mag_mode is 2-bit: {bit21, bit13} -> 0=|E|, 1=|S|, 2=raw signed Ey (wave)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 mag_mode_concat
set_property -dict [list CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {1} CONFIG.IN1_WIDTH {1}] [get_bd_cells mag_mode_concat]
connect_bd_net [get_bd_pins slice_mag_mode/Dout]    [get_bd_pins mag_mode_concat/In0]
connect_bd_net [get_bd_pins slice_mag_mode_hi/Dout] [get_bd_pins mag_mode_concat/In1]
connect_bd_net [get_bd_pins mag_mode_concat/dout]   [get_bd_pins fdtd_quad_0/mag_mode]

# ---- axi_gpio_status (M02) ----
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_status
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_ALL_INPUTS {1} CONFIG.C_ALL_INPUTS_2 {1} CONFIG.C_IS_DUAL {1}] [get_bd_cells axi_gpio_status]
connect_bd_net $FCLK     [get_bd_pins axi_gpio_status/s_axi_aclk]
connect_bd_net $PS_ARSTN [get_bd_pins axi_gpio_status/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M02_AXI] [get_bd_intf_pins axi_gpio_status/S_AXI]
connect_bd_net [get_bd_pins fdtd_quad_0/solver_checksum] [get_bd_pins axi_gpio_status/gpio_io_i]
# CH2 concat: {source_q313[16], 8'b0[8], bridge_busy, pp_frame_ready, pp_read_sel,
#              source_latched, mag_busy, mag_done, source_valid, solver_done}
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 status_concat
set_property -dict [list CONFIG.NUM_PORTS {10} \
    CONFIG.IN0_WIDTH {1} CONFIG.IN1_WIDTH {1} CONFIG.IN2_WIDTH {1} CONFIG.IN3_WIDTH {1} \
    CONFIG.IN4_WIDTH {1} CONFIG.IN5_WIDTH {1} CONFIG.IN6_WIDTH {1} CONFIG.IN7_WIDTH {1} \
    CONFIG.IN8_WIDTH {8} CONFIG.IN9_WIDTH {16}] [get_bd_cells status_concat]
make_const zero8 8 0
connect_bd_net [get_bd_pins fdtd_quad_0/solver_done]                [get_bd_pins status_concat/In0]
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_valid]    [get_bd_pins status_concat/In1]
connect_bd_net [get_bd_pins fdtd_quad_0/mag_done]                   [get_bd_pins status_concat/In2]
connect_bd_net [get_bd_pins fdtd_quad_0/mag_busy]                   [get_bd_pins status_concat/In3]
connect_bd_net [get_bd_pins fdtd_quad_0/source_latched]             [get_bd_pins status_concat/In4]
connect_bd_net [get_bd_pins s_mag_pingpong_ctrl_0/read_sel]          [get_bd_pins status_concat/In5]
connect_bd_net [get_bd_pins s_mag_pingpong_ctrl_0/frame_ready]       [get_bd_pins status_concat/In6]
connect_bd_net [get_bd_pins bridge_0/busy]                           [get_bd_pins status_concat/In7]
connect_bd_net [get_bd_pins zero8/dout]                              [get_bd_pins status_concat/In8]
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_q313]     [get_bd_pins status_concat/In9]
connect_bd_net [get_bd_pins status_concat/dout] [get_bd_pins axi_gpio_status/gpio2_io_i]

# ---------------------------------------------------------------------------
#  Address map (single source -> no gpio_src this build)
# ---------------------------------------------------------------------------
assign_bd_address
catch { set_property offset 0x40000000 [get_bd_addr_segs -of_objects [get_bd_intf_pins renderer_0/S_AXI]] }
catch { set_property range  4K          [get_bd_addr_segs -of_objects [get_bd_intf_pins renderer_0/S_AXI]] }
catch { set_property offset 0x41200000 [get_bd_addr_segs {axi_gpio_ctrl/S_AXI/Reg}] }
catch { set_property offset 0x41210000 [get_bd_addr_segs {axi_gpio_status/S_AXI/Reg}] }

# ---------------------------------------------------------------------------
#  Finalise
# ---------------------------------------------------------------------------
regenerate_bd_layout
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
puts "INFO: create_fdtd_render_project.tcl complete."
puts "INFO: BD: $bd_name  (top ${bd_name}_wrapper)"
puts "INFO: AXI: renderer 0x40000000 | gpio_ctrl 0x41200000 | gpio_status 0x41210000"
puts "INFO: ============================================================"

if {$run_synth} {
    reset_run synth_1
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
    set st [get_property STATUS [get_runs synth_1]]
    puts "INFO: synth_1: $st"
    if {[string first "Complete" $st] < 0} { error "Synthesis failed: $st" }
    set rdir [file join $proj_dir reports]
    file mkdir $rdir
    open_run synth_1
    report_utilization    -file [file join $rdir util_synth.rpt]
    report_timing_summary -max_paths 10 -file [file join $rdir timing_synth.rpt]
    close_design
    puts "INFO: synth reports in $rdir"
}
if {$run_impl} {
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
    wait_on_run impl_1
    set st [get_property STATUS [get_runs impl_1]]
    puts "INFO: impl_1: $st"
    set rdir [file join $proj_dir reports]
    open_run impl_1
    report_utilization    -file [file join $rdir util_impl.rpt]
    report_timing_summary -max_paths 10 -file [file join $rdir timing_impl.rpt]
    close_design
}

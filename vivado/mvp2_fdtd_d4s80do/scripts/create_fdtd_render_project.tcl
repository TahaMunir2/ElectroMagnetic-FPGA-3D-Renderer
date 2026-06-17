# =============================================================================
#  create_fdtd_render_project.tcl
#
#  Builds MVP2_fdtd_hdmi — the FDTD solver + ping-pong s_mag buffers feeding the
#  D4S80DO low-DSP ray-march renderer out over HDMI, all PS-controllable.
#
#  Pipeline (single 25 MHz clk_pix domain for the whole datapath):
#    CORDIC -> fdtd_solver -> field_magnitude -> ping-pong s_mag BRAMs
#           -> s_mag_to_heightmap_bridge -> 50 writable heightmap BRAMs
#           -> D4S80DO ray_unit -> rgb2dvi -> HDMI
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

set script_dir [file normalize [file dirname [info script]]]
set design_dir [file normalize [file join $script_dir ..]]
set proj_name  "MVP2_fdtd_d4s80do"
set proj_dir   [file normalize [file join $design_dir vivado_project]]
if {[info exists ::env(MVP2_PROJ_DIR)] && $::env(MVP2_PROJ_DIR) ne ""} {
    set proj_dir [file normalize $::env(MVP2_PROJ_DIR)]
}
set part      "xc7z020clg400-1"
set rtl_dir   [file join $design_dir rtl]
set ip_repo   [file join $proj_dir ip_repo]
set ip_work   [file join $proj_dir .ip_packager_work]
set bd_name   "fdtd_hdmi_bd"
set jobs      4
if {[info exists ::env(VIVADO_JOBS)]} { set jobs $::env(VIVADO_JOBS) }
set run_synth 0
set run_impl  0
if {[info exists ::env(RUN_SYNTH)] && $::env(RUN_SYNTH) eq "1"} { set run_synth 1 }
if {[info exists ::env(RUN_IMPL)]  && $::env(RUN_IMPL)  eq "1"} { set run_impl  1 ; set run_synth 1 }

set dvi_lib ""
set dvi_candidates [list]
if {[info exists ::env(DIGILENT_IP_REPO)] && $::env(DIGILENT_IP_REPO) ne ""} {
    lappend dvi_candidates [file normalize $::env(DIGILENT_IP_REPO)]
}
foreach p [list \
    [file join $design_dir third_party vivado-library ip] \
    [file join $design_dir .. .. vivado-library-master ip] \
    D:/ic/vivado-library-master/ip \
    C:/Xilinx/vivado-library-master/ip \
] {
    lappend dvi_candidates [file normalize $p]
}
foreach p $dvi_candidates {
    if {$dvi_lib eq "" && [file exists [file join $p rgb2dvi component.xml]]} {
        set dvi_lib $p
    }
}

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
    "FDTD s_mag -> renderer heightmap bridge (vblank-gated, 50-way broadcast)."

# ---------------------------------------------------------------------------
#  Step 2 — Create main project
# ---------------------------------------------------------------------------
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_FIFO XPM_CDC XPM_MEMORY} [current_project]
set_property simulator_language Mixed [current_project]

set ip_paths [list $ip_repo]
if {$dvi_lib ne "" && [file exists [file join $dvi_lib rgb2dvi component.xml]]} {
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

# Renderer sources (D4S80DO 3D ray-march: module-ref d4s80do_renderer_core_bd +
# 82 writable 8-bit dual-clock heightmap copies, low-DSP ray_unit4 pipeline)
set rend_files [list \
    [file join $rtl_dir renderer_d4 d4s80do_renderer_core_bd.v]   \
    [file join $rtl_dir renderer_d4 d4s80do_core_impl.sv]         \
    [file join $rtl_dir renderer_d4 ray_unit4.sv]                 \
    [file join $rtl_dir renderer_d4 marcher4.sv]                  \
    [file join $rtl_dir renderer_d4 march_step4.sv]               \
    [file join $rtl_dir renderer_d4 normal4.sv]                   \
    [file join $rtl_dir renderer_d4 ray_gen.sv]                   \
    [file join $rtl_dir renderer_d4 shader.sv]                    \
    [file join $rtl_dir renderer_d4 heightmap_bram_d4.sv]         \
    [file join $rtl_dir renderer design1_video_timing_640x480.sv] \
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

# ---- clk_wiz: 125 -> 25 (pixel) + 125 (serial) + 100 (D4S80DO render core) ----
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list \
    CONFIG.PRIMITIVE {MMCM} \
    CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.CLKOUT3_USED {true} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
] [get_bd_cells clk_wiz_0]
connect_bd_net [get_bd_ports clk] [get_bd_pins clk_wiz_0/clk_in1]
connect_bd_net [get_bd_ports rst] [get_bd_pins clk_wiz_0/reset]

set CLKP [get_bd_pins clk_wiz_0/clk_out1]
set CLK5 [get_bd_pins clk_wiz_0/clk_out2]
set CLKCORE [get_bd_pins clk_wiz_0/clk_out3]
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
create_bd_cell -type module -reference d4s80do_renderer_core_bd renderer_0
connect_bd_net $CLKP      [get_bd_pins renderer_0/clk_pix]
connect_bd_net $CLKCORE   [get_bd_pins renderer_0/clk_core]
connect_bd_net $PIX_ARSTN [get_bd_pins renderer_0/rst_pix_n]
# (D4S80DO: render core @100MHz, async-FIFO to 25MHz scanout; PS-loadable camera)
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
set_property CONFIG.NUM_MI {6} [get_bd_cells axi_ic_0]
connect_bd_net $FCLK [get_bd_pins axi_ic_0/ACLK] [get_bd_pins axi_ic_0/S00_ACLK] \
    [get_bd_pins axi_ic_0/M00_ACLK] [get_bd_pins axi_ic_0/M01_ACLK] [get_bd_pins axi_ic_0/M02_ACLK] \
    [get_bd_pins axi_ic_0/M03_ACLK] [get_bd_pins axi_ic_0/M04_ACLK] [get_bd_pins axi_ic_0/M05_ACLK]
connect_bd_net $IC_ARSTN [get_bd_pins axi_ic_0/ARESETN]
connect_bd_net $PS_ARSTN [get_bd_pins axi_ic_0/S00_ARESETN] \
    [get_bd_pins axi_ic_0/M00_ARESETN] [get_bd_pins axi_ic_0/M01_ARESETN] [get_bd_pins axi_ic_0/M02_ARESETN] \
    [get_bd_pins axi_ic_0/M03_ARESETN] [get_bd_pins axi_ic_0/M04_ARESETN] [get_bd_pins axi_ic_0/M05_ARESETN]
connect_bd_intf_net [get_bd_intf_pins ps7_0/M_AXI_GP0] [get_bd_intf_pins axi_ic_0/S00_AXI]

# ---- axi_gpio_ctrl (M00) ----
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_IS_DUAL {1}] [get_bd_cells axi_gpio_ctrl]
connect_bd_net $FCLK     [get_bd_pins axi_gpio_ctrl/s_axi_aclk]
connect_bd_net $PS_ARSTN [get_bd_pins axi_gpio_ctrl/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M00_AXI] [get_bd_intf_pins axi_gpio_ctrl/S_AXI]
# CH1: phase_step[15:0], amplitude[31:16]
make_slice slice_phase_step 15 0  32
make_slice slice_amplitude  31 16 32
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins slice_phase_step/Din] [get_bd_pins slice_amplitude/Din]
connect_bd_net [get_bd_pins slice_phase_step/Dout] [get_bd_pins cordic_source_adapter_0/phase_step_q313]
connect_bd_net [get_bd_pins slice_amplitude/Dout]  [get_bd_pins cordic_source_adapter_0/amplitude_q313]
# CH2: source_addr[11:0], solver_en[12], mag_mode[13], sample_req[14], free_run[15],
#      height_ctl[20:16] (signed 5-bit runtime terrain-height scale)
make_slice slice_source_addr 13 0  32
make_slice slice_solver_en   14 14 32
make_slice slice_mag_mode    15 15 32
make_slice slice_sample_req  16 16 32
make_slice slice_free_run    17 17 32
make_slice slice_height_ctl  22 18 32
make_slice slice_mag_mode_hi 23 23 32
make_slice slice_clear_req   24 24 32
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio2_io_o] \
    [get_bd_pins slice_source_addr/Din] [get_bd_pins slice_solver_en/Din] \
    [get_bd_pins slice_mag_mode/Din] [get_bd_pins slice_sample_req/Din] \
    [get_bd_pins slice_free_run/Din] [get_bd_pins slice_height_ctl/Din] \
    [get_bd_pins slice_mag_mode_hi/Din] [get_bd_pins slice_clear_req/Din]
connect_bd_net [get_bd_pins slice_source_addr/Dout] [get_bd_pins fdtd_quad_0/source_addr]
connect_bd_net [get_bd_pins slice_solver_en/Dout]   [get_bd_pins fdtd_quad_0/solver_enable]
connect_bd_net [get_bd_pins slice_free_run/Dout]    [get_bd_pins fdtd_quad_0/free_run]
# sample_req is re-timed inside the FDTD adapter to one pulse per solver
# iteration (free-run); the PS level feeds ext_sample_req, the pulse drives CORDIC
connect_bd_net [get_bd_pins slice_sample_req/Dout]  [get_bd_pins fdtd_quad_0/ext_sample_req]
connect_bd_net [get_bd_pins fdtd_quad_0/sample_pulse] [get_bd_pins cordic_source_adapter_0/sample_req]
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
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M01_AXI] [get_bd_intf_pins axi_gpio_status/S_AXI]
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

# ---- axi_gpio_motion (M02) — moving source velocity + speed throttle ----
#   CH1 out: {vy[31:16], vx[15:0]}  (signed, 1/256 cells per iteration)
#   CH2 out: {speed_div[31:8], 7'b0, move_en[0]}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_motion
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_IS_DUAL {1}] [get_bd_cells axi_gpio_motion]
connect_bd_net $FCLK     [get_bd_pins axi_gpio_motion/s_axi_aclk]
connect_bd_net $PS_ARSTN [get_bd_pins axi_gpio_motion/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M02_AXI] [get_bd_intf_pins axi_gpio_motion/S_AXI]
make_slice slice_vx        15 0  32
make_slice slice_vy        31 16 32
connect_bd_net [get_bd_pins axi_gpio_motion/gpio_io_o] [get_bd_pins slice_vx/Din] [get_bd_pins slice_vy/Din]
make_slice slice_move_en    0 0  32
make_slice slice_dcfree     1 1  32
make_slice slice_src_bz     2 2  32
make_slice slice_speed_div 31 8  32
connect_bd_net [get_bd_pins axi_gpio_motion/gpio2_io_o] [get_bd_pins slice_move_en/Din] \
    [get_bd_pins slice_dcfree/Din] [get_bd_pins slice_src_bz/Din] [get_bd_pins slice_speed_div/Din]
connect_bd_net [get_bd_pins slice_vx/Dout]        [get_bd_pins fdtd_quad_0/vx]
connect_bd_net [get_bd_pins slice_vy/Dout]        [get_bd_pins fdtd_quad_0/vy]
connect_bd_net [get_bd_pins slice_move_en/Dout]   [get_bd_pins fdtd_quad_0/move_en]
connect_bd_net [get_bd_pins slice_speed_div/Dout] [get_bd_pins fdtd_quad_0/speed_div]
connect_bd_net [get_bd_pins slice_dcfree/Dout]    [get_bd_pins cordic_source_adapter_0/src_dcfree]
connect_bd_net [get_bd_pins slice_src_bz/Dout]    [get_bd_pins fdtd_quad_0/source_bz]
# cam_load strobe reuses a spare bit (bit3) of motion CH2 -> renderer camera latch
make_slice slice_cam_load   3 3  32
connect_bd_net [get_bd_pins axi_gpio_motion/gpio2_io_o] [get_bd_pins slice_cam_load/Din]
connect_bd_net [get_bd_pins slice_cam_load/Dout]  [get_bd_pins renderer_0/cam_load]

# ---------------------------------------------------------------------------
#  Camera-basis GPIOs (M03/M04/M05) — PS computes the orthonormal basis in
#  software and writes 12 signed Q3.13 vectors; the renderer latches them on
#  cam_load.  Two 16-bit values packed per 32-bit channel:
#    cam_a CH1 {oy,ox}      CH2 {fwd_x,oz}
#    cam_b CH1 {fwd_z,fwd_y} CH2 {right_y,right_x}
#    cam_c CH1 {up_x,right_z} CH2 {up_z,up_y}
# ---------------------------------------------------------------------------
proc make_cam_gpio {name fclk arstn ic mi} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 $name
    set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32} \
        CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_IS_DUAL {1}] [get_bd_cells $name]
    connect_bd_net $fclk  [get_bd_pins $name/s_axi_aclk]
    connect_bd_net $arstn [get_bd_pins $name/s_axi_aresetn]
    connect_bd_intf_net [get_bd_intf_pins $ic/${mi}_AXI] [get_bd_intf_pins $name/S_AXI]
}
# slice a packed dual-GPIO and wire each 16-bit half to a renderer cam_* port.
#   lo/hi are the renderer port base-names; ch is gpio_io_o (CH1) or gpio2_io_o (CH2)
proc cam_pack {gpio ch lo_port hi_port} {
    set s_lo "slice_cam_${lo_port}"
    set s_hi "slice_cam_${hi_port}"
    make_slice $s_lo 15 0  32
    make_slice $s_hi 31 16 32
    connect_bd_net [get_bd_pins $gpio/$ch] [get_bd_pins $s_lo/Din] [get_bd_pins $s_hi/Din]
    connect_bd_net [get_bd_pins $s_lo/Dout] [get_bd_pins renderer_0/cam_${lo_port}]
    connect_bd_net [get_bd_pins $s_hi/Dout] [get_bd_pins renderer_0/cam_${hi_port}]
}
make_cam_gpio axi_gpio_cam_a $FCLK $PS_ARSTN axi_ic_0 M03
make_cam_gpio axi_gpio_cam_b $FCLK $PS_ARSTN axi_ic_0 M04
make_cam_gpio axi_gpio_cam_c $FCLK $PS_ARSTN axi_ic_0 M05
cam_pack axi_gpio_cam_a gpio_io_o  ox      oy
cam_pack axi_gpio_cam_a gpio2_io_o oz      fwd_x
cam_pack axi_gpio_cam_b gpio_io_o  fwd_y   fwd_z
cam_pack axi_gpio_cam_b gpio2_io_o right_x right_y
cam_pack axi_gpio_cam_c gpio_io_o  right_z up_x
cam_pack axi_gpio_cam_c gpio2_io_o up_y    up_z

# ---------------------------------------------------------------------------
#  Address map (single source -> no gpio_src this build)
# ---------------------------------------------------------------------------
# Assign each GPIO to a FIXED offset EXPLICITLY. Do NOT rely on a bare
# assign_bd_address + set_property offset: bare assign_bd_address orders the
# slaves ALPHABETICALLY, so adding cam_a/b/c (which sort before "ctrl") silently
# shifted ctrl/motion/status down 3 slots and scrambled the whole notebook map.
# assign_bd_address -offset places each segment deterministically (no collisions
# since every offset is unique) and matches the notebook's hard-coded addresses.
assign_bd_address -offset 0x41200000 -range 64K [get_bd_addr_segs {axi_gpio_ctrl/S_AXI/Reg}]
assign_bd_address -offset 0x41210000 -range 64K [get_bd_addr_segs {axi_gpio_motion/S_AXI/Reg}]
assign_bd_address -offset 0x41220000 -range 64K [get_bd_addr_segs {axi_gpio_status/S_AXI/Reg}]
assign_bd_address -offset 0x41230000 -range 64K [get_bd_addr_segs {axi_gpio_cam_a/S_AXI/Reg}]
assign_bd_address -offset 0x41240000 -range 64K [get_bd_addr_segs {axi_gpio_cam_b/S_AXI/Reg}]
assign_bd_address -offset 0x41250000 -range 64K [get_bd_addr_segs {axi_gpio_cam_c/S_AXI/Reg}]
assign_bd_address  ;# map any remaining segments (none expected) without disturbing the above
# Report the resulting map for the build log (the explicit -offset calls above
# are authoritative; this is just a record to cross-check against the notebook).
catch { report_bd_address -file [file join $proj_dir reports addr_map.rpt] }

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
puts "INFO: AXI: ctrl 0x41200000 | motion 0x41210000 | status 0x41220000"
puts "INFO:      cam_a 0x41230000 | cam_b 0x41240000 | cam_c 0x41250000 (camera basis)"
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

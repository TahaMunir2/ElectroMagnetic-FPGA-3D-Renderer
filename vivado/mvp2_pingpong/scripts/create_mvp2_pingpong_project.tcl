# =============================================================================
#  create_mvp2_pingpong_project.tcl
#
#  Creates a clean Vivado project:
#    MVP2_pingpong — FDTD solver + field magnitude + ping-pong s_mag BRAMs.
#    No renderer. No bridge.
#    BRAM port B exposed as BD ports (smag_a_* / smag_b_*) for PS/DMA later.
#
#  All custom RTL blocks are packaged as user.org:user IPs so they appear as
#  proper IP blocks in the block diagram.
#
#  BRAMs are implemented as thin RTL wrappers (field_bram.v / smag_bram.v)
#  rather than blk_mem_gen to avoid BD IP validator constraints on
#  Use_Byte_Write_Enable in TDP mode.
#
#  Run from Vivado Tcl Console (project must NOT already be open):
#    source E:/Vivado/Projects/desperate_yi/MVP2_pingpong/scripts/create_mvp2_pingpong_project.tcl
#
#  Optional env vars:
#    RUN_SYNTH=1   — also run synthesis after BD build
#    VIVADO_JOBS=N — parallelism (default 4)
# =============================================================================

set proj_name "MVP2_pingpong"
set proj_dir  "E:/Vivado/Projects/desperate_yi/MVP2_pingpong"
set part      "xc7z020clg400-1"
set rtl_dir   [file join $proj_dir rtl]
set ip_repo   [file join $proj_dir ip_repo]
set ip_work   [file join $proj_dir .ip_packager_work]
set bd_name   "mvp2_pingpong_bd"
set jobs      4
if {[info exists ::env(VIVADO_JOBS)]} { set jobs $::env(VIVADO_JOBS) }
set run_synth 0
if {[info exists ::env(RUN_SYNTH)] && $::env(RUN_SYNTH) eq "1"} { set run_synth 1 }

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

proc ensure_port {name dir args} {
    if {[llength [get_bd_ports -quiet $name]] == 0} {
        eval create_bd_port -dir $dir $args $name
    }
    return [get_bd_ports $name]
}

# Package a set of RTL files as a user.org:user IP.
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

# ---------------------------------------------------------------------------
#  Step 1 — Package all custom IPs
#
#  field_bram / smag_bram are thin RTL wrappers that infer RAMB36E1 primitives.
#  Using RTL IPs avoids blk_mem_gen BD validator issues with 16-bit TDP width.
# ---------------------------------------------------------------------------

set solver_sv [list \
    [file join $rtl_dir fdtd_solver_import fdtd_solver.sv] \
    [file join $rtl_dir fdtd_solver_import fdtd_engine.sv] \
    [file join $rtl_dir fdtd_solver_import pml.sv]         \
    [file join $rtl_dir fdtd_solver_import Ey.sv]          \
    [file join $rtl_dir fdtd_solver_import Ex.sv]          \
    [file join $rtl_dir fdtd_solver_import Bz.sv]          \
]

package_ip $part $ip_repo $ip_work \
    cordic_source_adapter cordic_source_adapter \
    [list [file join $rtl_dir cordic_source_adapter.v]] [list] \
    "MVP2 CORDIC source adapter — phase accumulator + amplitude scaler."

package_ip $part $ip_repo $ip_work \
    fdtd_solver_bd_adapter fdtd_solver_bd_adapter \
    [list [file join $rtl_dir fdtd_solver_bd_adapter.v]] $solver_sv \
    "MVP2 FDTD solver BD adapter — 192x192 2D Maxwell solver with BRAM interfaces."

package_ip $part $ip_repo $ip_work \
    field_magnitude_bd_adapter field_magnitude_bd_adapter \
    [list [file join $rtl_dir field_magnitude_bd_adapter.v]] [list] \
    "MVP2 field magnitude adapter — |E| / |S| post-processing."

package_ip $part $ip_repo $ip_work \
    s_mag_pingpong_ctrl s_mag_pingpong_ctrl \
    [list [file join $rtl_dir s_mag_pingpong_ctrl.v]] [list] \
    "MVP2 s_mag ping-pong BRAM controller — tear-free double buffer."

package_ip $part $ip_repo $ip_work \
    field_bram field_bram \
    [list [file join $rtl_dir field_bram.v]] [list] \
    "MVP2 field BRAM — 16-bit x 36864 true-dual-port block RAM (ey/ex/bz)."

package_ip $part $ip_repo $ip_work \
    smag_bram smag_bram \
    [list [file join $rtl_dir smag_bram.v]] [list] \
    "MVP2 s_mag BRAM — 16-bit x 36864 simple-dual-port block RAM (ping-pong)."

# ---------------------------------------------------------------------------
#  Step 2 — Create main Vivado project
# ---------------------------------------------------------------------------

create_project $proj_name $proj_dir -part $part -force
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog -rebuild

# ---------------------------------------------------------------------------
#  Step 3 — Create Block Design
# ---------------------------------------------------------------------------

create_bd_design $bd_name
current_bd_design $bd_name

# Global ports
create_bd_port -dir I -type clk clk
set_property CONFIG.FREQ_HZ 25000000 [get_bd_ports clk]
create_bd_port -dir I -type rst rst
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports rst]

# ---------------------------------------------------------------------------
#  CORDIC IP + cordic_source_adapter
# ---------------------------------------------------------------------------

create_bd_cell -type ip -vlnv xilinx.com:ip:cordic:6.0 cordic_0
set_property -dict [list \
    CONFIG.Functional_Selection         {Sin_and_Cos}           \
    CONFIG.Architectural_Configuration  {Parallel}              \
    CONFIG.Pipelining_Mode              {Optimal}               \
    CONFIG.Input_Width                  {16}                    \
    CONFIG.Output_Width                 {16}                    \
    CONFIG.Phase_Format                 {Scaled_Radians}        \
    CONFIG.Round_Mode                   {Nearest_Even}          \
    CONFIG.Coarse_Rotation              {false}                 \
    CONFIG.Compensation_Scaling         {No_Scale_Compensation} \
] [get_bd_cells cordic_0]

create_bd_cell -type ip -vlnv user.org:user:cordic_source_adapter:1.0 \
    cordic_source_adapter_0

connect_bd_net [get_bd_ports clk] [get_bd_pins cordic_0/aclk]
connect_bd_net [get_bd_ports clk] [get_bd_pins cordic_source_adapter_0/clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins cordic_source_adapter_0/rst]

# AXI-Stream cordic_source_adapter <-> cordic_0
connect_bd_net [get_bd_pins cordic_source_adapter_0/s_axis_phase_tdata]  \
               [get_bd_pins cordic_0/s_axis_phase_tdata]
connect_bd_net [get_bd_pins cordic_source_adapter_0/s_axis_phase_tvalid] \
               [get_bd_pins cordic_0/s_axis_phase_tvalid]
connect_bd_net [get_bd_pins cordic_0/m_axis_dout_tdata]  \
               [get_bd_pins cordic_source_adapter_0/m_axis_dout_tdata]
connect_bd_net [get_bd_pins cordic_0/m_axis_dout_tvalid] \
               [get_bd_pins cordic_source_adapter_0/m_axis_dout_tvalid]

# Source control BD ports
ensure_port sample_req      I
ensure_port phase_step_q313 I -from 15 -to 0
ensure_port amplitude_q313  I -from 15 -to 0
ensure_port source_q313     O -from 15 -to 0
ensure_port source_valid    O

connect_bd_net [get_bd_ports sample_req]      [get_bd_pins cordic_source_adapter_0/sample_req]
connect_bd_net [get_bd_ports phase_step_q313] [get_bd_pins cordic_source_adapter_0/phase_step_q313]
connect_bd_net [get_bd_ports amplitude_q313]  [get_bd_pins cordic_source_adapter_0/amplitude_q313]
connect_bd_net [get_bd_ports source_q313]     [get_bd_pins cordic_source_adapter_0/source_q313]
connect_bd_net [get_bd_ports source_valid]    [get_bd_pins cordic_source_adapter_0/source_valid]

# ---------------------------------------------------------------------------
#  FDTD solver BD adapter
# ---------------------------------------------------------------------------

create_bd_cell -type ip -vlnv user.org:user:fdtd_solver_bd_adapter:1.0 \
    fdtd_solver_bd_adapter_0

connect_bd_net [get_bd_ports clk] [get_bd_pins fdtd_solver_bd_adapter_0/clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins fdtd_solver_bd_adapter_0/rst]

# Source -> solver
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_q313]  \
               [get_bd_pins fdtd_solver_bd_adapter_0/source_q313]
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_valid] \
               [get_bd_pins fdtd_solver_bd_adapter_0/source_valid]

# Solver control BD ports
ensure_port solver_enable   I
ensure_port solver_done     O
ensure_port solver_checksum O -from 31 -to 0
ensure_port source_latched  O
ensure_port source_addr     I -from 11 -to 0

connect_bd_net [get_bd_ports solver_enable]   [get_bd_pins fdtd_solver_bd_adapter_0/solver_enable]
connect_bd_net [get_bd_ports solver_done]     [get_bd_pins fdtd_solver_bd_adapter_0/solver_done]
connect_bd_net [get_bd_ports solver_checksum] [get_bd_pins fdtd_solver_bd_adapter_0/solver_checksum]
connect_bd_net [get_bd_ports source_latched]  [get_bd_pins fdtd_solver_bd_adapter_0/source_latched]
connect_bd_net [get_bd_ports source_addr]     [get_bd_pins fdtd_solver_bd_adapter_0/source_addr]

# ---------------------------------------------------------------------------
#  Field magnitude BD adapter
# ---------------------------------------------------------------------------

create_bd_cell -type ip -vlnv user.org:user:field_magnitude_bd_adapter:1.0 \
    field_magnitude_bd_adapter_0

connect_bd_net [get_bd_ports clk] [get_bd_pins field_magnitude_bd_adapter_0/clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins field_magnitude_bd_adapter_0/rst]

# solver_done triggers magnitude computation
connect_bd_net [get_bd_pins fdtd_solver_bd_adapter_0/solver_done] \
               [get_bd_pins field_magnitude_bd_adapter_0/start]

# Magnitude control BD ports
ensure_port mag_mode I
ensure_port mag_busy O
ensure_port mag_done O

connect_bd_net [get_bd_ports mag_mode] [get_bd_pins field_magnitude_bd_adapter_0/mag_mode]
connect_bd_net [get_bd_ports mag_busy] [get_bd_pins field_magnitude_bd_adapter_0/busy]
connect_bd_net [get_bd_ports mag_done] [get_bd_pins field_magnitude_bd_adapter_0/done]

# ---------------------------------------------------------------------------
#  Field BRAMs (ey / ex / bz) — user.org:user:field_bram:1.0
#
#  field_magnitude_bd_adapter acts as a mux:
#    - when !mag_active: passes fdtd_solver_bd_adapter signals straight through
#    - when  mag_active: overrides address/enable to scan all cells for magnitude
#
#  BRAM douta fans out to both adapters (only one consumer active at a time).
# ---------------------------------------------------------------------------

proc wire_field_bram {prefix bram} {
    set sol fdtd_solver_bd_adapter_0
    set mag field_magnitude_bd_adapter_0

    connect_bd_net [get_bd_ports clk] [get_bd_pins $bram/clka]
    connect_bd_net [get_bd_ports clk] [get_bd_pins $bram/clkb]

    # Solver outputs -> magnitude mux inputs
    foreach sig {addra ena wea dina addrb enb web dinb} {
        connect_bd_net [get_bd_pins $sol/${prefix}_${sig}] \
                       [get_bd_pins $mag/solver_${prefix}_${sig}]
    }

    # Magnitude mux outputs -> BRAM port A
    foreach sig {addra ena wea dina} {
        connect_bd_net [get_bd_pins $mag/${prefix}_${sig}] \
                       [get_bd_pins $bram/${sig}]
    }
    # douta fans out to both adapters
    connect_bd_net [get_bd_pins $bram/douta] \
                   [get_bd_pins $mag/${prefix}_douta] \
                   [get_bd_pins $sol/${prefix}_douta]

    # Magnitude mux outputs -> BRAM port B
    foreach sig {addrb enb web dinb} {
        connect_bd_net [get_bd_pins $mag/${prefix}_${sig}] \
                       [get_bd_pins $bram/${sig}]
    }
    # doutb only needed by solver for ey/bz; ex has no ex_doutb port
    set sol_doutb [get_bd_pins -quiet $sol/${prefix}_doutb]
    if {[llength $sol_doutb] > 0} {
        connect_bd_net [get_bd_pins $bram/doutb] $sol_doutb
    }
}

create_bd_cell -type ip -vlnv user.org:user:field_bram:1.0 ey_bram
create_bd_cell -type ip -vlnv user.org:user:field_bram:1.0 ex_bram
create_bd_cell -type ip -vlnv user.org:user:field_bram:1.0 bz_bram

wire_field_bram ey ey_bram
wire_field_bram ex ex_bram
wire_field_bram bz bz_bram

# ---------------------------------------------------------------------------
#  Ping-pong controller + BRAMs — user.org:user:smag_bram:1.0
# ---------------------------------------------------------------------------

create_bd_cell -type ip -vlnv user.org:user:s_mag_pingpong_ctrl:1.0 \
    s_mag_pingpong_ctrl_0

connect_bd_net [get_bd_ports clk] [get_bd_pins s_mag_pingpong_ctrl_0/clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins s_mag_pingpong_ctrl_0/rst]

# field_magnitude -> ping-pong ctrl write side
foreach sig {s_mag_addra s_mag_ena s_mag_wea s_mag_dina} {
    connect_bd_net [get_bd_pins field_magnitude_bd_adapter_0/${sig}] \
                   [get_bd_pins s_mag_pingpong_ctrl_0/${sig}]
}
connect_bd_net [get_bd_pins field_magnitude_bd_adapter_0/done] \
               [get_bd_pins s_mag_pingpong_ctrl_0/mag_done]

# Wire one ping-pong BRAM: ctrl -> port A, port B -> BD ports
proc wire_pp_bram {ctrl_pfx bram bd_pfx} {
    connect_bd_net [get_bd_ports clk] [get_bd_pins $bram/clka]
    connect_bd_net [get_bd_ports clk] [get_bd_pins $bram/clkb]

    foreach sig {addra ena wea dina} {
        connect_bd_net [get_bd_pins s_mag_pingpong_ctrl_0/${ctrl_pfx}_${sig}] \
                       [get_bd_pins $bram/${sig}]
    }

    ensure_port ${bd_pfx}_addrb I -from 11 -to 0
    ensure_port ${bd_pfx}_enb   I
    ensure_port ${bd_pfx}_doutb O -from 15 -to 0
    connect_bd_net [get_bd_ports ${bd_pfx}_addrb] [get_bd_pins $bram/addrb]
    connect_bd_net [get_bd_ports ${bd_pfx}_enb]   [get_bd_pins $bram/enb]
    connect_bd_net [get_bd_pins  $bram/doutb]     [get_bd_ports ${bd_pfx}_doutb]
}

create_bd_cell -type ip -vlnv user.org:user:smag_bram:1.0 s_mag_bram_a
create_bd_cell -type ip -vlnv user.org:user:smag_bram:1.0 s_mag_bram_b

wire_pp_bram bram_a s_mag_bram_a smag_a
wire_pp_bram bram_b s_mag_bram_b smag_b

# Ping-pong status BD ports
ensure_port pp_read_sel    O
ensure_port pp_frame_ready O
connect_bd_net [get_bd_ports pp_read_sel]    [get_bd_pins s_mag_pingpong_ctrl_0/read_sel]
connect_bd_net [get_bd_ports pp_frame_ready] [get_bd_pins s_mag_pingpong_ctrl_0/frame_ready]

# ---------------------------------------------------------------------------
#  Finalise
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
puts "INFO: create_mvp2_pingpong_project.tcl completed."
puts "INFO: Project : $proj_dir"
puts "INFO: BD      : $bd_name  (top: ${bd_name}_wrapper)"
puts "INFO: Pipeline: CORDIC -> FDTD solver -> field_magnitude -> ping-pong s_mag BRAMs"
puts "INFO: Ports   : smag_a_addrb/enb/doutb  smag_b_addrb/enb/doutb"
puts "INFO:           pp_read_sel  pp_frame_ready  solver_done  mag_done"
puts "INFO: ============================================================"
puts ""

# ---------------------------------------------------------------------------
#  Optional synthesis
# ---------------------------------------------------------------------------

if {$run_synth} {
    reset_run synth_1
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
    set st [get_property STATUS [get_runs synth_1]]
    puts "INFO: synth_1: $st"
    if {[string first "synth_design Complete" $st] < 0} { error "Synthesis failed: $st" }
    set rdir [file join $proj_dir reports_synth]
    file mkdir $rdir
    open_run synth_1
    report_utilization    -file [file join $rdir utilization.rpt]
    report_timing_summary -max_paths 10 -file [file join $rdir timing.rpt]
    report_drc            -file [file join $rdir drc.rpt]
    close_design
    puts "INFO: Reports: $rdir"
}

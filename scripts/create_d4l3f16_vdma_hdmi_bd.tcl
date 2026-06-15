# Create a PYNQ-Z1 block-design project showing the D4L3F16 framebuffer/VDMA
# HDMI pipeline.
#
# This is a diagram/integration scaffold, not a fit-checked board bitstream.
# The D4L3F16 three-lane core exceeds the PYNQ-Z1 DSP budget; this design is
# intended to show the correct VDMA/DDR/HDMI connection topology.
#
# Usage from the repository root:
#   vivado -mode batch -source scripts/create_d4l3f16_vdma_hdmi_bd.tcl -tclargs -force
#
# Optional:
#   -force
#   -project_dir <path>
#   -ip_repo <path-to-Digilent-vivado-library/ip>

set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set project_name d4l3f16_vdma_hdmi
set project_dir [file normalize [file join $repo_dir D4L3F16 vivado_project_d4l3f16_vdma_hdmi]]
set part_name xc7z020clg400-1
set bd_name d4l3f16_vdma_hdmi
set force_project 0
set explicit_ip_repos [list]

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    if {$arg eq "-force"} {
        set force_project 1
    } elseif {$arg eq "-project_dir"} {
        incr i
        if {$i >= [llength $argv]} {
            error "-project_dir requires a path argument"
        }
        set project_dir [file normalize [lindex $argv $i]]
    } elseif {$arg eq "-ip_repo"} {
        incr i
        if {$i >= [llength $argv]} {
            error "-ip_repo requires a path argument"
        }
        lappend explicit_ip_repos [file normalize [lindex $argv $i]]
    } else {
        error "Unknown argument '$arg'. Supported arguments: -force, -project_dir <path>, -ip_repo <path>"
    }
}

proc first_ipdef {pattern} {
    set defs [get_ipdefs $pattern]
    if {[llength $defs] == 0} {
        set defs [get_ipdefs -all $pattern]
    }
    if {[llength $defs] == 0} {
        error "Could not find IP definition matching '$pattern'"
    }
    return [lindex $defs end]
}

proc checked_file {path} {
    set norm_path [file normalize $path]
    if {![file exists $norm_path]} {
        error "Required file not found: $norm_path"
    }
    return $norm_path
}

proc safe_set_props {cell prop_list} {
    foreach {prop val} $prop_list {
        if {[catch {set_property $prop $val $cell} msg]} {
            puts "WARNING: Could not set $prop=$val on $cell: $msg"
        }
    }
}

proc connect_if_present {from to} {
    set from_objs [get_bd_pins -quiet $from]
    set to_objs [get_bd_pins -quiet $to]
    if {[llength $from_objs] && [llength $to_objs]} {
        connect_bd_net $from_objs $to_objs
        return 1
    }
    return 0
}

if {[file exists [file join $project_dir ${project_name}.xpr]] && !$force_project} {
    error "Project already exists: [file join $project_dir ${project_name}.xpr]. Re-run with -tclargs -force to recreate it."
}

if {$force_project} {
    create_project -force $project_name $project_dir -part $part_name
} else {
    create_project $project_name $project_dir -part $part_name
}

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set candidate_ip_repos [list]
foreach path $explicit_ip_repos {
    lappend candidate_ip_repos $path
}
foreach path [list \
    [file join $repo_dir ip] \
    [file join $repo_dir .. .. vivado-library-master ip] \
    D:/ic/vivado-library-master/ip \
    C:/Xilinx/vivado-library-master/ip \
] {
    lappend candidate_ip_repos [file normalize $path]
}

set ip_repos [list]
foreach path $candidate_ip_repos {
    if {[file exists [file join $path rgb2dvi component.xml]]} {
        lappend ip_repos $path
    }
}
if {[llength $ip_repos] > 0} {
    set_property ip_repo_paths $ip_repos [current_project]
    update_ip_catalog
}

set pynq_boards [get_board_parts -quiet *pynq-z1*]
if {[llength $pynq_boards] > 0} {
    set_property board_part [lindex $pynq_boards 0] [current_project]
}

set source_files [list \
    [checked_file [file join $repo_dir D4S48 ray_gen.sv]] \
    [checked_file [file join $repo_dir D4S48 march_step4.sv]] \
    [checked_file [file join $repo_dir D4L3F16 marcher16.sv]] \
    [checked_file [file join $repo_dir D4S48 normal4.sv]] \
    [checked_file [file join $repo_dir D4S48 shader.sv]] \
    [checked_file [file join $repo_dir D4L3F16 ray_unit4_f16.sv]] \
    [checked_file [file join $repo_dir wrapper heightmap_bram.sv]] \
    [checked_file [file join $repo_dir D4L3F16 ray_unit4_lanes3_f16_axis.sv]] \
    [checked_file [file join $repo_dir wrapper ray_unit4_lanes3_f16_axis_bd.v]] \
]

add_files -norecurse -fileset sources_1 $source_files
foreach src $source_files {
    if {[file extension $src] eq ".sv"} {
        set_property file_type SystemVerilog [get_files $src]
    }
}

add_files -norecurse -fileset constrs_1 \
    [checked_file [file join $repo_dir D4S48 pynq_z1_hdmi_d4s48.xdc]]

set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1

create_bd_design $bd_name
current_bd_design $bd_name

set clk [create_bd_port -dir I -type clk clk]
set_property -dict [list CONFIG.FREQ_HZ 125000000] $clk
set rst [create_bd_port -dir I -type rst rst]
set_property -dict [list CONFIG.POLARITY ACTIVE_HIGH] $rst

create_bd_port -dir O hdmi_tx_clk_p
create_bd_port -dir O hdmi_tx_clk_n
create_bd_port -dir O -from 2 -to 0 hdmi_tx_p
create_bd_port -dir O -from 2 -to 0 hdmi_tx_n

set const1 [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:xlconstant:*"] const_1]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $const1

set ps7 [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:processing_system7:*"] ps7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} [get_bd_cells ps7_0]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
] [get_bd_cells ps7_0]

set clk_wiz [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:clk_wiz:*"] clk_wiz_0]
set_property -dict [list \
    CONFIG.PRIMITIVE {MMCM} \
    CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.NUM_OUT_CLKS {3} \
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

set rst_core [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:proc_sys_reset:*"] rst_core_100M]
set rst_pix  [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:proc_sys_reset:*"] rst_pixel_25M]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins rst_core_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rst_pixel_25M/slowest_sync_clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins rst_core_100M/ext_reset_in] [get_bd_pins rst_pixel_25M/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_core_100M/dcm_locked] [get_bd_pins rst_pixel_25M/dcm_locked]

set renderer [create_bd_cell -type module -reference ray_unit4_lanes3_f16_axis_bd d4l3f16_axis_0]

set vdma [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:axi_vdma:*"] axi_vdma_0]
safe_set_props [get_bd_cells axi_vdma_0] [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_num_fstores {2} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {24} \
    CONFIG.c_mm2s_linebuffer_depth {512} \
    CONFIG.c_s2mm_linebuffer_depth {512} \
]

set vidout [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:v_axi4s_vid_out:*"] v_axi4s_vid_out_0]
safe_set_props [get_bd_cells v_axi4s_vid_out_0] [list \
    CONFIG.C_NATIVE_COMPONENT_WIDTH {8} \
    CONFIG.C_PIXELS_PER_CLOCK {1} \
    CONFIG.C_S_AXIS_VIDEO_DATA_WIDTH {8} \
    CONFIG.C_HAS_ASYNC_CLK {0} \
]

set vtc [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:v_tc:*"] v_tc_0]
safe_set_props [get_bd_cells v_tc_0] [list \
    CONFIG.HAS_AXI4_LITE {false} \
    CONFIG.enable_detection {false} \
    CONFIG.enable_generation {true} \
    CONFIG.VIDEO_MODE {Custom} \
    CONFIG.GEN_VIDEO_FORMAT {RGB} \
    CONFIG.GEN_HACTIVE_SIZE {640} \
    CONFIG.GEN_HFRAME_SIZE {800} \
    CONFIG.GEN_HSYNC_START {656} \
    CONFIG.GEN_HSYNC_END {752} \
    CONFIG.GEN_VACTIVE_SIZE {480} \
    CONFIG.GEN_F0_VFRAME_SIZE {525} \
    CONFIG.GEN_F0_VSYNC_VSTART {490} \
    CONFIG.GEN_F0_VSYNC_VEND {492} \
    CONFIG.GEN_F0_VSYNC_HSTART {640} \
    CONFIG.GEN_F0_VSYNC_HEND {640} \
    CONFIG.GEN_F0_VBLANK_HSTART {640} \
    CONFIG.GEN_F0_VBLANK_HEND {640} \
    CONFIG.VID_PPC {1} \
]

set rgb2dvi [create_bd_cell -type ip -vlnv [first_ipdef "*:rgb2dvi:*"] rgb2dvi_0]
catch {
    set_property -dict [list \
        CONFIG.kGenerateSerialClk {false} \
        CONFIG.kRstActiveHigh {true} \
        CONFIG.kClkRange {2} \
    ] [get_bd_cells rgb2dvi_0]
}

# AXI interconnects: PS GP0 controls VDMA registers, VDMA masters access DDR
# through PS HP0.
set ddr_smc [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:smartconnect:*"] axi_smc_ddr]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells axi_smc_ddr]

set ctrl_smc [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:smartconnect:*"] axi_smc_ctrl]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_smc_ctrl]

# Core/AXI clock domain.
foreach pin [list \
    ps7_0/M_AXI_GP0_ACLK \
    ps7_0/S_AXI_HP0_ACLK \
    axi_smc_ddr/aclk \
    axi_smc_ctrl/aclk \
    axi_vdma_0/s_axi_lite_aclk \
    axi_vdma_0/m_axi_mm2s_aclk \
    axi_vdma_0/m_axi_s2mm_aclk \
    axi_vdma_0/s_axis_s2mm_aclk \
    d4l3f16_axis_0/clk \
] {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins $pin]
}
connect_bd_net [get_bd_pins rst_core_100M/peripheral_aresetn] \
    [get_bd_pins axi_smc_ddr/aresetn] \
    [get_bd_pins axi_smc_ctrl/aresetn] \
    [get_bd_pins axi_vdma_0/axi_resetn] \
    [get_bd_pins d4l3f16_axis_0/rst_n]

# Pixel/TMDS clock domain.
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] \
    [get_bd_pins axi_vdma_0/m_axis_mm2s_aclk] \
    [get_bd_pins v_axi4s_vid_out_0/aclk] \
    [get_bd_pins v_tc_0/clk] \
    [get_bd_pins rgb2dvi_0/PixelClk]
connect_bd_net [get_bd_pins rst_pixel_25M/peripheral_aresetn] \
    [get_bd_pins v_axi4s_vid_out_0/aresetn] \
    [get_bd_pins v_tc_0/resetn]
connect_bd_net [get_bd_pins rst_pixel_25M/peripheral_reset] [get_bd_pins rgb2dvi_0/aRst]
connect_bd_net [get_bd_pins const_1/dout] \
    [get_bd_pins v_axi4s_vid_out_0/aclken] \
    [get_bd_pins v_tc_0/clken] \
    [get_bd_pins v_tc_0/gen_clken]
if {[llength [get_bd_pins -quiet rgb2dvi_0/SerialClk]]} {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins rgb2dvi_0/SerialClk]
}

# AXI control and DDR paths.
connect_bd_intf_net [get_bd_intf_pins ps7_0/M_AXI_GP0] [get_bd_intf_pins axi_smc_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_ctrl/M00_AXI] [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_MM2S] [get_bd_intf_pins axi_smc_ddr/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] [get_bd_intf_pins axi_smc_ddr/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_ddr/M00_AXI] [get_bd_intf_pins ps7_0/S_AXI_HP0]

# Renderer -> VDMA write channel.
if {[llength [get_bd_intf_pins -quiet d4l3f16_axis_0/M_AXIS]]} {
    connect_bd_intf_net [get_bd_intf_pins d4l3f16_axis_0/M_AXIS] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
} else {
    connect_bd_net [get_bd_pins d4l3f16_axis_0/m_axis_tdata]  [get_bd_pins axi_vdma_0/s_axis_s2mm_tdata]
    connect_bd_net [get_bd_pins d4l3f16_axis_0/m_axis_tvalid] [get_bd_pins axi_vdma_0/s_axis_s2mm_tvalid]
    connect_bd_net [get_bd_pins d4l3f16_axis_0/m_axis_tready] [get_bd_pins axi_vdma_0/s_axis_s2mm_tready]
    connect_bd_net [get_bd_pins d4l3f16_axis_0/m_axis_tuser]  [get_bd_pins axi_vdma_0/s_axis_s2mm_tuser]
    connect_bd_net [get_bd_pins d4l3f16_axis_0/m_axis_tlast]  [get_bd_pins axi_vdma_0/s_axis_s2mm_tlast]
    connect_bd_net [get_bd_pins d4l3f16_axis_0/m_axis_tkeep]  [get_bd_pins axi_vdma_0/s_axis_s2mm_tkeep]
}

# VDMA read channel -> AXI4-Stream to Video Out -> rgb2dvi.
if {[catch {
    connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXIS_MM2S] [get_bd_intf_pins v_axi4s_vid_out_0/video_in]
} msg]} {
    puts "WARNING: Interface connection VDMA MM2S -> video out failed, falling back to scalar pins: $msg"
    connect_bd_net [get_bd_pins axi_vdma_0/m_axis_mm2s_tdata]  [get_bd_pins v_axi4s_vid_out_0/s_axis_video_tdata]
    connect_bd_net [get_bd_pins axi_vdma_0/m_axis_mm2s_tvalid] [get_bd_pins v_axi4s_vid_out_0/s_axis_video_tvalid]
    connect_bd_net [get_bd_pins axi_vdma_0/m_axis_mm2s_tready] [get_bd_pins v_axi4s_vid_out_0/s_axis_video_tready]
    connect_bd_net [get_bd_pins axi_vdma_0/m_axis_mm2s_tuser]  [get_bd_pins v_axi4s_vid_out_0/s_axis_video_tuser]
    connect_bd_net [get_bd_pins axi_vdma_0/m_axis_mm2s_tlast]  [get_bd_pins v_axi4s_vid_out_0/s_axis_video_tlast]
}

connect_bd_intf_net [get_bd_intf_pins v_tc_0/vtiming_out] [get_bd_intf_pins v_axi4s_vid_out_0/vtiming_in]
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_data]         [get_bd_pins rgb2dvi_0/vid_pData]
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_active_video] [get_bd_pins rgb2dvi_0/vid_pVDE]
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_hsync]        [get_bd_pins rgb2dvi_0/vid_pHSync]
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_vsync]        [get_bd_pins rgb2dvi_0/vid_pVSync]

connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_p]  [get_bd_ports hdmi_tx_clk_p]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_n]  [get_bd_ports hdmi_tx_clk_n]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_p] [get_bd_ports hdmi_tx_p]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_n] [get_bd_ports hdmi_tx_n]

assign_bd_address
validate_bd_design
save_bd_design

set bd_files [get_files -quiet */${bd_name}.bd]
if {[llength $bd_files] == 0} {
    set bd_files [get_files -quiet ${bd_name}.bd]
}
make_wrapper -files $bd_files -top
set wrapper_file [file join $project_dir ${project_name}.srcs sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
add_files -norecurse $wrapper_file
set_property top ${bd_name}_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts ""
puts "Created D4L3F16 VDMA HDMI block design project:"
puts "  [file join $project_dir ${project_name}.xpr]"
puts ""
puts "Open the block design:"
puts "  $bd_name"
puts ""
puts "Main datapath:"
puts "  d4l3f16_axis_0/M_AXIS -> axi_vdma_0/S_AXIS_S2MM -> PS DDR via S_AXI_HP0"
puts "  PS DDR -> axi_vdma_0/M_AXIS_MM2S -> v_axi4s_vid_out_0 -> rgb2dvi_0 -> HDMI"

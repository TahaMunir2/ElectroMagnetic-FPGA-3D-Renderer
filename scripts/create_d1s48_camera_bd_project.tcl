# Create a PYNQ-Z1 block-design Vivado project for D1S48 with PS camera control.
#
# Usage from the repo root:
#   vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl
#
# To recreate:
#   vivado -mode batch -source scripts/create_d1s48_camera_bd_project.tcl -tclargs -force
#
# Output project:
#   D1S48/vivado_project_d1s48_camera/d1s48_camera_renderer.xpr

set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set project_name d1s48_camera_renderer
set project_dir [file normalize [file join $repo_dir D1S48 vivado_project_d1s48_camera]]
set part_name xc7z020clg400-1
set bd_name design_1
set force_project 0
set explicit_ip_repos [list]

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    if {$arg eq "-force"} {
        set force_project 1
    } elseif {$arg eq "-ip_repo"} {
        incr i
        if {$i >= [llength $argv]} {
            error "-ip_repo requires a path argument"
        }
        lappend explicit_ip_repos [file normalize [lindex $argv $i]]
    } else {
        error "Unknown argument '$arg'. Supported arguments: -force, -ip_repo <path>"
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

proc add_sv_source {path} {
    set norm_path [checked_file $path]
    if {[llength [get_files -quiet $norm_path]] == 0} {
        add_files -norecurse -fileset sources_1 $norm_path
    }
    if {[string match *.sv $norm_path]} {
        set_property file_type SystemVerilog [get_files $norm_path]
    }
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

# Register Digilent Vivado IP library if present. rgb2dvi is not in the Xilinx
# catalog.
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

foreach rel_path {
    D1S48/D1_wrapper/design1_video_timing_640x480.sv
    D1S48/D1_wrapper/heightmap_bram.sv
    D1S48/D1_wrapper/camera_ctrl_axi.sv
    D1S48/D1_wrapper/d1s48_renderer_core_axi.sv
    D1S48/D1_wrapper/d1s48_renderer_core_axi_bd.v
    D1S48/design1_ray_gen.sv
    D1S48/design1_march_step.sv
    D1S48/design1_marcher.sv
    D1S48/design1_normal.sv
    D1S48/design1_shader.sv
    D1S48/design1_ray_unit.sv
} {
    add_sv_source [file join $repo_dir $rel_path]
}

add_files -norecurse -fileset constrs_1 \
    [checked_file [file join $repo_dir D1S48 D1_wrapper pynq_z1_hdmi.xdc]]

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

set ps7 [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:processing_system7:*"] ps7_0]
if {[llength [get_board_parts -quiet *pynq-z1*]] > 0} {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} [get_bd_cells ps7_0]
} else {
    make_bd_intf_pins_external [get_bd_intf_pins ps7_0/DDR]
    make_bd_intf_pins_external [get_bd_intf_pins ps7_0/FIXED_IO]
}

set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50.0} \
] [get_bd_cells ps7_0]

set clk_wiz [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:clk_wiz:*"] clk_wiz_0]
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

set renderer [create_bd_cell -type module -reference d1s48_renderer_core_axi_bd d1s48_renderer_core_axi_0]

set rgb2dvi_vlnv [first_ipdef "*:rgb2dvi:*"]
set rgb2dvi [create_bd_cell -type ip -vlnv $rgb2dvi_vlnv rgb2dvi_0]
catch {
    set_property -dict [list \
        CONFIG.kGenerateSerialClk {false} \
        CONFIG.kRstActiveHigh {true} \
        CONFIG.kClkRange {2} \
    ] [get_bd_cells rgb2dvi_0]
}

set axi_rst [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:proc_sys_reset:*"] rst_ps7_0_50M]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins rst_ps7_0_50M/slowest_sync_clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins rst_ps7_0_50M/ext_reset_in]
connect_bd_net [get_bd_pins ps7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_0_50M/dcm_locked]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins d1s48_renderer_core_axi_0/s_axi_aresetn]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins d1s48_renderer_core_axi_0/s_axi_aclk]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/ps7_0/M_AXI_GP0" Clk_master "/ps7_0/FCLK_CLK0" Clk_slave "/ps7_0/FCLK_CLK0" Clk_xbar "/ps7_0/FCLK_CLK0"} \
    [get_bd_intf_pins d1s48_renderer_core_axi_0/S_AXI]

set pix_rst [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:proc_sys_reset:*"] rst_pixel_25M]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rst_pixel_25M/slowest_sync_clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins rst_pixel_25M/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_pixel_25M/dcm_locked]
connect_bd_net [get_bd_pins rst_pixel_25M/peripheral_aresetn] [get_bd_pins d1s48_renderer_core_axi_0/rst_pix_n]
connect_bd_net [get_bd_pins rst_pixel_25M/peripheral_reset] [get_bd_pins rgb2dvi_0/aRst]

connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins d1s48_renderer_core_axi_0/clk_pix]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rgb2dvi_0/PixelClk]
if {[llength [get_bd_pins -quiet rgb2dvi_0/SerialClk]]} {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins rgb2dvi_0/SerialClk]
} else {
    puts "WARNING: rgb2dvi_0 has no SerialClk pin. Check CONFIG.kGenerateSerialClk; it should be false."
}

connect_bd_net [get_bd_pins d1s48_renderer_core_axi_0/vid_pData]  [get_bd_pins rgb2dvi_0/vid_pData]
connect_bd_net [get_bd_pins d1s48_renderer_core_axi_0/vid_pVDE]   [get_bd_pins rgb2dvi_0/vid_pVDE]
connect_bd_net [get_bd_pins d1s48_renderer_core_axi_0/vid_pHSync] [get_bd_pins rgb2dvi_0/vid_pHSync]
connect_bd_net [get_bd_pins d1s48_renderer_core_axi_0/vid_pVSync] [get_bd_pins rgb2dvi_0/vid_pVSync]

connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_p]  [get_bd_ports hdmi_tx_clk_p]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_n]  [get_bd_ports hdmi_tx_clk_n]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_p] [get_bd_ports hdmi_tx_p]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_n] [get_bd_ports hdmi_tx_n]

assign_bd_address
set renderer_segs [get_bd_addr_segs -quiet ps7_0/Data/*d1s48_renderer_core_axi_0*]
if {[llength $renderer_segs] > 0} {
    set renderer_seg [lindex $renderer_segs 0]
    set_property range 4K $renderer_seg
    set_property offset 0x40000000 $renderer_seg
} else {
    puts "WARNING: Could not find renderer address segment to force 0x40000000."
}

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
puts "Created D1S48 camera-control Vivado project:"
puts "  [file join $project_dir ${project_name}.xpr]"
puts ""
puts "AXI camera base address:"
puts "  0x40000000"
puts ""
puts "Next:"
puts "  Generate bitstream, then copy design_1_wrapper.bit and design_1.hwh to PYNQ with matching basenames."

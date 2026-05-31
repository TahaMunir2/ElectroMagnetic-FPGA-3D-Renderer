# Create the PYNQ-Z1 HDMI renderer block design.
#
# Usage from the Vivado Tcl console, with ray_renderer.xpr open:
#   cd D:/ic/OTE/ElectroMagnetic-FPGA-3D-Renderer
#   source scripts/create_renderer_bd.tcl
#
# The design contains:
#   processing_system7 -> AXI interconnect -> ray_renderer_core_axi/S_AXI
#   clk_wiz_0: 125 MHz board clock -> 25 MHz pixel clock + 125 MHz serial clock
#   ray_renderer_core_axi video outputs -> rgb2dvi_0 -> external HDMI ports

set bd_name design_1
set repo_dir [file normalize [file join [file dirname [info script]] ..]]

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

proc add_sv_source {path} {
    set norm_path [file normalize $path]
    if {![file exists $norm_path]} {
        error "Required source file not found: $norm_path"
    }
    if {[llength [get_files -quiet $norm_path]] == 0} {
        add_files -norecurse -fileset sources_1 $norm_path
    }
}

proc disable_project_file {path} {
    set norm_path [file normalize $path]
    foreach f [get_files -quiet $norm_path] {
        catch {set_property is_enabled false $f}
    }
}

proc enable_or_add_project_file {path fileset} {
    set norm_path [file normalize $path]
    if {![file exists $norm_path]} {
        error "Required project file not found: $norm_path"
    }
    if {[llength [get_files -quiet $norm_path]] == 0} {
        add_files -norecurse -fileset $fileset $norm_path
    }
    foreach f [get_files -quiet $norm_path] {
        catch {set_property is_enabled true $f}
    }
}

proc ensure_renderer_sources {repo_dir} {
    foreach rel_path {
        src/hdl/ray_gen.sv
        src/hdl/march_step.sv
        src/hdl/marcher.sv
        src/hdl/normal.sv
        src/hdl/shader.sv
        src/hdl/ray_unit.sv
        wrapper/video_timing_640x480.sv
        wrapper/heightmap_bram.sv
        wrapper/camera_ctrl_axi.sv
        wrapper/ray_renderer_core_axi.sv
        wrapper/ray_renderer_core_axi_bd.v
    } {
        add_sv_source [file join $repo_dir $rel_path]
    }
    set_property source_mgmt_mode All [current_project]
    update_compile_order -fileset sources_1
}

proc disable_standalone_hdmi_flow {repo_dir} {
    # Keep the BD module-reference cell clean. These files belong to the old
    # standalone top flow; if left enabled, Vivado can copy their IP/XDC files
    # into the renderer module-reference cell.
    foreach rel_path {
        wrapper/ray_unit_hdmi_top.sv
        wrapper/ray_unit_top.sv
        wrapper/constraints.xdc
        wrapper/pynq_z1_hdmi.xdc
        vivado_project/ray_renderer.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci
        vivado_project/ray_renderer.srcs/sources_1/ip/rgb2dvi_0/rgb2dvi_0.xci
    } {
        disable_project_file [file join $repo_dir $rel_path]
    }
}

if {[llength [get_bd_designs -quiet $bd_name]]} {
    current_bd_design $bd_name
    error "Block design '$bd_name' already exists. Rename it, delete it, or change bd_name in this script."
}

create_bd_design $bd_name
current_bd_design $bd_name
disable_standalone_hdmi_flow $repo_dir
ensure_renderer_sources $repo_dir

# External board ports. Names match wrapper/pynq_z1_hdmi.xdc.
set clk [create_bd_port -dir I -type clk clk]
set_property -dict [list CONFIG.FREQ_HZ 125000000] $clk
set rst [create_bd_port -dir I -type rst rst]
set_property -dict [list CONFIG.POLARITY ACTIVE_HIGH] $rst

create_bd_port -dir O hdmi_tx_clk_p
create_bd_port -dir O hdmi_tx_clk_n
create_bd_port -dir O -from 2 -to 0 hdmi_tx_p
create_bd_port -dir O -from 2 -to 0 hdmi_tx_n

# Zynq PS. Board automation will expose DDR and FIXED_IO when the board part is set.
set ps7 [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:processing_system7:*"] ps7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} [get_bd_cells ps7_0]

set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50.0} \
] [get_bd_cells ps7_0]

# Clock wizard: PYNQ-Z1 PL clock is 125 MHz. 640x480 VGA uses 25 MHz pixel clock;
# rgb2dvi needs 5x serial clock for TMDS DDR output.
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

# Renderer RTL module. The BD references a Verilog shim because Vivado module
# reference blocks do not accept a SystemVerilog file as the referenced top.
set renderer [create_bd_cell -type module -reference ray_renderer_core_axi_bd ray_renderer_core_axi_0]

# RGB to DVI encoder.
set rgb2dvi_vlnv [first_ipdef "*:rgb2dvi:*"]
set rgb2dvi [create_bd_cell -type ip -vlnv $rgb2dvi_vlnv rgb2dvi_0]
catch {
    set_property -dict [list \
        CONFIG.kGenerateSerialClk {false} \
        CONFIG.kRstActiveHigh {true} \
        CONFIG.kClkRange {2} \
    ] [get_bd_cells rgb2dvi_0]
}

# AXI reset and interconnect. This keeps all AXI pins in the PS FCLK0 domain.
set axi_rst [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:proc_sys_reset:*"] rst_ps7_0_50M]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins rst_ps7_0_50M/slowest_sync_clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins rst_ps7_0_50M/ext_reset_in]
connect_bd_net [get_bd_pins ps7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_0_50M/dcm_locked]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins ray_renderer_core_axi_0/s_axi_aresetn]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins ray_renderer_core_axi_0/s_axi_aclk]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/ps7_0/M_AXI_GP0" Clk_master "/ps7_0/FCLK_CLK0" Clk_slave "/ps7_0/FCLK_CLK0" Clk_xbar "/ps7_0/FCLK_CLK0"} \
    [get_bd_intf_pins ray_renderer_core_axi_0/S_AXI]

# Pixel reset, synchronized to the 25 MHz pixel domain and released only after
# clk_wiz locks.
set pix_rst [create_bd_cell -type ip -vlnv [first_ipdef "xilinx.com:ip:proc_sys_reset:*"] rst_pixel_25M]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rst_pixel_25M/slowest_sync_clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins rst_pixel_25M/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_pixel_25M/dcm_locked]
connect_bd_net [get_bd_pins rst_pixel_25M/peripheral_aresetn] [get_bd_pins ray_renderer_core_axi_0/rst_pix_n]
connect_bd_net [get_bd_pins rst_pixel_25M/peripheral_reset] [get_bd_pins rgb2dvi_0/aRst]

# Pixel and serial clocking.
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins ray_renderer_core_axi_0/clk_pix]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rgb2dvi_0/PixelClk]
if {[llength [get_bd_pins -quiet rgb2dvi_0/SerialClk]]} {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins rgb2dvi_0/SerialClk]
} else {
    puts "WARNING: rgb2dvi_0 has no SerialClk pin. Check CONFIG.kGenerateSerialClk; it should be false for the external 125 MHz serial clock flow."
}

# Video stream.
connect_bd_net [get_bd_pins ray_renderer_core_axi_0/vid_pData]  [get_bd_pins rgb2dvi_0/vid_pData]
connect_bd_net [get_bd_pins ray_renderer_core_axi_0/vid_pVDE]   [get_bd_pins rgb2dvi_0/vid_pVDE]
connect_bd_net [get_bd_pins ray_renderer_core_axi_0/vid_pHSync] [get_bd_pins rgb2dvi_0/vid_pHSync]
connect_bd_net [get_bd_pins ray_renderer_core_axi_0/vid_pVSync] [get_bd_pins rgb2dvi_0/vid_pVSync]

# HDMI external pins.
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_p]  [get_bd_ports hdmi_tx_clk_p]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_n]  [get_bd_ports hdmi_tx_clk_n]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_p] [get_bd_ports hdmi_tx_p]
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_n] [get_bd_ports hdmi_tx_n]

assign_bd_address
set renderer_segs [get_bd_addr_segs -quiet ps7_0/Data/*ray_renderer_core_axi_0*]
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
set project_dir [get_property DIRECTORY [current_project]]
set project_name [get_property NAME [current_project]]
set wrapper_file [file join $project_dir ${project_name}.srcs sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
add_files -norecurse $wrapper_file
set_property top ${bd_name}_wrapper [get_filesets sources_1]
enable_or_add_project_file [file join $repo_dir wrapper/pynq_z1_hdmi.xdc] constrs_1
update_compile_order -fileset sources_1

puts "Created block design '$bd_name'. Generate bitstream next."

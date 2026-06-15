# Integrate the renderer handoff RTL into the existing MVP2 block design.
#
# Run in Vivado Tcl Console after the FDTD solver BD exists:
#   source E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/scripts/integrate_renderer_bd.tcl
#
# Optional environment variables:
#   VIVADO_PROJECT=E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr
#   RUN_SYNTH=1
#   RUN_IMPL=1
#   VIVADO_JOBS=4
#
# This adds:
#   - s_mag_to_renderer_bridge_0
#   - renderer_bd_adapter_0
#
# Data path:
#   field_magnitude_bd_adapter_0/done
#     -> s_mag_to_renderer_bridge_0 reads s_mag_bram port B
#     -> bridge writes 64x64x16 heightmap samples into renderer copies
#     -> renderer starts when heightmap_ready goes high

proc getenv_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

proc add_file_if_missing {fileset_name path_value file_type} {
    set path_value [file normalize $path_value]
    if {![file exists $path_value]} {
        error "Missing source file: $path_value"
    }
    if {[llength [get_files -quiet $path_value]] == 0} {
        add_files -norecurse -fileset $fileset_name $path_value
    }
    set_property file_type $file_type [get_files $path_value]
}

proc remove_file_if_present {path_value} {
    set path_value [file normalize $path_value]
    set files [get_files -quiet $path_value]
    if {[llength $files] != 0} {
        remove_files $files
    }
}

proc disconnect_pin_if_connected {pin_name} {
    set pin [get_bd_pins -quiet $pin_name]
    if {[llength $pin] == 0} {
        return
    }
    set net [get_bd_nets -quiet -of_objects $pin]
    if {[llength $net] != 0} {
        catch {disconnect_bd_net $net $pin}
        set remaining_pins [get_bd_pins -quiet -of_objects $net]
        set remaining_ports [get_bd_ports -quiet -of_objects $net]
        if {[expr {[llength $remaining_pins] + [llength $remaining_ports]}] < 2} {
            catch {delete_bd_objs $net}
        }
    }
}

proc ensure_port {name dir args} {
    set port [get_bd_ports -quiet $name]
    if {[llength $port] == 0} {
        set port [eval create_bd_port -dir $dir $args $name]
    }
    return $port
}

proc package_project_ip {part ip_repo_dir work_dir ip_name top_module verilog_files sv_files description} {
    set ip_root [file join $ip_repo_dir $ip_name]
    set pkg_project_dir [file join $work_dir $ip_name]
    if {[file exists $ip_root]} {
        file delete -force $ip_root
    }
    if {[file exists $pkg_project_dir]} {
        file delete -force $pkg_project_dir
    }
    file mkdir $ip_repo_dir
    file mkdir $work_dir

    puts "INFO: Packaging $top_module as user.org:user:${ip_name}:1.0"
    create_project ${ip_name}_pkg $pkg_project_dir -part $part -force
    set_property source_mgmt_mode None [current_project]

    foreach src_file $verilog_files {
        set src_file [file normalize $src_file]
        if {![file exists $src_file]} {
            error "Missing Verilog source for $ip_name: $src_file"
        }
        add_files -norecurse $src_file
        set_property file_type Verilog [get_files $src_file]
    }

    foreach src_file $sv_files {
        set src_file [file normalize $src_file]
        if {![file exists $src_file]} {
            error "Missing SystemVerilog source for $ip_name: $src_file"
        }
        add_files -norecurse $src_file
        set_property file_type SystemVerilog [get_files $src_file]
    }

    set_property top $top_module [get_filesets sources_1]
    update_compile_order -fileset sources_1

    ipx::package_project \
        -root_dir $ip_root \
        -vendor user.org \
        -library user \
        -taxonomy /UserIP \
        -force \
        -import_files

    set core [ipx::current_core]
    set_property name $ip_name $core
    set_property display_name $ip_name $core
    set_property description $description $core
    ipx::update_checksums $core
    ipx::save_core $core
    close_project
}

set default_project "E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr"
set project_path [file normalize [getenv_or_default VIVADO_PROJECT $default_project]]
set jobs [getenv_or_default VIVADO_JOBS "4"]
set run_synth [getenv_or_default RUN_SYNTH "0"]
set run_impl [getenv_or_default RUN_IMPL "0"]

if {[llength [get_projects -quiet]] == 0} {
    open_project $project_path
} else {
    set open_project_dir [file normalize [get_property DIRECTORY [current_project]]]
    set open_project_name [get_property NAME [current_project]]
    set open_project_path [file normalize [file join $open_project_dir "${open_project_name}.xpr"]]
    if {![string equal -nocase $open_project_path $project_path]} {
        close_project
        open_project $project_path
    }
}

set proj_dir [get_property DIRECTORY [current_project]]
set bd_file [file join $proj_dir "MVP2_2D_EE_simulation.srcs" "sources_1" "bd" "mvp2_ftdt_bd" "mvp2_ftdt_bd.bd"]
set renderer_hdl [file join $proj_dir renderer_standalone hdl]
set renderer_integration [file join $proj_dir rtl renderer_integration]
set ip_repo_dir [file join $proj_dir ip_repo]
set ip_work_dir [file join $proj_dir .ip_packager_work]
set project_part [get_property PART [current_project]]
set open_project_name [get_property NAME [current_project]]
set main_project_path [file normalize [file join $proj_dir "${open_project_name}.xpr"]]

set renderer_verilog_files [list \
    [file join $renderer_integration renderer_heightmap_ram.v] \
    [file join $renderer_integration renderer_bd_adapter.v] \
]
set renderer_sv_files [list \
    [file join $renderer_hdl ray_gen.sv] \
    [file join $renderer_hdl march_step.sv] \
    [file join $renderer_hdl marcher.sv] \
    [file join $renderer_hdl normal.sv] \
    [file join $renderer_hdl shader.sv] \
    [file join $renderer_hdl ray_unit.sv] \
    [file join $renderer_hdl ray_unit_synth_wrapper.sv] \
]
set bridge_verilog_files [list \
    [file join $renderer_integration s_mag_to_renderer_bridge.v] \
]

foreach src_file [concat $renderer_verilog_files $renderer_sv_files $bridge_verilog_files] {
    remove_file_if_present $src_file
}

catch {close_design}
close_project

package_project_ip \
    $project_part \
    $ip_repo_dir \
    $ip_work_dir \
    renderer_bd_adapter \
    renderer_bd_adapter \
    $renderer_verilog_files \
    $renderer_sv_files \
    "MVP2 renderer adapter: converts a 64x64 heightmap into RGB pixels through Taha's ray renderer."

package_project_ip \
    $project_part \
    $ip_repo_dir \
    $ip_work_dir \
    s_mag_to_renderer_bridge \
    s_mag_to_renderer_bridge \
    $bridge_verilog_files \
    [list] \
    "MVP2 s_mag_bram to renderer heightmap bridge."

open_project $main_project_path
set proj_dir [get_property DIRECTORY [current_project]]
set bd_file [file join $proj_dir "MVP2_2D_EE_simulation.srcs" "sources_1" "bd" "mvp2_ftdt_bd" "mvp2_ftdt_bd.bd"]
set current_ip_repos [get_property ip_repo_paths [current_project]]
if {[lsearch -exact $current_ip_repos $ip_repo_dir] < 0} {
    set_property ip_repo_paths [concat $current_ip_repos [list $ip_repo_dir]] [current_project]
}
update_ip_catalog -rebuild

catch {close_design}
open_bd_design $bd_file

if {[llength [get_bd_cells -quiet fdtd_solver_bd_adapter_0]] == 0} {
    error "fdtd_solver_bd_adapter_0 is missing. Run integrate_fdtd_solver_bd.tcl before integrating the renderer."
}
if {[llength [get_bd_cells -quiet s_mag_bram]] == 0} {
    error "s_mag_bram is missing. The renderer bridge needs the solver magnitude BRAM."
}

foreach obj_name {
    renderer_rgb888 renderer_valid renderer_frame_done
    renderer_heightmap_busy renderer_heightmap_done renderer_heightmap_ready
} {
    catch {delete_bd_objs [get_bd_ports -quiet $obj_name]}
}

catch {delete_bd_objs [get_bd_cells -quiet renderer_bd_adapter_0]}
catch {delete_bd_objs [get_bd_cells -quiet s_mag_to_renderer_bridge_0]}

set bridge_cell [create_bd_cell -type ip -vlnv user.org:user:s_mag_to_renderer_bridge:1.0 s_mag_to_renderer_bridge_0]
set renderer_cell [create_bd_cell -type ip -vlnv user.org:user:renderer_bd_adapter:1.0 renderer_bd_adapter_0]

connect_bd_net [get_bd_ports clk] [get_bd_pins s_mag_to_renderer_bridge_0/clk]
connect_bd_net [get_bd_ports clk] [get_bd_pins renderer_bd_adapter_0/clk]

ensure_port rst I -type rst
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports rst]
connect_bd_net [get_bd_ports rst] [get_bd_pins s_mag_to_renderer_bridge_0/rst]
connect_bd_net [get_bd_ports rst] [get_bd_pins renderer_bd_adapter_0/rst]

# Reclaim s_mag_bram port B for the renderer bridge. The FDTD adapter does not
# consume s_mag_doutb, so port B can safely become the post-magnitude reader.
foreach pin_name {
    s_mag_bram/addrb s_mag_bram/enb s_mag_bram/web s_mag_bram/dinb s_mag_bram/doutb
    fdtd_solver_bd_adapter_0/s_mag_addrb fdtd_solver_bd_adapter_0/s_mag_enb
    fdtd_solver_bd_adapter_0/s_mag_web fdtd_solver_bd_adapter_0/s_mag_dinb
    fdtd_solver_bd_adapter_0/s_mag_doutb
} {
    disconnect_pin_if_connected $pin_name
}

foreach stale_net [get_bd_nets -quiet fdtd_solver_bd_adapter_0_s_mag_*] {
    catch {delete_bd_objs $stale_net}
}
foreach stale_net [get_bd_nets -quiet s_mag_bram_doutb*] {
    catch {delete_bd_objs $stale_net}
}

if {[llength [get_bd_cells -quiet field_magnitude_bd_adapter_0]] != 0} {
    set magnitude_done_pin [get_bd_pins field_magnitude_bd_adapter_0/done]
} elseif {[llength [get_bd_pins -quiet fdtd_solver_bd_adapter_0/mag_done]] != 0} {
    set magnitude_done_pin [get_bd_pins fdtd_solver_bd_adapter_0/mag_done]
} else {
    error "No magnitude-done pin found. Run separate_field_magnitude_ip_bd.tcl or the older solver integration before integrating the renderer."
}

connect_bd_net $magnitude_done_pin [get_bd_pins s_mag_to_renderer_bridge_0/start]

connect_bd_net [get_bd_pins s_mag_to_renderer_bridge_0/s_mag_addr] [get_bd_pins s_mag_bram/addrb]
connect_bd_net [get_bd_pins s_mag_to_renderer_bridge_0/s_mag_en]   [get_bd_pins s_mag_bram/enb]
connect_bd_net [get_bd_pins s_mag_to_renderer_bridge_0/s_mag_we]   [get_bd_pins s_mag_bram/web]
connect_bd_net [get_bd_pins s_mag_to_renderer_bridge_0/s_mag_din]  [get_bd_pins s_mag_bram/dinb]
connect_bd_net [get_bd_pins s_mag_bram/doutb]                      [get_bd_pins s_mag_to_renderer_bridge_0/s_mag_dout]

connect_bd_net [get_bd_pins s_mag_to_renderer_bridge_0/heightmap_we]    [get_bd_pins renderer_bd_adapter_0/heightmap_we]
connect_bd_net [get_bd_pins s_mag_to_renderer_bridge_0/heightmap_waddr] [get_bd_pins renderer_bd_adapter_0/heightmap_waddr]
connect_bd_net [get_bd_pins s_mag_to_renderer_bridge_0/heightmap_wdata] [get_bd_pins renderer_bd_adapter_0/heightmap_wdata]
connect_bd_net [get_bd_pins s_mag_to_renderer_bridge_0/ready]           [get_bd_pins renderer_bd_adapter_0/enable]

ensure_port renderer_rgb888 O -from 23 -to 0
ensure_port renderer_valid O
ensure_port renderer_frame_done O
ensure_port renderer_heightmap_busy O
ensure_port renderer_heightmap_done O
ensure_port renderer_heightmap_ready O

connect_bd_net [get_bd_ports renderer_rgb888]          [get_bd_pins renderer_bd_adapter_0/rgb888]
connect_bd_net [get_bd_ports renderer_valid]           [get_bd_pins renderer_bd_adapter_0/valid]
connect_bd_net [get_bd_ports renderer_frame_done]      [get_bd_pins renderer_bd_adapter_0/frame_done]
connect_bd_net [get_bd_ports renderer_heightmap_busy]  [get_bd_pins s_mag_to_renderer_bridge_0/busy]
connect_bd_net [get_bd_ports renderer_heightmap_done]  [get_bd_pins s_mag_to_renderer_bridge_0/done]
connect_bd_net [get_bd_ports renderer_heightmap_ready] [get_bd_pins s_mag_to_renderer_bridge_0/ready]

set_property location {5 1120 120} [get_bd_cells renderer_bd_adapter_0]
set_property location {4 850 150} [get_bd_cells s_mag_to_renderer_bridge_0]

regenerate_bd_layout -routing
validate_bd_design
save_bd_design

set synth_mode_status [catch {set_property synth_checkpoint_mode None [get_files $bd_file]} synth_mode_result]
if {$synth_mode_status != 0} {
    puts "INFO: Could not set BD synth_checkpoint_mode to None: $synth_mode_result"
} else {
    puts "INFO: Set BD synth_checkpoint_mode to None so renderer dependencies synthesize in the top-level run."
}

generate_target all [get_files $bd_file]
set wrapper_file [make_wrapper -files [get_files $bd_file] -top]
if {[file exists $wrapper_file]} {
    add_files -norecurse -force $wrapper_file
} else {
    set wrapper_file [file join $proj_dir "MVP2_2D_EE_simulation.gen" "sources_1" "bd" "mvp2_ftdt_bd" "hdl" "mvp2_ftdt_bd_wrapper.v"]
    add_files -norecurse -force $wrapper_file
}

set_property top mvp2_ftdt_bd_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

set report_dir [file join $proj_dir reports_renderer_integrated]
file mkdir $report_dir

if {$run_synth eq "1" || $run_impl eq "1"} {
    reset_run synth_1
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
    set synth_status [get_property STATUS [get_runs synth_1]]
    puts "INFO: synth_1 status: $synth_status"
    if {[string first "synth_design Complete" $synth_status] < 0} {
        error "synth_1 did not complete successfully: $synth_status"
    }

    open_run synth_1
    report_utilization -file [file join $report_dir utilization_synth_renderer.rpt]
    report_timing_summary -max_paths 10 -file [file join $report_dir timing_synth_renderer.rpt]
    report_drc -file [file join $report_dir drc_synth_renderer.rpt]
    close_design
}

if {$run_impl eq "1"} {
    reset_run impl_1
    launch_runs impl_1 -to_step route_design -jobs $jobs
    wait_on_run impl_1
    set impl_status [get_property STATUS [get_runs impl_1]]
    puts "INFO: impl_1 status: $impl_status"
    if {[string first "route_design Complete" $impl_status] < 0} {
        error "impl_1 did not route successfully: $impl_status"
    }

    open_run impl_1
    report_utilization -file [file join $report_dir utilization_impl_renderer.rpt]
    report_timing_summary -max_paths 10 -file [file join $report_dir timing_impl_renderer.rpt]
    report_route_status -file [file join $report_dir route_status_renderer.rpt]
    report_drc -file [file join $report_dir drc_impl_renderer.rpt]
    close_design
}

puts "INFO: Renderer integration script completed."
puts "INFO: s_mag_bram port B now feeds s_mag_to_renderer_bridge_0."
puts "INFO: Bridge downsamples 192x192 s_mag_bram to 64x64 by sampling the center of each 3x3 tile."
puts "INFO: renderer_bd_adapter_0 starts when renderer_heightmap_ready goes high."
puts "INFO: Exported renderer outputs: renderer_rgb888[23:0], renderer_valid, renderer_frame_done."
puts "INFO: Optional reports directory: $report_dir"

# Split the post-solver |E| / |S| pass out of fdtd_solver_bd_adapter_0.
#
# Run in Vivado Tcl Console:
#   source E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/scripts/separate_field_magnitude_ip_bd.tcl
#
# Optional environment variables:
#   VIVADO_PROJECT=E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr
#   RUN_SYNTH=1
#   RUN_IMPL=1
#   VIVADO_JOBS=4
#
# Resulting data path:
#   fdtd_solver_bd_adapter_0
#     -> field_magnitude_bd_adapter_0 owns Ex/Ey/Bz port-A after solver_done
#     -> field_magnitude_bd_adapter_0 writes |E| or |S| into s_mag_bram port A
#     -> optional s_mag_to_renderer_bridge_0 reads s_mag_bram port B

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

proc ensure_const {name width value} {
    set cell [get_bd_cells -quiet $name]
    if {[llength $cell] == 0} {
        set cell [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 $name]
    }
    set_property -dict [list CONFIG.CONST_WIDTH $width CONFIG.CONST_VAL $value] $cell
    return $cell
}

proc refresh_module_reference_without_pin {cell_name module_name removed_pin} {
    update_compile_order -fileset sources_1

    set refresh_sets [list \
        [get_bd_cells -quiet $cell_name] \
        [get_ips -quiet "*${cell_name}*"] \
        [get_ips -quiet "*${module_name}*"] \
        [list $module_name] \
    ]

    foreach refs $refresh_sets {
        if {[llength $refs] == 0} {
            continue
        }
        puts "INFO: Refreshing module reference for $cell_name using: $refs"
        set status [catch {update_module_reference $refs} result]
        if {$status != 0} {
            puts "INFO: update_module_reference did not accept '$refs': $result"
        } else {
            puts "INFO: update_module_reference result: $result"
        }
    }

    if {[llength [get_bd_pins -quiet "$cell_name/$removed_pin"]] != 0} {
        set available_pins [lsort [get_property NAME [get_bd_pins -quiet "$cell_name/*"]]]
        error "Module reference '$cell_name' still exposes removed pin '$removed_pin'. Available pins: $available_pins. Close/reopen the project or clear the module-reference cache, then rerun this script."
    }
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

proc disconnect_bram_all_pins {bram} {
    foreach pin {addra addrb dina dinb douta doutb ena enb wea web clka clkb} {
        disconnect_pin_if_connected "$bram/$pin"
    }
}

proc disconnect_bram_porta {bram} {
    foreach pin {addra dina douta ena wea clka} {
        disconnect_pin_if_connected "$bram/$pin"
    }
}

proc wire_solver_to_magnitude {prefix} {
    set solver fdtd_solver_bd_adapter_0
    set mag field_magnitude_bd_adapter_0
    foreach pin {addra ena wea dina addrb enb web dinb} {
        connect_bd_net [get_bd_pins $solver/${prefix}_${pin}] \
                       [get_bd_pins $mag/solver_${prefix}_${pin}]
    }
}

proc wire_field_bram_through_magnitude {bram prefix} {
    set solver fdtd_solver_bd_adapter_0
    set mag field_magnitude_bd_adapter_0

    disconnect_bram_all_pins $bram

    connect_bd_net [get_bd_ports clk] [get_bd_pins $bram/clka]
    connect_bd_net [get_bd_ports clk] [get_bd_pins $bram/clkb]

    connect_bd_net [get_bd_pins $mag/${prefix}_addra] [get_bd_pins $bram/addra]
    connect_bd_net [get_bd_pins $mag/${prefix}_ena]   [get_bd_pins $bram/ena]
    connect_bd_net [get_bd_pins $mag/${prefix}_wea]   [get_bd_pins $bram/wea]
    connect_bd_net [get_bd_pins $mag/${prefix}_dina]  [get_bd_pins $bram/dina]
    connect_bd_net [get_bd_pins $bram/douta]          [get_bd_pins $mag/${prefix}_douta]
    connect_bd_net [get_bd_pins $bram/douta]          [get_bd_pins $solver/${prefix}_douta]

    connect_bd_net [get_bd_pins $mag/${prefix}_addrb] [get_bd_pins $bram/addrb]
    connect_bd_net [get_bd_pins $mag/${prefix}_enb]   [get_bd_pins $bram/enb]
    connect_bd_net [get_bd_pins $mag/${prefix}_web]   [get_bd_pins $bram/web]
    connect_bd_net [get_bd_pins $mag/${prefix}_dinb]  [get_bd_pins $bram/dinb]

    if {[llength [get_bd_pins -quiet $solver/${prefix}_doutb]] != 0} {
        connect_bd_net [get_bd_pins $bram/doutb] [get_bd_pins $solver/${prefix}_doutb]
    }
}

proc wire_s_mag_porta_from_magnitude {} {
    set mag field_magnitude_bd_adapter_0

    disconnect_bram_porta s_mag_bram

    connect_bd_net [get_bd_ports clk] [get_bd_pins s_mag_bram/clka]
    connect_bd_net [get_bd_pins $mag/s_mag_addra] [get_bd_pins s_mag_bram/addra]
    connect_bd_net [get_bd_pins $mag/s_mag_ena]   [get_bd_pins s_mag_bram/ena]
    connect_bd_net [get_bd_pins $mag/s_mag_wea]   [get_bd_pins s_mag_bram/wea]
    connect_bd_net [get_bd_pins $mag/s_mag_dina]  [get_bd_pins s_mag_bram/dina]

    if {[llength [get_bd_cells -quiet s_mag_to_renderer_bridge_0]] == 0} {
        foreach pin {addrb dinb doutb enb web clkb} {
            disconnect_pin_if_connected "s_mag_bram/$pin"
        }
        connect_bd_net [get_bd_ports clk] [get_bd_pins s_mag_bram/clkb]
        connect_bd_net [get_bd_pins const_0_16/dout] [get_bd_pins s_mag_bram/addrb]
        connect_bd_net [get_bd_pins const_0_16/dout] [get_bd_pins s_mag_bram/dinb]
        connect_bd_net [get_bd_pins const_1/dout]    [get_bd_pins s_mag_bram/enb]
        connect_bd_net [get_bd_pins const_0_1/dout]  [get_bd_pins s_mag_bram/web]
    } else {
        set clkb_net [get_bd_nets -quiet -of_objects [get_bd_pins s_mag_bram/clkb]]
        if {[llength $clkb_net] == 0} {
            connect_bd_net [get_bd_ports clk] [get_bd_pins s_mag_bram/clkb]
        }
    }
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
set open_project_name [get_property NAME [current_project]]
set main_project_path [file normalize [file join $proj_dir "${open_project_name}.xpr"]]
set bd_file [file join $proj_dir "MVP2_2D_EE_simulation.srcs" "sources_1" "bd" "mvp2_ftdt_bd" "mvp2_ftdt_bd.bd"]
set project_part [get_property PART [current_project]]
set ip_repo_dir [file join $proj_dir ip_repo]
set ip_work_dir [file join $proj_dir .ip_packager_work]
set solver_adapter_file [file join $proj_dir rtl fdtd_solver_bd_adapter.v]
set magnitude_file [file join $proj_dir rtl field_magnitude_bd_adapter.v]

catch {close_design}
close_project

package_project_ip \
    $project_part \
    $ip_repo_dir \
    $ip_work_dir \
    field_magnitude_bd_adapter \
    field_magnitude_bd_adapter \
    [list $magnitude_file] \
    [list] \
    "MVP2 post-solver magnitude adapter: writes approximate |E| or |S| into s_mag_bram."

open_project $main_project_path
set proj_dir [get_property DIRECTORY [current_project]]
set bd_file [file join $proj_dir "MVP2_2D_EE_simulation.srcs" "sources_1" "bd" "mvp2_ftdt_bd" "mvp2_ftdt_bd.bd"]

add_file_if_missing sources_1 $solver_adapter_file Verilog
remove_file_if_present $magnitude_file

set current_ip_repos [get_property ip_repo_paths [current_project]]
if {[lsearch -exact $current_ip_repos $ip_repo_dir] < 0} {
    set_property ip_repo_paths [concat $current_ip_repos [list $ip_repo_dir]] [current_project]
}
update_ip_catalog -rebuild
update_compile_order -fileset sources_1

catch {close_design}
open_bd_design $bd_file

foreach stale_port {mag_busy mag_done e_mag_busy e_mag_done} {
    catch {delete_bd_objs [get_bd_ports -quiet $stale_port]}
}
catch {delete_bd_objs [get_bd_cells -quiet field_magnitude_bd_adapter_0]}
catch {delete_bd_objs [get_bd_cells -quiet fdtd_solver_bd_adapter_0]}

ensure_const const_1 1 1
ensure_const const_0_1 1 0
ensure_const const_0_16 16 0

set solver_cell [create_bd_cell -type module -reference fdtd_solver_bd_adapter fdtd_solver_bd_adapter_0]
refresh_module_reference_without_pin fdtd_solver_bd_adapter_0 fdtd_solver_bd_adapter mag_mode
set mag_cell [create_bd_cell -type ip -vlnv user.org:user:field_magnitude_bd_adapter:1.0 field_magnitude_bd_adapter_0]

ensure_port rst I -type rst
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports rst]
connect_bd_net [get_bd_ports clk] [get_bd_pins fdtd_solver_bd_adapter_0/clk]
connect_bd_net [get_bd_ports clk] [get_bd_pins field_magnitude_bd_adapter_0/clk]
connect_bd_net [get_bd_ports rst] [get_bd_pins fdtd_solver_bd_adapter_0/rst]
connect_bd_net [get_bd_ports rst] [get_bd_pins field_magnitude_bd_adapter_0/rst]

ensure_port solver_enable I
ensure_port mag_mode I
ensure_port solver_done O
ensure_port source_latched O
ensure_port solver_checksum O -from 31 -to 0
ensure_port mag_busy O
ensure_port mag_done O

connect_bd_net [get_bd_ports solver_enable] [get_bd_pins fdtd_solver_bd_adapter_0/solver_enable]
connect_bd_net [get_bd_ports solver_done] [get_bd_pins fdtd_solver_bd_adapter_0/solver_done]
connect_bd_net [get_bd_pins fdtd_solver_bd_adapter_0/solver_done] [get_bd_pins field_magnitude_bd_adapter_0/start]
connect_bd_net [get_bd_ports source_latched] [get_bd_pins fdtd_solver_bd_adapter_0/source_latched]
connect_bd_net [get_bd_ports solver_checksum] [get_bd_pins fdtd_solver_bd_adapter_0/solver_checksum]
connect_bd_net [get_bd_ports mag_mode] [get_bd_pins field_magnitude_bd_adapter_0/mag_mode]
connect_bd_net [get_bd_ports mag_busy] [get_bd_pins field_magnitude_bd_adapter_0/busy]
connect_bd_net [get_bd_ports mag_done] [get_bd_pins field_magnitude_bd_adapter_0/done]

connect_bd_net [get_bd_pins cordic_source_adapter_0/source_q313] \
               [get_bd_pins fdtd_solver_bd_adapter_0/source_q313]
connect_bd_net [get_bd_pins cordic_source_adapter_0/source_valid] \
               [get_bd_pins fdtd_solver_bd_adapter_0/source_valid]

foreach prefix {ey ex bz} {
    wire_solver_to_magnitude $prefix
}

wire_field_bram_through_magnitude ey_bram ey
wire_field_bram_through_magnitude ex_bram ex
wire_field_bram_through_magnitude bz_bram bz
wire_s_mag_porta_from_magnitude

if {[llength [get_bd_cells -quiet s_mag_to_renderer_bridge_0]] != 0} {
    disconnect_pin_if_connected s_mag_to_renderer_bridge_0/start
    connect_bd_net [get_bd_pins field_magnitude_bd_adapter_0/done] \
                   [get_bd_pins s_mag_to_renderer_bridge_0/start]
}

set_property location {3.5 680 90} [get_bd_cells field_magnitude_bd_adapter_0]
set_property location {3 455 85} [get_bd_cells fdtd_solver_bd_adapter_0]

regenerate_bd_layout -routing
validate_bd_design
save_bd_design

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

set preserve_xdc [file join $proj_dir solver_preserve.xdc]
set preserve_fp [open $preserve_xdc w]
puts $preserve_fp {
# Preservation constraints intentionally disabled after renderer/magnitude integration.
# Keep this file in constrs_1 so old run configurations still have a stable constraint set.
}
close $preserve_fp
if {[llength [get_files -quiet $preserve_xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $preserve_xdc
}

set report_dir [file join $proj_dir reports_field_magnitude_ip]
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
    report_utilization -file [file join $report_dir utilization_synth_field_magnitude_ip.rpt]
    report_timing_summary -max_paths 10 -file [file join $report_dir timing_synth_field_magnitude_ip.rpt]
    report_drc -file [file join $report_dir drc_synth_field_magnitude_ip.rpt]
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
    report_utilization -file [file join $report_dir utilization_impl_field_magnitude_ip.rpt]
    report_timing_summary -max_paths 10 -file [file join $report_dir timing_impl_field_magnitude_ip.rpt]
    report_route_status -file [file join $report_dir route_status_field_magnitude_ip.rpt]
    report_drc -file [file join $report_dir drc_impl_field_magnitude_ip.rpt]
    close_design
}

puts "INFO: Field magnitude split completed."
puts "INFO: fdtd_solver_bd_adapter_0 now owns solver update only."
puts "INFO: field_magnitude_bd_adapter_0 writes s_mag_bram port A after solver_done."
puts "INFO: mag_mode=0 stores |E| approximation; mag_mode=1 stores |S| approximation."
puts "INFO: Reports directory: $report_dir"

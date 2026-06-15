# Clean MVP2 Vivado project down to one canonical block design.
#
# Run in Vivado Tcl Console:
#   source E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/scripts/cleanup_single_bd_project.tcl
#
# This removes old bring-up/test source files and verifies that the single
# block design contains the active MVP2 architecture.

proc cleanup_getenv_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

proc cleanup_remove_file_from_project {path_value} {
    set path_value [file normalize $path_value]
    set file_obj [get_files -quiet $path_value]
    if {[llength $file_obj] != 0} {
        puts "INFO: Removing stale project source: $path_value"
        remove_files $file_obj
    }
    if {[file exists $path_value]} {
        puts "INFO: Deleting stale source file: $path_value"
        file delete -force $path_value
    }
}

set default_project "E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr"
set project_path [file normalize [cleanup_getenv_or_default VIVADO_PROJECT $default_project]]

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

foreach stale_file [list \
    [file join $proj_dir rtl bram_test_adapter.v] \
    [file join $proj_dir rtl cordic_source_adapter.sv] \
    [file join $proj_dir "MVP2_2D_EE_simulation.srcs" "sources_1" "new" "cordic_source_adapter.sv"] \
] {
    cleanup_remove_file_from_project $stale_file
}

catch {close_design}
open_bd_design $bd_file

foreach stale_cell {bram_test_adapter_0 ey_adj_bram bz_adj_bram} {
    set cell [get_bd_cells -quiet $stale_cell]
    if {[llength $cell] != 0} {
        puts "INFO: Removing stale BD cell: $stale_cell"
        delete_bd_objs $cell
    }
}

set required_cells {
    cordic_0
    cordic_source_adapter_0
    fdtd_solver_bd_adapter_0
    ey_bram
    ex_bram
    bz_bram
    s_mag_bram
}
foreach cell_name $required_cells {
    if {[llength [get_bd_cells -quiet $cell_name]] == 0} {
        error "Required BD cell is missing: $cell_name"
    }
}

set unexpected_test_cells [get_bd_cells -quiet -hier -filter {NAME =~ *test* || VLNV =~ *bram_test*}]
if {[llength $unexpected_test_cells] != 0} {
    error "Unexpected test cells remain in BD: $unexpected_test_cells"
}

validate_bd_design
save_bd_design

generate_target all [get_files $bd_file]
set wrapper_file [make_wrapper -files [get_files $bd_file] -top]
if {[file exists $wrapper_file] && [llength [get_files -quiet $wrapper_file]] == 0} {
    add_files -norecurse $wrapper_file
}

set_property top mvp2_ftdt_bd_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "INFO: MVP2 project cleanup complete."
puts "INFO: Single active BD: $bd_file"
puts "INFO: Active BD cells: [lsort [get_property NAME [get_bd_cells]]]"
puts "INFO: Stale BRAM test and duplicate CORDIC SystemVerilog sources are removed."

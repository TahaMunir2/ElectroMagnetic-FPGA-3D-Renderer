# Run Taha's standalone renderer ray_unit regression in Vivado XSim.
#
# This is intentionally not connected to the MVP2 block design. It creates/uses
# a dedicated simulation fileset, compiles the renderer RTL plus the small
# 4x4 ray_unit testbench, and runs the same Python-generated vectors that were
# used in the branch handoff.
#
# Run in Vivado Tcl Console:
#   source E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/scripts/run_renderer_ray_unit_sim.tcl
#
# Optional environment variables:
#   VIVADO_PROJECT=E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr
#   RENDERER_STANDALONE_ROOT=E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/renderer_standalone

proc getenv_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

proc add_sim_sv_file {simset_name path_value} {
    set path_value [file normalize $path_value]
    if {![file exists $path_value]} {
        error "Missing renderer simulation source: $path_value"
    }
    if {[llength [get_files -quiet -of_objects [get_filesets $simset_name] $path_value]] == 0} {
        add_files -norecurse -fileset $simset_name $path_value
    }
    set_property file_type SystemVerilog [get_files -quiet $path_value]
}

set default_project "E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr"
set project_path [file normalize [getenv_or_default VIVADO_PROJECT $default_project]]

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
set default_renderer_root [file join $proj_dir renderer_standalone]
set renderer_root [file normalize [getenv_or_default RENDERER_STANDALONE_ROOT $default_renderer_root]]
set renderer_hdl [file join $renderer_root hdl]
set renderer_tb  [file join $renderer_root tb]
set heightmap_path [file normalize [file join $renderer_tb heightmap.hex]]
set vectors_path [file normalize [file join $renderer_tb ray_unit_vectors.hex]]

foreach required_file [list \
    [file join $renderer_hdl ray_gen.sv] \
    [file join $renderer_hdl march_step.sv] \
    [file join $renderer_hdl marcher.sv] \
    [file join $renderer_hdl normal.sv] \
    [file join $renderer_hdl shader.sv] \
    [file join $renderer_hdl ray_unit.sv] \
    [file join $renderer_tb tb_ray_unit_vivado.sv] \
    [file join $renderer_tb heightmap.hex] \
    [file join $renderer_tb ray_unit_vectors.hex] \
] {
    if {![file exists $required_file]} {
        error "Missing standalone renderer test file: $required_file"
    }
}

set simset_name renderer_ray_unit_sim
if {[llength [get_filesets -quiet $simset_name]] == 0} {
    create_fileset -simset $simset_name
}

foreach src_file [list \
    [file join $renderer_hdl ray_gen.sv] \
    [file join $renderer_hdl march_step.sv] \
    [file join $renderer_hdl marcher.sv] \
    [file join $renderer_hdl normal.sv] \
    [file join $renderer_hdl shader.sv] \
    [file join $renderer_hdl ray_unit.sv] \
    [file join $renderer_tb tb_ray_unit_vivado.sv] \
] {
    add_sim_sv_file $simset_name $src_file
}

set_property top tb_ray_unit [get_filesets $simset_name]
set_property top_lib xil_defaultlib [get_filesets $simset_name]
set_property -name {xsim.elaborate.debug_level} -value {typical} -objects [get_filesets $simset_name]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets $simset_name]
set_property -name {xsim.simulate.xsim.more_options} -value "+HEIGHTMAP=$heightmap_path +VECTORS=$vectors_path" -objects [get_filesets $simset_name]

update_compile_order -fileset $simset_name

set xsim_run_dir [file join $proj_dir "[get_property NAME [current_project]].sim" $simset_name behav xsim]
file mkdir $xsim_run_dir
file copy -force $heightmap_path [file join $xsim_run_dir heightmap.hex]
file copy -force $vectors_path [file join $xsim_run_dir ray_unit_vectors.hex]

catch {close_sim}
launch_simulation -simset $simset_name -mode behavioral
close_sim

puts "INFO: Standalone renderer ray_unit XSim regression completed."
puts "INFO: Renderer root: $renderer_root"
puts "INFO: Expected pass line: ray_unit TB: tested=16  pass=16  fail=0"

# Synthesize Taha's standalone renderer ray_unit as an out-of-context module.
#
# This does not connect the renderer to the MVP2 block design. It creates a
# separate source fileset and synthesis run so we can estimate the renderer
# core logic cost independently from the heightmap BRAM replication/buffer
# manager that still needs to be built.
#
# Run in Vivado Tcl Console:
#   set ::env(VIVADO_JOBS) 4
#   source E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/scripts/synth_renderer_ray_unit_ooc.tcl
#
# Optional:
#   RENDERER_STANDALONE_ROOT=E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/renderer_standalone

proc getenv_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

proc add_src_sv_file {fileset_name path_value} {
    set path_value [file normalize $path_value]
    if {![file exists $path_value]} {
        error "Missing renderer synthesis source: $path_value"
    }
    if {[llength [get_files -quiet -of_objects [get_filesets $fileset_name] $path_value]] == 0} {
        add_files -norecurse -fileset $fileset_name $path_value
    }
    set_property file_type SystemVerilog [get_files -quiet $path_value]
}

set default_project "E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr"
set project_path [file normalize [getenv_or_default VIVADO_PROJECT $default_project]]
set jobs [getenv_or_default VIVADO_JOBS "4"]

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
set part_name [get_property PART [current_project]]
set renderer_root [file normalize [getenv_or_default RENDERER_STANDALONE_ROOT [file join $proj_dir renderer_standalone]]]
set renderer_hdl [file join $renderer_root hdl]
set report_dir [file join $proj_dir reports_renderer]
file mkdir $report_dir

set srcset_name renderer_ray_unit_src
if {[llength [get_filesets -quiet $srcset_name]] == 0} {
    create_fileset -srcset $srcset_name
}

foreach src_file [list \
    [file join $renderer_hdl ray_gen.sv] \
    [file join $renderer_hdl march_step.sv] \
    [file join $renderer_hdl marcher.sv] \
    [file join $renderer_hdl normal.sv] \
    [file join $renderer_hdl shader.sv] \
    [file join $renderer_hdl ray_unit.sv] \
    [file join $renderer_hdl ray_unit_synth_wrapper.sv] \
] {
    add_src_sv_file $srcset_name $src_file
}

set_property top ray_unit_synth_wrapper [get_filesets $srcset_name]
update_compile_order -fileset $srcset_name

set run_name renderer_ray_unit_synth_1
if {[llength [get_runs -quiet $run_name]] != 0} {
    delete_runs $run_name
}

create_run $run_name \
    -flow {Vivado Synthesis 2023} \
    -strategy {Vivado Synthesis Defaults} \
    -part $part_name \
    -srcset $srcset_name \
    -constrset constrs_1

set_property "STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS" {-mode out_of_context} [get_runs $run_name]

reset_run $run_name
launch_runs $run_name -jobs $jobs
wait_on_run $run_name

set run_status [get_property STATUS [get_runs $run_name]]
puts "INFO: $run_name status: $run_status"

if {![string match {*Complete*} $run_status]} {
    error "Renderer synthesis did not complete: $run_status"
}

open_run $run_name -name renderer_ray_unit_synth_open

report_utilization -file [file join $report_dir renderer_ray_unit_ooc_utilization.rpt]
report_timing_summary -max_paths 10 -file [file join $report_dir renderer_ray_unit_ooc_timing.rpt]
check_timing -file [file join $report_dir renderer_ray_unit_ooc_check_timing.rpt]
write_checkpoint -force [file join $report_dir renderer_ray_unit_ooc.dcp]

puts "INFO: Standalone renderer ray_unit out-of-context synthesis complete."
puts "INFO: Reports:"
puts "INFO:   [file join $report_dir renderer_ray_unit_ooc_utilization.rpt]"
puts "INFO:   [file join $report_dir renderer_ray_unit_ooc_timing.rpt]"
puts "INFO:   [file join $report_dir renderer_ray_unit_ooc_check_timing.rpt]"
puts "INFO: Note: this is only the renderer core. It excludes replicated heightmap BRAMs, buffer manager, AXI-Lite, and AXI-Stream output."

# Generate routed reports for the solver-integrated MVP2 block design.
#
# Run after impl_1 completes:
#   source E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/scripts/report_solver_integrated_impl.tcl

proc getenv_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

set default_project "E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr"
set project_path [file normalize [getenv_or_default VIVADO_PROJECT $default_project]]

if {[llength [get_projects -quiet]] == 0} {
    open_project $project_path
}

set proj_dir [get_property DIRECTORY [current_project]]
set report_dir [file join $proj_dir reports_solver_integrated]
file mkdir $report_dir

set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: impl_1 status: $impl_status"
if {[string first "route_design Complete" $impl_status] < 0} {
    puts "WARNING: impl_1 is not routed yet. Reports may be stale or unavailable."
}

catch {close_design}
open_run impl_1

report_utilization -file [file join $report_dir utilization_impl_solver.rpt]
report_timing_summary -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_impl_solver.rpt]
report_route_status -file [file join $report_dir route_status_solver.rpt]
report_drc -file [file join $report_dir drc_impl_solver.rpt]

puts "INFO: Reports written to: $report_dir"
puts "INFO: Check utilization_impl_solver.rpt for nonzero Block RAM Tile usage."
puts "INFO: Check timing_impl_solver.rpt for WNS/TNS and route_status_solver.rpt for routing errors."

set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set project_path [file normalize [file join $repo_dir D4S48 vivado_project_d4s48 d4s48_renderer.xpr]]
set report_dir [file normalize [file join $repo_dir D4S48 vivado_project_d4s48 reports_lowdsp_impl]]

if {![file exists $project_path]} {
    error "D4S48 project not found: $project_path"
}

open_project $project_path

if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
    [get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    reset_run synth_1
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
}

reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "impl_1 did not complete"
}
set impl_status [get_property STATUS [get_runs impl_1]]
if {$impl_status ne "route_design Complete!" &&
    $impl_status ne "route_design Complete, Failed Timing!"} {
    error "impl_1 status: $impl_status"
}

open_run impl_1
file mkdir $report_dir

set util_report [file join $report_dir utilization_routed.rpt]
set timing_report [file join $report_dir timing_summary_routed.rpt]

report_utilization -file $util_report
report_timing_summary -file $timing_report

puts "Wrote routed utilization report: $util_report"
puts "Wrote routed timing report: $timing_report"

set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set project_path [file normalize [file join $repo_dir D4S48 vivado_project_d4s48 d4s48_renderer.xpr]]
set report_dir [file normalize [file join $repo_dir D4S48 vivado_project_d4s48 reports_lowdsp_synth]]

if {![file exists $project_path]} {
    error "D4S48 project not found: $project_path"
}

open_project $project_path

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synth_1 did not complete"
}
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "synth_1 status: [get_property STATUS [get_runs synth_1]]"
}

open_run synth_1
file mkdir $report_dir

set util_report [file join $report_dir utilization_synth.rpt]
set timing_report [file join $report_dir timing_summary_synth.rpt]

report_utilization -file $util_report
report_timing_summary -file $timing_report

puts "Wrote utilization report: $util_report"
puts "Wrote timing report: $timing_report"

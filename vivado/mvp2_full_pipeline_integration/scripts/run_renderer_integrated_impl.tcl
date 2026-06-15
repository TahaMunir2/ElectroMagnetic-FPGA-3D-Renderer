# Run implementation for the MVP2 design after renderer integration.
#
# Optional environment variables:
#   VIVADO_PROJECT=E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr
#   VIVADO_JOBS=4

proc getenv_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
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
set ip_repo_dir [file join $proj_dir ip_repo]
set report_dir [file join $proj_dir reports_renderer_integrated]
file mkdir $report_dir

set current_ip_repos [get_property ip_repo_paths [current_project]]
if {[lsearch -exact $current_ip_repos $ip_repo_dir] < 0} {
    set_property ip_repo_paths [concat $current_ip_repos [list $ip_repo_dir]] [current_project]
}
update_ip_catalog -rebuild

set ip_status_file [file join $report_dir ip_status_before_impl.rpt]
report_ip_status -file $ip_status_file
set locked_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
if {[llength $locked_ips] != 0} {
    puts "INFO: Attempting to upgrade locked IPs: $locked_ips"
    upgrade_ip $locked_ips
    generate_target all [get_files [file join $proj_dir "MVP2_2D_EE_simulation.srcs" "sources_1" "bd" "mvp2_ftdt_bd" "mvp2_ftdt_bd.bd"]]
}

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

puts "INFO: Renderer-integrated implementation reports written to $report_dir"

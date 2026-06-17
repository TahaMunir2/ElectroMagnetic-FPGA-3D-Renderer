set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set project_path [file normalize [file join $repo_dir D4S48 vivado_project_d4s48 d4s48_renderer.xpr]]
set bit_path [file normalize [file join $repo_dir D4S48 vivado_project_d4s48 d4s48_renderer.runs impl_1 ray_unit_hdmi_top_d4s48.bit]]

if {![file exists $project_path]} {
    error "D4S48 project not found: $project_path"
}

open_project $project_path

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
if {$impl_status ne "write_bitstream Complete!"} {
    error "impl_1 status: $impl_status"
}

if {![file exists $bit_path]} {
    error "Expected bitstream was not written: $bit_path"
}

puts "Wrote bitstream: $bit_path"

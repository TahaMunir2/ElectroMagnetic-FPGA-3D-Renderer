# Open the existing MVP2_fdtd_hdmi project and run synth -> impl -> bitstream,
# emitting utilization / timing / DRC reports.
set proj_dir "E:/Vivado/Projects/desperate_yi/MVP2_fdtd_contour_128_cb"
set jobs 4
if {[info exists ::env(VIVADO_JOBS)]} { set jobs $::env(VIVADO_JOBS) }

open_project [file join $proj_dir MVP2_fdtd_contour_128_cb.xpr]
set rdir [file join $proj_dir reports]
file mkdir $rdir

reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set st [get_property STATUS [get_runs synth_1]]
puts "INFO: synth_1 status: $st"
if {[string first "Complete" $st] < 0} { error "SYNTH FAILED: $st" }

open_run synth_1
report_utilization    -file [file join $rdir util_synth.rpt]
report_timing_summary -max_paths 5 -file [file join $rdir timing_synth.rpt]
close_design
puts "INFO: synthesis complete; reports in $rdir"

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set st [get_property STATUS [get_runs impl_1]]
puts "INFO: impl_1 status: $st"

open_run impl_1
report_utilization    -file [file join $rdir util_impl.rpt]
report_timing_summary -max_paths 10 -file [file join $rdir timing_impl.rpt]
report_drc            -file [file join $rdir drc_impl.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "INFO: post-route WNS = $wns"
close_design

set bit [file join $proj_dir MVP2_fdtd_contour_128_cb.runs impl_1 fdtd_hdmi_bd_wrapper.bit]
if {[file exists $bit]} {
    file copy -force $bit [file join $proj_dir fdtd_hdmi.bit]
    puts "INFO: bitstream -> [file join $proj_dir fdtd_hdmi.bit]"
} else {
    puts "WARNING: bitstream not found at $bit"
}
puts "INFO: run_build.tcl done."

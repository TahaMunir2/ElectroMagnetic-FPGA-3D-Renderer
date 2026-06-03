# Build a Vivado project through bitstream generation and write basic reports.
#
# Usage:
#   vivado -mode batch -source scripts/build_vivado_bitstream.tcl -tclargs \
#       -project design2/vivado_project_design2/design2_renderer.xpr
#
# Optional:
#   -jobs <n>
#   -reports_dir <path>

set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set project_path [file normalize [file join $repo_dir design2 vivado_project_design2 design2_renderer.xpr]]
set jobs 8
set reports_dir ""

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    if {$arg eq "-project"} {
        incr i
        if {$i >= [llength $argv]} {
            error "-project requires a path argument"
        }
        set project_path [file normalize [lindex $argv $i]]
    } elseif {$arg eq "-jobs"} {
        incr i
        if {$i >= [llength $argv]} {
            error "-jobs requires an integer argument"
        }
        set jobs [lindex $argv $i]
    } elseif {$arg eq "-reports_dir"} {
        incr i
        if {$i >= [llength $argv]} {
            error "-reports_dir requires a path argument"
        }
        set reports_dir [file normalize [lindex $argv $i]]
    } else {
        error "Unknown argument '$arg'. Supported arguments: -project <xpr>, -jobs <n>, -reports_dir <path>"
    }
}

if {![file exists $project_path]} {
    error "Vivado project not found: $project_path"
}

if {$reports_dir eq ""} {
    set reports_dir [file normalize [file join [file dirname $project_path] reports]]
}
file mkdir $reports_dir

open_project $project_path

set top_name [get_property top [get_filesets sources_1]]
puts "PROJECT=$project_path"
puts "TOP=$top_name"
puts "REPORTS_DIR=$reports_dir"

reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
if {$synth_status ne "synth_design Complete!"} {
    close_project
    exit 1
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"
if {$impl_status ne "write_bitstream Complete!"} {
    close_project
    exit 1
}

open_run impl_1
report_timing_summary -file [file join $reports_dir timing_summary.rpt] -warn_on_violation
report_utilization -file [file join $reports_dir utilization.rpt]

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bitstream [file normalize [file join $impl_dir "${top_name}.bit"]]
puts "BITSTREAM=$bitstream"

close_project
exit 0

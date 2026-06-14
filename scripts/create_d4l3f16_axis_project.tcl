# Create a Vivado synthesis project for the three-lane, 16-cycle folded
# Design4 framebuffer-stream renderer.
#
# This project validates/synthesizes the render-to-framebuffer stream core.  It
# is not a board bitstream by itself; connect the stream to AXI VDMA S2MM and
# use a separate VDMA MM2S/video-out path for HDMI scan-out.
#
# Usage from the repo root:
#   vivado -mode batch -source scripts/create_d4l3f16_axis_project.tcl
#
# Optional:
#   -force
#   -project_dir <path>

set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set project_name d4l3f16_axis
set project_dir [file normalize [file join $repo_dir D4L3F16 vivado_project_d4l3f16_axis]]
set part_name xc7z020clg400-1
set top_name ray_unit4_lanes3_f16_axis
set force_project 0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    if {$arg eq "-force"} {
        set force_project 1
    } elseif {$arg eq "-project_dir"} {
        incr i
        if {$i >= [llength $argv]} {
            error "-project_dir requires a path argument"
        }
        set project_dir [file normalize [lindex $argv $i]]
    } else {
        error "Unknown argument '$arg'. Supported arguments: -force, -project_dir <path>"
    }
}

proc checked_file {path} {
    set norm_path [file normalize $path]
    if {![file exists $norm_path]} {
        error "Required file not found: $norm_path"
    }
    return $norm_path
}

if {[file exists [file join $project_dir ${project_name}.xpr]] && !$force_project} {
    error "Project already exists: [file join $project_dir ${project_name}.xpr]. Re-run with -tclargs -force to recreate it."
}

if {$force_project} {
    create_project -force $project_name $project_dir -part $part_name
} else {
    create_project $project_name $project_dir -part $part_name
}

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set pynq_boards [get_board_parts -quiet *pynq-z1*]
if {[llength $pynq_boards] > 0} {
    set_property board_part [lindex $pynq_boards 0] [current_project]
}

set source_files [list \
    [checked_file [file join $repo_dir D4S48 ray_gen.sv]] \
    [checked_file [file join $repo_dir D4S48 march_step4.sv]] \
    [checked_file [file join $repo_dir D4L3F16 marcher16.sv]] \
    [checked_file [file join $repo_dir D4S48 normal4.sv]] \
    [checked_file [file join $repo_dir D4S48 shader.sv]] \
    [checked_file [file join $repo_dir D4L3F16 ray_unit4_f16.sv]] \
    [checked_file [file join $repo_dir wrapper heightmap_bram.sv]] \
    [checked_file [file join $repo_dir D4L3F16 ray_unit4_lanes3_f16_axis.sv]] \
]

add_files -norecurse -fileset sources_1 $source_files
foreach src $source_files {
    set_property file_type SystemVerilog [get_files $src]
}

add_files -norecurse -fileset constrs_1 \
    [checked_file [file join $repo_dir D4L3F16 d4l3f16_axis_ooc.xdc]]

set_property top $top_name [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Created D4L3F16 AXIS Vivado project:"
puts "  [file join $project_dir ${project_name}.xpr]"
puts ""
puts "Top:"
puts "  $top_name"
puts ""
puts "Next:"
puts "  Run synthesis for area/timing, or package the top as the S2MM stream source for AXI VDMA."

# Create a standalone Vivado project from the source-only D4S48 low-DSP package.
#
# Usage from the repo root:
#   vivado -mode batch -source packages/d4s48_lowdsp/scripts/create_project.tcl -tclargs -force
#
# Optional:
#   -force
#   -project_dir <path>
#   -ip_repo <path-to-Digilent-vivado-library/ip>

set pkg_dir [file normalize [file join [file dirname [info script]] ..]]
set project_name d4s48_lowdsp_renderer
set project_dir [file normalize [file join $pkg_dir vivado_project_d4s48_lowdsp]]
set part_name xc7z020clg400-1
set top_name ray_unit_hdmi_top_d4s48
set force_project 0
set explicit_ip_repos [list]

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
    } elseif {$arg eq "-ip_repo"} {
        incr i
        if {$i >= [llength $argv]} {
            error "-ip_repo requires a path argument"
        }
        lappend explicit_ip_repos [file normalize [lindex $argv $i]]
    } else {
        error "Unknown argument '$arg'. Supported arguments: -force, -project_dir <path>, -ip_repo <path>"
    }
}

proc first_ipdef {pattern} {
    set defs [get_ipdefs $pattern]
    if {[llength $defs] == 0} {
        set defs [get_ipdefs -all $pattern]
    }
    if {[llength $defs] == 0} {
        error "Could not find IP definition matching '$pattern'"
    }
    return [lindex $defs end]
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

set candidate_ip_repos [list]
foreach path $explicit_ip_repos {
    lappend candidate_ip_repos $path
}
foreach path [list \
    [file join $pkg_dir ip] \
    [file join $pkg_dir .. ip] \
    [file join $pkg_dir .. .. ip] \
    [file join $pkg_dir .. .. .. vivado-library-master ip] \
    D:/ic/vivado-library-master/ip \
    C:/Xilinx/vivado-library-master/ip \
] {
    lappend candidate_ip_repos [file normalize $path]
}

set ip_repos [list]
foreach path $candidate_ip_repos {
    if {[file exists [file join $path rgb2dvi component.xml]]} {
        lappend ip_repos $path
    }
}
if {[llength $ip_repos] > 0} {
    set_property ip_repo_paths $ip_repos [current_project]
    update_ip_catalog
}

set pynq_boards [get_board_parts -quiet *pynq-z1*]
if {[llength $pynq_boards] > 0} {
    set_property board_part [lindex $pynq_boards 0] [current_project]
}

set source_files [list \
    [checked_file [file join $pkg_dir src ray_unit_hdmi_top_d4s48.sv]] \
    [checked_file [file join $pkg_dir src video_timing_640x480.sv]] \
    [checked_file [file join $pkg_dir src heightmap_bram.sv]] \
    [checked_file [file join $pkg_dir src ray_gen.sv]] \
    [checked_file [file join $pkg_dir src march_step4.sv]] \
    [checked_file [file join $pkg_dir src marcher4.sv]] \
    [checked_file [file join $pkg_dir src normal4.sv]] \
    [checked_file [file join $pkg_dir src shader.sv]] \
    [checked_file [file join $pkg_dir src ray_unit4.sv]] \
]

add_files -norecurse -fileset sources_1 $source_files
foreach src $source_files {
    set_property file_type SystemVerilog [get_files $src]
}

add_files -norecurse -fileset constrs_1 \
    [checked_file [file join $pkg_dir constraints pynq_z1_hdmi_d4s48.xdc]]

create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_1
set_property -dict [list \
    CONFIG.PRIMITIVE {MMCM} \
    CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.NUM_OUT_CLKS {3} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.CLKOUT3_USED {true} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
] [get_ips clk_wiz_1]

set rgb2dvi_vlnv [first_ipdef "*:rgb2dvi:*"]
set rgb2dvi_parts [split $rgb2dvi_vlnv ":"]
create_ip \
    -vendor  [lindex $rgb2dvi_parts 0] \
    -library [lindex $rgb2dvi_parts 1] \
    -name    [lindex $rgb2dvi_parts 2] \
    -version [lindex $rgb2dvi_parts 3] \
    -module_name rgb2dvi_0
catch {
    set_property -dict [list \
        CONFIG.kGenerateSerialClk {false} \
        CONFIG.kRstActiveHigh {true} \
        CONFIG.kClkRange {2} \
    ] [get_ips rgb2dvi_0]
}

generate_target all [get_ips clk_wiz_1]
generate_target all [get_ips rgb2dvi_0]
export_ip_user_files -of_objects [get_ips clk_wiz_1] -no_script -sync -force -quiet
export_ip_user_files -of_objects [get_ips rgb2dvi_0] -no_script -sync -force -quiet

set_property top $top_name [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Created D4S48 low-DSP Vivado project:"
puts "  [file join $project_dir ${project_name}.xpr]"
puts ""
puts "Top:"
puts "  $top_name"

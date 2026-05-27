proc getenv_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

proc bd_obj {name} {
    set obj [get_bd_pins -quiet $name]
    if {[llength $obj] == 0} {
        if {[string match "/*" $name]} {
            set obj [get_bd_ports -quiet $name]
        } else {
            set obj [get_bd_ports -quiet /$name]
            if {[llength $obj] == 0} {
                set obj [get_bd_ports -quiet $name]
            }
        }
    }
    if {[llength $obj] == 0} {
        error "Missing BD pin/port: $name"
    }
    return [lindex $obj 0]
}

proc bd_net_of {name} {
    set obj [bd_obj $name]
    set net [get_bd_nets -quiet -of_objects $obj]
    if {[llength $net] == 0} {
        error "BD pin/port is not connected: $name"
    }
    return [lindex $net 0]
}

proc assert_same_net {left right} {
    set left_net [bd_net_of $left]
    set right_net [bd_net_of $right]
    if {[string compare $left_net $right_net] != 0} {
        error "Expected $left and $right to share one net, got '$left_net' and '$right_net'"
    }
    puts "OK: $left <-> $right"
}

proc assert_missing_pin {pin_name} {
    if {[llength [get_bd_pins -quiet $pin_name]] != 0} {
        error "Unexpected stale pin still exists: $pin_name"
    }
    puts "OK: stale pin absent: $pin_name"
}

proc assert_file_contains {path pattern description} {
    if {![file exists $path]} {
        error "Missing generated file for check: $path"
    }
    set fp [open $path r]
    set text [read $fp]
    close $fp
    if {![regexp $pattern $text]} {
        error "Generated Verilog check failed: $description"
    }
    puts "OK: $description"
}

set default_project "E:/Vivado/Projects/desperate_yi/MVP2_2D_EE_simulation/MVP2_2D_EE_simulation.xpr"
set project_path [file normalize [getenv_or_default VIVADO_PROJECT $default_project]]

if {[llength [get_projects -quiet]] == 0} {
    open_project $project_path
}

set proj_dir [get_property DIRECTORY [current_project]]
set bd_file [file join $proj_dir "MVP2_2D_EE_simulation.srcs" "sources_1" "bd" "mvp2_ftdt_bd" "mvp2_ftdt_bd.bd"]
set bd_verilog [file join $proj_dir "MVP2_2D_EE_simulation.gen" "sources_1" "bd" "mvp2_ftdt_bd" "synth" "mvp2_ftdt_bd.v"]

open_bd_design $bd_file

foreach cell {
    fdtd_solver_bd_adapter_0
    field_magnitude_bd_adapter_0
    cordic_source_adapter_0
    cordic_0
    ey_bram
    ex_bram
    bz_bram
    s_mag_bram
} {
    if {[llength [get_bd_cells -quiet $cell]] == 0} {
        error "Missing expected BD cell: $cell"
    }
    puts "OK: cell exists: $cell"
}

foreach pin {
    fdtd_solver_bd_adapter_0/mag_mode
    fdtd_solver_bd_adapter_0/mag_busy
    fdtd_solver_bd_adapter_0/mag_done
    fdtd_solver_bd_adapter_0/s_mag_addra
    fdtd_solver_bd_adapter_0/s_mag_dina
    fdtd_solver_bd_adapter_0/s_mag_ena
    fdtd_solver_bd_adapter_0/s_mag_wea
} {
    assert_missing_pin $pin
}

assert_same_net fdtd_solver_bd_adapter_0/solver_done field_magnitude_bd_adapter_0/start
assert_file_contains $bd_verilog {assign[ \t]+mag_done[ \t]*=[ \t]*field_magnitude_bd_adapter_0_done} "top mag_done is driven by field magnitude IP"
assert_file_contains $bd_verilog {assign[ \t]+mag_busy[ \t]*=[ \t]*field_magnitude_bd_adapter_0_busy} "top mag_busy is driven by field magnitude IP"
assert_file_contains $bd_verilog {assign[ \t]+mag_mode_[0-9A-Za-z_]*[ \t]*=[ \t]*mag_mode} "top mag_mode drives field magnitude IP"

foreach field {ey ex bz} {
    foreach pin {addra addrb dina dinb ena enb wea web} {
        assert_same_net fdtd_solver_bd_adapter_0/${field}_${pin} field_magnitude_bd_adapter_0/solver_${field}_${pin}
        assert_same_net field_magnitude_bd_adapter_0/${field}_${pin} ${field}_bram/${pin}
    }
    assert_same_net ${field}_bram/douta field_magnitude_bd_adapter_0/${field}_douta
}

foreach pin {addra dina ena wea} {
    assert_same_net field_magnitude_bd_adapter_0/s_mag_${pin} s_mag_bram/${pin}
}

if {[llength [get_bd_cells -quiet s_mag_to_renderer_bridge_0]] != 0} {
    assert_same_net field_magnitude_bd_adapter_0/done s_mag_to_renderer_bridge_0/start
    assert_same_net s_mag_bram/addrb s_mag_to_renderer_bridge_0/s_mag_addr
    assert_same_net s_mag_bram/enb s_mag_to_renderer_bridge_0/s_mag_en
    assert_same_net s_mag_bram/web s_mag_to_renderer_bridge_0/s_mag_we
    assert_same_net s_mag_bram/dinb s_mag_to_renderer_bridge_0/s_mag_din
    assert_same_net s_mag_bram/doutb s_mag_to_renderer_bridge_0/s_mag_dout
}

validate_bd_design
puts "OK: MVP2 block design connectivity smoke test passed."

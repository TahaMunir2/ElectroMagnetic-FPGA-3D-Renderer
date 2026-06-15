# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "GRID_N" -parent ${Page_0}
  ipgui::add_param $IPINST -name "H" -parent ${Page_0}
  ipgui::add_param $IPINST -name "H_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "N_STEPS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "W" -parent ${Page_0}


}

proc update_PARAM_VALUE.ADDR_WIDTH { PARAM_VALUE.ADDR_WIDTH } {
	# Procedure called to update ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ADDR_WIDTH { PARAM_VALUE.ADDR_WIDTH } {
	# Procedure called to validate ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.GRID_N { PARAM_VALUE.GRID_N } {
	# Procedure called to update GRID_N when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.GRID_N { PARAM_VALUE.GRID_N } {
	# Procedure called to validate GRID_N
	return true
}

proc update_PARAM_VALUE.H { PARAM_VALUE.H } {
	# Procedure called to update H when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.H { PARAM_VALUE.H } {
	# Procedure called to validate H
	return true
}

proc update_PARAM_VALUE.H_WIDTH { PARAM_VALUE.H_WIDTH } {
	# Procedure called to update H_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.H_WIDTH { PARAM_VALUE.H_WIDTH } {
	# Procedure called to validate H_WIDTH
	return true
}

proc update_PARAM_VALUE.N_STEPS { PARAM_VALUE.N_STEPS } {
	# Procedure called to update N_STEPS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.N_STEPS { PARAM_VALUE.N_STEPS } {
	# Procedure called to validate N_STEPS
	return true
}

proc update_PARAM_VALUE.W { PARAM_VALUE.W } {
	# Procedure called to update W when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.W { PARAM_VALUE.W } {
	# Procedure called to validate W
	return true
}


proc update_MODELPARAM_VALUE.W { MODELPARAM_VALUE.W PARAM_VALUE.W } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.W}] ${MODELPARAM_VALUE.W}
}

proc update_MODELPARAM_VALUE.H { MODELPARAM_VALUE.H PARAM_VALUE.H } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.H}] ${MODELPARAM_VALUE.H}
}

proc update_MODELPARAM_VALUE.GRID_N { MODELPARAM_VALUE.GRID_N PARAM_VALUE.GRID_N } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.GRID_N}] ${MODELPARAM_VALUE.GRID_N}
}

proc update_MODELPARAM_VALUE.N_STEPS { MODELPARAM_VALUE.N_STEPS PARAM_VALUE.N_STEPS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.N_STEPS}] ${MODELPARAM_VALUE.N_STEPS}
}

proc update_MODELPARAM_VALUE.H_WIDTH { MODELPARAM_VALUE.H_WIDTH PARAM_VALUE.H_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.H_WIDTH}] ${MODELPARAM_VALUE.H_WIDTH}
}

proc update_MODELPARAM_VALUE.ADDR_WIDTH { MODELPARAM_VALUE.ADDR_WIDTH PARAM_VALUE.ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ADDR_WIDTH}] ${MODELPARAM_VALUE.ADDR_WIDTH}
}


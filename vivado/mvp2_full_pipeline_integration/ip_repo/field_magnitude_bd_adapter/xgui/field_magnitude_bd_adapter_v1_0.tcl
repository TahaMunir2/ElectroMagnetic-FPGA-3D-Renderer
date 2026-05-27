# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CELLS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CELL_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DATA_WIDTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.CELLS { PARAM_VALUE.CELLS } {
	# Procedure called to update CELLS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CELLS { PARAM_VALUE.CELLS } {
	# Procedure called to validate CELLS
	return true
}

proc update_PARAM_VALUE.CELL_WIDTH { PARAM_VALUE.CELL_WIDTH } {
	# Procedure called to update CELL_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CELL_WIDTH { PARAM_VALUE.CELL_WIDTH } {
	# Procedure called to validate CELL_WIDTH
	return true
}

proc update_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to update DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to validate DATA_WIDTH
	return true
}


proc update_MODELPARAM_VALUE.CELLS { MODELPARAM_VALUE.CELLS PARAM_VALUE.CELLS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CELLS}] ${MODELPARAM_VALUE.CELLS}
}

proc update_MODELPARAM_VALUE.CELL_WIDTH { MODELPARAM_VALUE.CELL_WIDTH PARAM_VALUE.CELL_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CELL_WIDTH}] ${MODELPARAM_VALUE.CELL_WIDTH}
}

proc update_MODELPARAM_VALUE.DATA_WIDTH { MODELPARAM_VALUE.DATA_WIDTH PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATA_WIDTH}] ${MODELPARAM_VALUE.DATA_WIDTH}
}


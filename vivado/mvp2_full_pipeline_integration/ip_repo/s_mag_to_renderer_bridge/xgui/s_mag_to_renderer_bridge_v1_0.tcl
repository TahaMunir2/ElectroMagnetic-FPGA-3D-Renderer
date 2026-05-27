# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DST_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DST_CELLS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SRC_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SRC_CELLS" -parent ${Page_0}


}

proc update_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to update DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to validate DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.DST_ADDR_WIDTH { PARAM_VALUE.DST_ADDR_WIDTH } {
	# Procedure called to update DST_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DST_ADDR_WIDTH { PARAM_VALUE.DST_ADDR_WIDTH } {
	# Procedure called to validate DST_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.DST_CELLS { PARAM_VALUE.DST_CELLS } {
	# Procedure called to update DST_CELLS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DST_CELLS { PARAM_VALUE.DST_CELLS } {
	# Procedure called to validate DST_CELLS
	return true
}

proc update_PARAM_VALUE.SRC_ADDR_WIDTH { PARAM_VALUE.SRC_ADDR_WIDTH } {
	# Procedure called to update SRC_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SRC_ADDR_WIDTH { PARAM_VALUE.SRC_ADDR_WIDTH } {
	# Procedure called to validate SRC_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.SRC_CELLS { PARAM_VALUE.SRC_CELLS } {
	# Procedure called to update SRC_CELLS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SRC_CELLS { PARAM_VALUE.SRC_CELLS } {
	# Procedure called to validate SRC_CELLS
	return true
}


proc update_MODELPARAM_VALUE.SRC_CELLS { MODELPARAM_VALUE.SRC_CELLS PARAM_VALUE.SRC_CELLS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SRC_CELLS}] ${MODELPARAM_VALUE.SRC_CELLS}
}

proc update_MODELPARAM_VALUE.DST_CELLS { MODELPARAM_VALUE.DST_CELLS PARAM_VALUE.DST_CELLS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DST_CELLS}] ${MODELPARAM_VALUE.DST_CELLS}
}

proc update_MODELPARAM_VALUE.SRC_ADDR_WIDTH { MODELPARAM_VALUE.SRC_ADDR_WIDTH PARAM_VALUE.SRC_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SRC_ADDR_WIDTH}] ${MODELPARAM_VALUE.SRC_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.DST_ADDR_WIDTH { MODELPARAM_VALUE.DST_ADDR_WIDTH PARAM_VALUE.DST_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DST_ADDR_WIDTH}] ${MODELPARAM_VALUE.DST_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.DATA_WIDTH { MODELPARAM_VALUE.DATA_WIDTH PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATA_WIDTH}] ${MODELPARAM_VALUE.DATA_WIDTH}
}


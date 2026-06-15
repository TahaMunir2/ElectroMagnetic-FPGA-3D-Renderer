# PYNQ-Z1 constraints for D1S48/D1_wrapper/design1_ray_unit_hdmi_top.sv.
# Target part/board: xc7z020clg400-1 / PYNQ-Z1.

## 125 MHz PL reference clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { clk }]
# clk_wiz_0 owns the 125 MHz create_clock constraint for this port.
# Do not add another create_clock here, or Vivado will derive duplicate
# clk_wiz output clocks and report TIMING-6/TIMING-56 warnings.

## Reset input
## BTN0 on PYNQ-Z1, active high.
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports { rst }]

## HDMI TX output, source connector J11
set_property -dict { PACKAGE_PIN L16 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_p }]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_n }]

set_property -dict { PACKAGE_PIN K17 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[0] }]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[0] }]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[1] }]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[1] }]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[2] }]
set_property -dict { PACKAGE_PIN H18 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[2] }]

## ---------------------------------------------------------------------------
## Asynchronous clock groups
## The FDTD + render datapath runs on the clk_wiz outputs derived from the
## external 125 MHz pin (clk_out1 25 MHz pixel, clk_out2 125 MHz serial). The
## PS AXI domain runs on clk_fpga_0 (FCLK_CLK0, 50 MHz). These are unrelated
## clocks. FDTD control words crossing in are static config; the renderer
## camera path has its own toggle/ASYNC_REG CDC. Declare them asynchronous so
## the tool does not attempt (impossible) cross-domain timing.
## ---------------------------------------------------------------------------
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks -of_objects [get_ports clk]] \
  -group [get_clocks clk_fpga_0]

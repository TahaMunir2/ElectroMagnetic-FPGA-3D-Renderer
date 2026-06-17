# PYNQ-Z1 constraints for D4S48.
# Target part/board: xc7z020clg400-1 / PYNQ-Z1.

## 125 MHz PL reference clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { clk }]
# clk_wiz_1 owns the 125 MHz create_clock constraint for this port.

## Reset input
## BTN0 on PYNQ-Z1, active high. PULLDOWN guarantees reset is inactive if the
## button input is not externally driven during standalone JTAG programming.
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { rst }]

## HDMI TX output, source connector J11
set_property -dict { PACKAGE_PIN L16 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_p }]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_n }]

set_property -dict { PACKAGE_PIN K17 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[0] }]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[0] }]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[1] }]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[1] }]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[2] }]
set_property -dict { PACKAGE_PIN H18 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[2] }]

# Shared Quartus timing constraints for all FIR top-level revisions.
#
# The RTL uses a single synchronous clock input named clk and an active-low
# asynchronous reset named rst_n. This first-pass constraint set assumes a
# 100 MHz target clock and excludes rst_n from timing closure.

create_clock -name clk -period 10.000 [get_ports {clk}]

set_false_path -from [get_ports {rst_n}]
set_false_path -to [get_ports {rst_n}]

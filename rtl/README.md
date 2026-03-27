# RTL Layout

This repository keeps only the selected published RTL set plus the internal reduced-parallel support modules they depend on.

- `include/` holds generated or shared packages such as `fir_coeffs_pkg.sv`
- `src/` holds synthesis-target SystemVerilog modules

The checked-in Quartus scripts expect these file names:

- `rtl/include/fir_coeffs_pkg.sv`
- `rtl/src/fir_filter.sv`
- `rtl/src/fir_filter_pipelined.sv`
- `rtl/src/fir_filter_l2_reduced.sv`
- `rtl/src/fir_filter_l3_reduced.sv`
- `rtl/src/fir_filter_pipelined_l3_reduced.sv`
- `rtl/src/fir_filter_parallel_reduced.sv`
- `rtl/src/fir_filter_parallel_reduced_pipelined.sv`

The last two files are internal support blocks for the scalar `L=2`, `L=3`, and pipelined `L=3` reduced architectures.

The completed Quartus architecture set is:

- `fir_filter`
- `fir_filter_pipelined`
- `fir_filter_l2_reduced`
- `fir_filter_l3_reduced`
- `fir_filter_pipelined_l3_reduced`

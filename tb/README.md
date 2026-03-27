# Testbench Layout

`fir_filter_required_regression_tb.sv` is the main shared regression testbench for the published architecture set:

- `fir_filter`
- `fir_filter_pipelined`
- `fir_filter_l2_reduced`
- `fir_filter_l3_reduced`
- `fir_filter_pipelined_l3_reduced`

All five use the same scalar interface and are checked against the same baseline reference stream.

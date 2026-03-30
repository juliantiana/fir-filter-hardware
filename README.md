# Optimized FIR Filter — Design, Quantization, and FPGA Implementation

This repository contains an optimized low-pass FIR filter design study that aggressively searches tap count, equiripple weight, and coefficient width to find a better cost-performance point than the conservative baseline.

## Start Here

- Report: `docs/project_report.md`
- MATLAB tradeoff search: [`matlab/search_optimal_assignment_tradeoff.m`](matlab/search_optimal_assignment_tradeoff.m)
- Optimized coefficient design: [`matlab/design_fir_equiripple_optimized.m`](matlab/design_fir_equiripple_optimized.m)
- Final coefficient report and files: [`data/coeffs/final/`](data/coeffs/final/)

- Locked coefficient package used by RTL: [`rtl/include/fir_coeffs_pkg.sv`](rtl/include/fir_coeffs_pkg.sv)
- Top-level RTL architectures: [`rtl/src/fir_filter.sv`](rtl/src/fir_filter.sv), [`rtl/src/fir_filter_pipelined.sv`](rtl/src/fir_filter_pipelined.sv), [`rtl/src/fir_filter_l2_reduced.sv`](rtl/src/fir_filter_l2_reduced.sv), [`rtl/src/fir_filter_l3_reduced.sv`](rtl/src/fir_filter_l3_reduced.sv), [`rtl/src/fir_filter_pipelined_l3_reduced.sv`](rtl/src/fir_filter_pipelined_l3_reduced.sv)
- Shared reduced-complexity engines: [`rtl/src/fir_filter_parallel_reduced.sv`](rtl/src/fir_filter_parallel_reduced.sv), [`rtl/src/fir_filter_parallel_reduced_pipelined.sv`](rtl/src/fir_filter_parallel_reduced_pipelined.sv)

- Main regression testbench: [`tb/fir_filter_required_regression_tb.sv`](tb/fir_filter_required_regression_tb.sv)

- Raw Quartus implementation results: [`data/results/quartus/`](data/results/quartus/)
- Report figures and plots: [`assets/images/`](assets/images/)

## Optimized Design Point

| Parameter | Value |
| --- | --- |
| Taps | 211 |
| Passband edge | 0.20 pi rad/sample |
| Stopband edge | 0.23 pi rad/sample |
| Stopband target | 80 dB |
| Coefficient format | 20-bit signed (Q1.19) |
| Equiripple weights | [1, 160] |
| Measured stopband peak | -80.15 dB (quantized) |

## Quartus Results Summary (Cyclone V 5CGXFC9E6F35C7, 100 MHz)

| Architecture | Registers | DSPs | Timing | Setup Slack | Power |
| --- | ---: | ---: | --- | ---: | ---: |
| `fir_filter` | 3,393 | 205 | Fails | -17.36 ns | 721 mW |
| `fir_filter_pipelined` | 9,667 | 103 | **Passes** | +1.97 ns | 639 mW |
| `fir_filter_l2_reduced` | 3,574 | 206 | Fails | -19.22 ns | 788 mW |
| `fir_filter_l3_reduced` | 3,720 | 309 | Fails | -24.87 ns | 848 mW |
| **`fir_filter_pipelined_l3_reduced`** | **24,304** | **159** | **Passes** | **+0.32 ns** | **1,104 mW** |

Only pipelined designs meet 100 MHz. `fir_filter_pipelined_l3_reduced` delivers 3x the throughput of the serial pipeline at 1.7x power.

## Repository Layout

- `docs/` report and images
- [`matlab/`](matlab/) filter-design and tradeoff-search scripts
- [`rtl/include/`](rtl/include/) generated shared packages such as FIR coefficients
- [`rtl/src/`](rtl/src/) synthesis-target SystemVerilog modules
- [`tb/`](tb/) simulation testbenches and shared test utilities
- [`data/coeffs/final/`](data/coeffs/final/) final coefficient files used by the RTL
- [`data/results/`](data/results/) consolidated Quartus result summaries
- [`vendor/quartus/`](vendor/quartus/) checked-in timing constraint snapshot used by the saved FPGA results
- [`scripts/`](scripts/) helper scripts
- [`assets/images/`](assets/images/) report figures and plots

## Structure Notes

- Generated coefficient integers live in [`data/coeffs/final/`](data/coeffs/final/), while the RTL-consumable package lives in [`rtl/include/fir_coeffs_pkg.sv`](rtl/include/fir_coeffs_pkg.sv).
- The most important published source files are the five top-level RTL modules in [`rtl/src/`](rtl/src/) plus the shared regression testbench in [`tb/fir_filter_required_regression_tb.sv`](tb/fir_filter_required_regression_tb.sv).
- Quartus implementation summaries are consolidated under [`data/results/quartus/`](data/results/quartus/) so readers do not need to navigate multiple result trees.

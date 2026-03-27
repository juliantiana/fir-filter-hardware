# Optimized FIR Filter — Design, Quantization, and FPGA Implementation

This repository contains an optimized low-pass FIR filter design study that aggressively searches tap count, equiripple weight, and coefficient width to find a better cost-performance point than the conservative baseline.

## Start Here

- MATLAB tradeoff search: [`matlab/search_optimal_assignment_tradeoff.m`](matlab/search_optimal_assignment_tradeoff.m)
- Optimized coefficient design: [`matlab/design_fir_equiripple_optimized.m`](matlab/design_fir_equiripple_optimized.m)
- Final chosen coefficient files: [`data/coeffs/final/`](data/coeffs/final/)
- Locked coefficient package used by RTL: [`rtl/include/fir_coeffs_pkg.sv`](rtl/include/fir_coeffs_pkg.sv)
- Key pipelined parallel RTL: [`rtl/src/fir_filter_parallel_reduced_pipelined.sv`](rtl/src/fir_filter_parallel_reduced_pipelined.sv)
- Main regression testbench: [`tb/fir_filter_required_regression_tb.sv`](tb/fir_filter_required_regression_tb.sv)
- Current Quartus result snapshot: [`docs/quartus_results_snapshot.md`](docs/quartus_results_snapshot.md)

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

- [`docs/`](docs/) concise Quartus result snapshots
- [`matlab/`](matlab/) filter-design and tradeoff-search scripts
- [`rtl/include/`](rtl/include/) generated shared packages such as FIR coefficients
- [`rtl/src/`](rtl/src/) synthesis-target SystemVerilog modules
- [`tb/`](tb/) simulation testbenches and shared test utilities
- [`data/coeffs/final/`](data/coeffs/final/) final coefficient files used by the RTL
- [`data/results/`](data/results/) consolidated Quartus result summaries
- [`vendor/quartus/`](vendor/quartus/) checked-in timing constraint snapshot used by the saved FPGA results
- [`scripts/`](scripts/) helper scripts such as coefficient-package generation
- [`assets/images/`](assets/images/) report figures and plots

## Structure Notes

- Generated coefficient integers live in [`data/coeffs/final/`](data/coeffs/final/), while the RTL-consumable package lives in [`rtl/include/fir_coeffs_pkg.sv`](rtl/include/fir_coeffs_pkg.sv).
- Quartus implementation summaries are consolidated under [`data/results/quartus/`](data/results/quartus/) so readers do not need to navigate multiple result trees.
- [`docs/quartus_results_snapshot.md`](docs/quartus_results_snapshot.md) keeps the checked-in implementation snapshot.
- Detailed local tool-launch instructions are intentionally kept outside this published repo.

## Status

- MATLAB optimized design, coefficient export, RTL, shared verification, and Quartus results are all present.
- Two architectures meet 100 MHz timing: serial pipelined and parallel pipelined L3 reduced.
- The parallel pipelined L3 design is the highest-throughput timing-closed architecture at 310 MSPS.

# Quartus Results Snapshot

This note captures the consolidated Quartus results saved under `data/results/quartus/` for the Cyclone V `5CGXFC9E6F35C7` target at 100 MHz.

## Completed result folders

- `fir_filter`
- `fir_filter_pipelined`
- `fir_filter_l2_reduced`
- `fir_filter_l3_reduced`
- `fir_filter_pipelined_l3_reduced`

## Current completed comparison

| Architecture | Fitter status | Registers | DSPs | 100 MHz timing | Worst slow 85C setup slack | Total thermal power |
| --- | --- | ---: | ---: | --- | ---: | ---: |
| `fir_filter` | Successful | `3,393` | `205` | Fails | `-17.362 ns` | `720.56 mW` |
| `fir_filter_pipelined` | Successful | `9,667` | `103` | Passes | `+1.965 ns` | `639.29 mW` |
| `fir_filter_l2_reduced` | Successful | `3,574` | `206` | Fails | `-19.217 ns` | `788.45 mW` |
| `fir_filter_l3_reduced` | Successful | `3,720` | `309` | Fails | `-24.871 ns` | `848.44 mW` |
| `fir_filter_pipelined_l3_reduced` | Successful | `24,304` | `159` | Passes | `+0.324 ns` | `1,104.29 mW` |

## Short interpretation

- `fir_filter` fits, but the direct-form arithmetic path is too slow for the 100 MHz target.
- `fir_filter_pipelined` fits and meets timing with comfortable margin (+1.965 ns), making it the simplest timing-closed design.
- `fir_filter_l2_reduced` fits, but its parallel L=2 structure does not meet timing without pipeline registers.
- `fir_filter_l3_reduced` fits, but the deeper L=3 parallel structure creates even longer combinational paths (-24.871 ns slack).
- `fir_filter_pipelined_l3_reduced` meets timing with thin margin (+0.324 ns), delivering 3x throughput of the serial pipelined design at 1.7x power and 2.5x registers.
- Only two architectures close timing: `fir_filter_pipelined` (serial) and `fir_filter_pipelined_l3_reduced` (parallel).
- Power values were obtained with Quartus default toggle assumptions and are therefore most useful for relative comparison only.

## Throughput-normalized view (timing-closed designs only)

| Architecture | Fmax | Parallelism | Throughput | mW/MSPS | Regs/MSPS | DSPs/MSPS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `fir_filter_pipelined` | 124.5 MHz | 1 | 124.5 MSPS | 5.1 | 77.6 | 0.83 |
| `fir_filter_pipelined_l3_reduced` | 103.3 MHz | 3 | 310.0 MSPS | 3.6 | 78.4 | 0.51 |

## Source reports

- `data/results/quartus/fir_filter/fir_filter.fit.summary`
- `data/results/quartus/fir_filter/fir_filter.pow.summary`
- `data/results/quartus/fir_filter/fir_filter.sta.summary`
- `data/results/quartus/fir_filter_pipelined/fir_filter_pipelined.fit.summary`
- `data/results/quartus/fir_filter_pipelined/fir_filter_pipelined.pow.summary`
- `data/results/quartus/fir_filter_pipelined/fir_filter_pipelined.sta.summary`
- `data/results/quartus/fir_filter_l2_reduced/fir_filter_l2_reduced.fit.summary`
- `data/results/quartus/fir_filter_l2_reduced/fir_filter_l2_reduced.pow.summary`
- `data/results/quartus/fir_filter_l2_reduced/fir_filter_l2_reduced.sta.summary`
- `data/results/quartus/fir_filter_l3_reduced/fir_filter_l3_reduced.fit.summary`
- `data/results/quartus/fir_filter_l3_reduced/fir_filter_l3_reduced.pow.summary`
- `data/results/quartus/fir_filter_l3_reduced/fir_filter_l3_reduced.sta.summary`
- `data/results/quartus/fir_filter_pipelined_l3_reduced/fir_filter_pipelined_l3_reduced.fit.summary`
- `data/results/quartus/fir_filter_pipelined_l3_reduced/fir_filter_pipelined_l3_reduced.pow.summary`
- `data/results/quartus/fir_filter_pipelined_l3_reduced/fir_filter_pipelined_l3_reduced.sta.summary`

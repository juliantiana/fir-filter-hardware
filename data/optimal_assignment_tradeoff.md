# Optimized Tradeoff Summary

## Selected design point

- taps: `211`
- stopband weight: `160`
- coefficient format: `20-bit signed` (`Q1.19`)
- quantized stopband peak: `-80.15 dB`
- quantized passband ripple: `0.2275 dB`

## Why this point was selected

- it meets the original `80 dB` stopband target after quantization
- it reduces tap count relative to the conservative public baseline
- it keeps the coefficient width moderate while preserving the required response

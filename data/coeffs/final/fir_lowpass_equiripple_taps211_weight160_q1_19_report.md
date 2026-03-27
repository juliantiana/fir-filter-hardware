# Optimized FIR Design Report: fir_lowpass_equiripple_taps211_weight160_q1_19

## Design inputs
- taps: `211`
- passband edge: `0.2000 * pi rad/sample`
- stopband edge: `0.2300 * pi rad/sample`
- stopband target: `80.00 dB`
- coefficient format: `20-bit signed`
- coefficient quantization: `Q1.19`
- equiripple band weights [passband, stopband]: `[1, 160]`

## Measured floating-point response
- passband ripple: `0.2274 dB`
- stopband peak: `-81.45 dB`

## Measured quantized response
- passband ripple: `0.2275 dB`
- stopband peak: `-80.15 dB`

## Generated files
- floating-point coefficients: `results/coeffs/fir_lowpass_equiripple_taps211_weight160_q1_19_float.txt`
- quantized coefficients: `results/coeffs/fir_lowpass_equiripple_taps211_weight160_q1_19_int.txt`
- response plot: `results/images/fir_lowpass_equiripple_taps211_weight160_q1_19_response.png`
- passband zoom plot: `results/images/fir_lowpass_equiripple_taps211_weight160_q1_19_passband_zoom.png`
- stopband zoom plot: `results/images/fir_lowpass_equiripple_taps211_weight160_q1_19_stopband_zoom.png`
- impulse response plot: `results/images/fir_lowpass_equiripple_taps211_weight160_q1_19_impulse.png`
- quantized coefficient plot: `results/images/fir_lowpass_equiripple_taps211_weight160_q1_19_coefficients.png`

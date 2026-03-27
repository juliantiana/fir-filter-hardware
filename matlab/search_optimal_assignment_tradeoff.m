%% Search tap / weight / quantization tradeoff under original assignment spec

clear;
clc;

passband_edge = 0.20;
stopband_edge = 0.23;
stopband_atten_db = 80;

tap_values = 100:1:280;
stopband_weight_values = [1, 2, 5, 10, 20, 40, 80, 160];
coeff_fraction_bits_values = [15, 17, 19, 21, 23, 25, 27, 31];

passband_weight = 1;
n_fft = 16384;

script_dir = fileparts(mfilename('fullpath'));
opt_root = fileparts(script_dir);
results_dir = fullfile(opt_root, 'results');
csv_path = fullfile(results_dir, 'optimal_assignment_tradeoff.csv');
report_path = fullfile(results_dir, 'optimal_assignment_tradeoff.md');

weights = [passband_weight, stopband_weight_values(1)];

rows = [];
best_idx = 0;
best_cost = inf;

for tap_idx = 1:numel(tap_values)
    num_taps = tap_values(tap_idx);
    filter_order = num_taps - 1;
    bands = [0, passband_edge, stopband_edge, 1];
    desired = [1, 1, 0, 0];

    for wt_idx = 1:numel(stopband_weight_values)
        stopband_weight = stopband_weight_values(wt_idx);
        weights = [passband_weight, stopband_weight];

        h = firpm(filter_order, bands, desired, weights);
        [H, w] = freqz(h, 1, n_fft);
        f_norm = w / pi;
        mag = abs(H);

        passband_mask = f_norm <= passband_edge;
        stopband_mask = f_norm >= stopband_edge;
        passband_mag = mag(passband_mask);
        stopband_mag = mag(stopband_mask);

        float_pb_ripple_db = 20 * log10(max(passband_mag)) - 20 * log10(min(passband_mag));
        float_sb_peak_db = 20 * log10(max(stopband_mag) + eps);
        float_ok = double(float_sb_peak_db <= -stopband_atten_db);

        for bits_idx = 1:numel(coeff_fraction_bits_values)
            coeff_fraction_bits = coeff_fraction_bits_values(bits_idx);
            coeff_scale = 2^coeff_fraction_bits;
            coeff_int = round(h * coeff_scale);
            coeff_int = min(max(coeff_int, -coeff_scale), coeff_scale - 1);
            coeff_quant = coeff_int / coeff_scale;

            Hq = freqz(coeff_quant, 1, n_fft);
            mag_q = abs(Hq);
            passband_mag_q = mag_q(passband_mask);
            stopband_mag_q = mag_q(stopband_mask);

            quant_pb_ripple_db = 20 * log10(max(passband_mag_q)) - 20 * log10(min(passband_mag_q));
            quant_sb_peak_db = 20 * log10(max(stopband_mag_q) + eps);
            quant_ok = double(quant_sb_peak_db <= -stopband_atten_db);

            total_bits = coeff_fraction_bits + 1;
            cost = num_taps * total_bits;

            row = [num_taps, stopband_weight, coeff_fraction_bits, total_bits, ...
                   float_pb_ripple_db, float_sb_peak_db, float_ok, ...
                   quant_pb_ripple_db, quant_sb_peak_db, quant_ok, cost];
            rows = [rows; row]; %#ok<AGROW>

            if quant_ok
                if (cost < best_cost) || ...
                   (cost == best_cost && num_taps < rows(best_idx, 1)) || ...
                   (cost == best_cost && num_taps == rows(best_idx, 1) && total_bits < rows(best_idx, 4))
                    best_cost = cost;
                    best_idx = size(rows, 1);
                end
            end
        end
    end
end

fid = fopen(csv_path, 'w');
if fid == -1
    error('Could not open %s for writing.', csv_path);
end
cleanup_csv = onCleanup(@() fclose(fid));
fprintf(fid, 'taps,stopband_weight,coeff_fraction_bits,total_bits,float_pb_ripple_db,float_sb_peak_db,float_ok,quant_pb_ripple_db,quant_sb_peak_db,quant_ok,cost\n');
for idx = 1:size(rows, 1)
    fprintf(fid, '%d,%.0f,%d,%d,%.6f,%.6f,%d,%.6f,%.6f,%d,%.0f\n', rows(idx, :));
end
clear cleanup_csv

valid_rows = rows(rows(:, 10) == 1, :);
[~, sort_idx] = sortrows(valid_rows, [11, 1, 4]);
top_rows = valid_rows(sort_idx, :);
top_n = min(10, size(top_rows, 1));

lines = {
    '# Optimal Assignment Tradeoff Search'
    ''
    'This search keeps the original public assignment-style filter target:'
    sprintf('- passband edge: `%.2f * pi rad/sample`', passband_edge)
    sprintf('- stopband edge: `%.2f * pi rad/sample`', stopband_edge)
    sprintf('- stopband attenuation target: `%.1f dB`', stopband_atten_db)
    ''
    'The search varies only design choices that the assignment leaves open:'
    '- equiripple stopband weight'
    '- coefficient quantization width'
    '- tap count'
    ''
};

if best_idx > 0
    best = rows(best_idx, :);
    lines{end + 1} = '## Best quantized-feasible tradeoff found';
    lines{end + 1} = sprintf('- taps: `%d`', best(1));
    lines{end + 1} = sprintf('- stopband weight: `%d`', best(2));
    lines{end + 1} = sprintf('- coefficient format: `%d-bit signed` (`Q1.%d`)', best(4), best(3));
    lines{end + 1} = sprintf('- floating-point passband ripple: `%.4f dB`', best(5));
    lines{end + 1} = sprintf('- floating-point stopband peak: `%.2f dB`', best(6));
    lines{end + 1} = sprintf('- quantized passband ripple: `%.4f dB`', best(8));
    lines{end + 1} = sprintf('- quantized stopband peak: `%.2f dB`', best(9));
    lines{end + 1} = sprintf('- simple implementation cost metric (`taps * total_bits`): `%.0f`', best(11));
    lines{end + 1} = '';
end

lines{end + 1} = '## Top feasible combinations by simple cost metric';
lines{end + 1} = '';
lines{end + 1} = '| Taps | Stopband Weight | Coeff Format | Float PB Ripple | Float SB Peak | Quant PB Ripple | Quant SB Peak | Cost |';
lines{end + 1} = '| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |';

for idx = 1:top_n
    row = top_rows(idx, :);
    lines{end + 1} = sprintf('| `%d` | `%d` | `%d-bit / Q1.%d` | `%.4f dB` | `%.2f dB` | `%.4f dB` | `%.2f dB` | `%.0f` |', ...
        row(1), row(2), row(4), row(3), row(5), row(6), row(8), row(9), row(11));
end

lines{end + 1} = '';
lines{end + 1} = 'Interpretation notes:';
lines{end + 1} = '- The public assignment targets are unchanged.';
lines{end + 1} = '- The cost metric is intentionally simple and only meant to compare tap-count / coefficient-width tradeoffs.';
lines{end + 1} = '- Lower cost does not automatically guarantee better FPGA timing or lower routed power.';

fid = fopen(report_path, 'w');
if fid == -1
    error('Could not open %s for writing.', report_path);
end
cleanup_report = onCleanup(@() fclose(fid));
for idx = 1:numel(lines)
    fprintf(fid, '%s\n', lines{idx});
end

fprintf('Wrote optimized tradeoff search report to %s\n', report_path);
fprintf('Wrote optimized tradeoff search CSV to %s\n', csv_path);

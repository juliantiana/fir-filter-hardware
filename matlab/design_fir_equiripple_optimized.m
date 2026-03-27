%% Optimized low-pass FIR design under original assignment targets

clear;
clc;

num_taps = 211;
passband_edge = 0.20;
stopband_edge = 0.23;
stopband_atten_db = 80;
coeff_fraction_bits = 19;
passband_weight = 1;
stopband_weight = 160;

if ~(0 < passband_edge && passband_edge < stopband_edge && stopband_edge < 1)
    error('Use normalized edges with 0 < passband_edge < stopband_edge < 1.');
end

script_dir = fileparts(mfilename('fullpath'));
opt_root = fileparts(script_dir);
results_dir = fullfile(opt_root, 'results');
coeff_dir = fullfile(results_dir, 'coeffs');
image_dir = fullfile(results_dir, 'images');

weights = [passband_weight, stopband_weight];
filter_order = num_taps - 1;
bands = [0, passband_edge, stopband_edge, 1];
desired = [1, 1, 0, 0];

h = firpm(filter_order, bands, desired, weights);

n_fft = 16384;
[H, w] = freqz(h, 1, n_fft);
f_norm = w / pi;
mag = abs(H);

passband_mask = f_norm <= passband_edge;
stopband_mask = f_norm >= stopband_edge;
passband_mag = mag(passband_mask);
stopband_mag = mag(stopband_mask);

passband_ripple_measured_db = 20 * log10(max(passband_mag)) - 20 * log10(min(passband_mag));
stopband_peak_db = 20 * log10(max(stopband_mag) + eps);

coeff_scale = 2^coeff_fraction_bits;
coeff_total_bits = coeff_fraction_bits + 1;
coeff_int = round(h * coeff_scale);
coeff_int = min(max(coeff_int, -coeff_scale), coeff_scale - 1);
coeff_quant = coeff_int / coeff_scale;

[Hq, ~] = freqz(coeff_quant, 1, n_fft);
mag_q = abs(Hq);
passband_mag_q = mag_q(passband_mask);
stopband_mag_q = mag_q(stopband_mask);

passband_ripple_quant_db = 20 * log10(max(passband_mag_q)) - 20 * log10(min(passband_mag_q));
stopband_peak_quant_db = 20 * log10(max(stopband_mag_q) + eps);

base_name = sprintf('fir_lowpass_equiripple_taps%d_weight%d_q1_%d', num_taps, stopband_weight, coeff_fraction_bits);
float_path = fullfile(coeff_dir, [base_name, '_float.txt']);
q_path = fullfile(coeff_dir, [base_name, '_int.txt']);
report_path = fullfile(results_dir, [base_name, '_report.md']);
response_plot_path = fullfile(image_dir, [base_name, '_response.png']);
passband_plot_path = fullfile(image_dir, [base_name, '_passband_zoom.png']);
stopband_plot_path = fullfile(image_dir, [base_name, '_stopband_zoom.png']);
impulse_plot_path = fullfile(image_dir, [base_name, '_impulse.png']);
coeff_plot_path = fullfile(image_dir, [base_name, '_coefficients.png']);

write_numeric_vector(float_path, h(:), '%.18g');
write_numeric_vector(q_path, coeff_int(:), '%d');

fig = figure('Visible', 'off');
plot(f_norm, 20 * log10(mag + eps), 'LineWidth', 1.5);
hold on;
plot(f_norm, 20 * log10(mag_q + eps), '--', 'LineWidth', 1.5);
xline(passband_edge, ':', 'Passband Edge');
xline(stopband_edge, ':', 'Stopband Edge');
yline(-stopband_atten_db, ':', 'Stopband Target');
grid on;
xlabel('Normalized Frequency (x pi rad/sample)');
ylabel('Magnitude (dB)');
title(sprintf('Optimized FIR Response: %d Taps, Q1.%d', num_taps, coeff_fraction_bits));
legend('Floating-point', 'Quantized', 'Location', 'southwest');
saveas(fig, response_plot_path);
close(fig);

fig = figure('Visible', 'off');
plot(f_norm(passband_mask), 20 * log10(passband_mag + eps), 'LineWidth', 1.5);
hold on;
plot(f_norm(passband_mask), 20 * log10(passband_mag_q + eps), '--', 'LineWidth', 1.5);
grid on;
xlim([0, passband_edge * 1.05]);
xlabel('Normalized Frequency (x pi rad/sample)');
ylabel('Magnitude (dB)');
title(sprintf('Optimized Passband Zoom: %d-Tap FIR', num_taps));
legend('Floating-point', 'Quantized', 'Location', 'southwest');
saveas(fig, passband_plot_path);
close(fig);

fig = figure('Visible', 'off');
plot(f_norm(stopband_mask), 20 * log10(stopband_mag + eps), 'LineWidth', 1.5);
hold on;
plot(f_norm(stopband_mask), 20 * log10(stopband_mag_q + eps), '--', 'LineWidth', 1.5);
yline(-stopband_atten_db, ':', 'Stopband Target');
grid on;
xlim([stopband_edge * 0.95, 1]);
xlabel('Normalized Frequency (x pi rad/sample)');
ylabel('Magnitude (dB)');
title(sprintf('Optimized Stopband Zoom: %d-Tap FIR', num_taps));
legend('Floating-point', 'Quantized', 'Location', 'southwest');
saveas(fig, stopband_plot_path);
close(fig);

fig = figure('Visible', 'off');
stem(0:num_taps-1, h, 'filled', 'MarkerSize', 2);
grid on;
xlabel('Tap Index');
ylabel('Coefficient Value');
title(sprintf('Optimized Floating-Point Impulse Response: %d Taps', num_taps));
saveas(fig, impulse_plot_path);
close(fig);

fig = figure('Visible', 'off');
stairs(0:num_taps-1, coeff_int, 'LineWidth', 1.2);
grid on;
xlabel('Tap Index');
ylabel('Quantized Coefficient Integer');
title(sprintf('Optimized Quantized Coefficients: %d Taps, Q1.%d', num_taps, coeff_fraction_bits));
saveas(fig, coeff_plot_path);
close(fig);

report_lines = {
    sprintf('# Optimized FIR Design Report: %s', base_name)
    ''
    '## Design inputs'
    sprintf('- taps: `%d`', num_taps)
    sprintf('- passband edge: `%.4f * pi rad/sample`', passband_edge)
    sprintf('- stopband edge: `%.4f * pi rad/sample`', stopband_edge)
    sprintf('- stopband target: `%.2f dB`', stopband_atten_db)
    sprintf('- coefficient format: `%d-bit signed`', coeff_total_bits)
    sprintf('- coefficient quantization: `Q1.%d`', coeff_fraction_bits)
    sprintf('- equiripple band weights [passband, stopband]: `[%g, %g]`', passband_weight, stopband_weight)
    ''
    '## Measured floating-point response'
    sprintf('- passband ripple: `%.4f dB`', passband_ripple_measured_db)
    sprintf('- stopband peak: `%.2f dB`', stopband_peak_db)
    ''
    '## Measured quantized response'
    sprintf('- passband ripple: `%.4f dB`', passband_ripple_quant_db)
    sprintf('- stopband peak: `%.2f dB`', stopband_peak_quant_db)
    ''
    '## Generated files'
    sprintf('- floating-point coefficients: `%s`', relative_to_root(float_path, opt_root))
    sprintf('- quantized coefficients: `%s`', relative_to_root(q_path, opt_root))
    sprintf('- response plot: `%s`', relative_to_root(response_plot_path, opt_root))
    sprintf('- passband zoom plot: `%s`', relative_to_root(passband_plot_path, opt_root))
    sprintf('- stopband zoom plot: `%s`', relative_to_root(stopband_plot_path, opt_root))
    sprintf('- impulse response plot: `%s`', relative_to_root(impulse_plot_path, opt_root))
    sprintf('- quantized coefficient plot: `%s`', relative_to_root(coeff_plot_path, opt_root))
};

write_lines(report_path, report_lines);

fprintf('Optimized FIR generated.\n');
fprintf('Float coeffs  : %s\n', relative_to_root(float_path, opt_root));
fprintf('Q coeffs      : %s\n', relative_to_root(q_path, opt_root));
fprintf('Response plot : %s\n', relative_to_root(response_plot_path, opt_root));
fprintf('Passband zoom : %s\n', relative_to_root(passband_plot_path, opt_root));
fprintf('Stopband zoom : %s\n', relative_to_root(stopband_plot_path, opt_root));
fprintf('Impulse plot  : %s\n', relative_to_root(impulse_plot_path, opt_root));
fprintf('Coeff plot    : %s\n', relative_to_root(coeff_plot_path, opt_root));
fprintf('Report        : %s\n', relative_to_root(report_path, opt_root));

function rel_path = relative_to_root(abs_path, root_dir)
rel_path = strrep(abs_path, [root_dir, filesep], '');
end

function write_lines(file_path, lines)
fid = fopen(file_path, 'w');
if fid == -1
    error('Could not open file for writing: %s', file_path);
end
cleanup_obj = onCleanup(@() fclose(fid));
for idx = 1:numel(lines)
    fprintf(fid, '%s\n', lines{idx});
end
end

function write_numeric_vector(file_path, values, format_spec)
fid = fopen(file_path, 'w');
if fid == -1
    error('Could not open file for writing: %s', file_path);
end
cleanup_obj = onCleanup(@() fclose(fid));
for idx = 1:numel(values)
    fprintf(fid, [format_spec, '\n'], values(idx));
end
end

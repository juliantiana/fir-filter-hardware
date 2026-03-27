`timescale 1ns/1ps

module fir_filter #(
    parameter int SAMPLE_WIDTH = 16
) (
    input  logic                             clk,
    input  logic                             rst_n,
    input  logic                             sample_valid,
    input  logic signed [SAMPLE_WIDTH-1:0]   sample_in,
    output logic                             sample_out_valid,
    output logic signed [SAMPLE_WIDTH-1:0]   sample_out
);

    // Baseline direct-form FIR: shift in a new sample, multiply every tap,
    // accumulate the full sum, then resize back to the sample width.

    import fir_coeffs_pkg::*;

    localparam int PRODUCT_WIDTH = SAMPLE_WIDTH + FIR_COEFF_WIDTH;
    localparam int ACC_WIDTH = PRODUCT_WIDTH + $clog2(FIR_NUM_TAPS) + 2;
    localparam logic signed [SAMPLE_WIDTH-1:0] SAMPLE_MAX = {1'b0, {(SAMPLE_WIDTH-1){1'b1}}};
    localparam logic signed [SAMPLE_WIDTH-1:0] SAMPLE_MIN = {1'b1, {(SAMPLE_WIDTH-1){1'b0}}};
    localparam logic signed [ACC_WIDTH-1:0] SAMPLE_MAX_EXT = {{(ACC_WIDTH-SAMPLE_WIDTH){1'b0}}, SAMPLE_MAX};
    localparam logic signed [ACC_WIDTH-1:0] SAMPLE_MIN_EXT = {{(ACC_WIDTH-SAMPLE_WIDTH){1'b1}}, SAMPLE_MIN};

    // Most recent sample is stored at index 0.
    logic signed [SAMPLE_WIDTH-1:0] delay_line [0:FIR_NUM_TAPS-1];
    logic signed [SAMPLE_WIDTH-1:0] delay_line_next [0:FIR_NUM_TAPS-1];
    logic signed [ACC_WIDTH-1:0] accumulator_next;
    logic signed [SAMPLE_WIDTH-1:0] output_next;

    function automatic logic signed [SAMPLE_WIDTH-1:0] resize_and_saturate(
        input logic signed [ACC_WIDTH-1:0] value
    );
        logic signed [ACC_WIDTH-1:0] rounded;
        logic signed [ACC_WIDTH-1:0] shifted;
        begin
            if (FIR_COEFF_FRAC_BITS > 0) begin
                if (value >= 0) begin
                    rounded = value + ({{(ACC_WIDTH-1){1'b0}}, 1'b1} <<< (FIR_COEFF_FRAC_BITS - 1));
                end else begin
                    rounded = value - ({{(ACC_WIDTH-1){1'b0}}, 1'b1} <<< (FIR_COEFF_FRAC_BITS - 1));
                end
                shifted = rounded >>> FIR_COEFF_FRAC_BITS;
            end else begin
                shifted = value;
            end

            if (shifted > SAMPLE_MAX_EXT) begin
                resize_and_saturate = SAMPLE_MAX;
            end else if (shifted < SAMPLE_MIN_EXT) begin
                resize_and_saturate = SAMPLE_MIN;
            end else begin
                resize_and_saturate = shifted[SAMPLE_WIDTH-1:0];
            end
        end
    endfunction

    integer tap_idx;
    always @* begin
        for (tap_idx = 0; tap_idx < FIR_NUM_TAPS; tap_idx++) begin
            delay_line_next[tap_idx] = delay_line[tap_idx];
        end

        if (sample_valid) begin
            // Shift the sample history only when the input is valid.
            delay_line_next[0] = sample_in;
            for (tap_idx = 1; tap_idx < FIR_NUM_TAPS; tap_idx++) begin
                delay_line_next[tap_idx] = delay_line[tap_idx - 1];
            end
        end

        // Direct-form multiply-accumulate across the entire tap set.
        accumulator_next = '0;
        for (tap_idx = 0; tap_idx < FIR_NUM_TAPS; tap_idx++) begin
            accumulator_next += delay_line_next[tap_idx] * fir_coeff(tap_idx);
        end

        output_next = resize_and_saturate(accumulator_next);
    end

    integer reg_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (reg_idx = 0; reg_idx < FIR_NUM_TAPS; reg_idx++) begin
                delay_line[reg_idx] <= '0;
            end
            sample_out_valid <= 1'b0;
            sample_out <= '0;
        end else begin
            if (sample_valid) begin
                // Commit the shifted history and corresponding FIR output.
                for (reg_idx = 0; reg_idx < FIR_NUM_TAPS; reg_idx++) begin
                    delay_line[reg_idx] <= delay_line_next[reg_idx];
                end
                sample_out <= output_next;
            end
            sample_out_valid <= sample_valid;
        end
    end

endmodule

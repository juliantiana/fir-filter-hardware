`timescale 1ns/1ps

module fir_filter_pipelined #(
    parameter int SAMPLE_WIDTH = 16
) (
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           sample_valid,
    input  logic signed [SAMPLE_WIDTH-1:0] sample_in,
    output logic                           sample_out_valid,
    output logic signed [SAMPLE_WIDTH-1:0] sample_out
);

    // Transposed/pipelined FIR: each stage stores a partial sum so the
    // combinational depth is much shorter than the baseline direct form.

    import fir_coeffs_pkg::*;

    localparam int PRODUCT_WIDTH = SAMPLE_WIDTH + FIR_COEFF_WIDTH;
    localparam int ACC_WIDTH = PRODUCT_WIDTH + $clog2(FIR_NUM_TAPS) + 2;
    localparam logic signed [SAMPLE_WIDTH-1:0] SAMPLE_MAX = {1'b0, {(SAMPLE_WIDTH-1){1'b1}}};
    localparam logic signed [SAMPLE_WIDTH-1:0] SAMPLE_MIN = {1'b1, {(SAMPLE_WIDTH-1){1'b0}}};
    localparam logic signed [ACC_WIDTH-1:0] SAMPLE_MAX_EXT = {{(ACC_WIDTH-SAMPLE_WIDTH){1'b0}}, SAMPLE_MAX};
    localparam logic signed [ACC_WIDTH-1:0] SAMPLE_MIN_EXT = {{(ACC_WIDTH-SAMPLE_WIDTH){1'b1}}, SAMPLE_MIN};

    // stage_reg[k] holds the registered partial sum feeding the next stage.
    logic signed [ACC_WIDTH-1:0] stage_reg [0:FIR_NUM_TAPS-2];
    logic signed [ACC_WIDTH-1:0] stage_next [0:FIR_NUM_TAPS-2];
    logic signed [ACC_WIDTH-1:0] output_acc_next;

    function automatic logic signed [ACC_WIDTH-1:0] mult_ext(
        input logic signed [SAMPLE_WIDTH-1:0] sample,
        input logic signed [FIR_COEFF_WIDTH-1:0] coeff
    );
        logic signed [PRODUCT_WIDTH-1:0] product;
        begin
            product = sample * coeff;
            mult_ext = {{(ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};
        end
    endfunction

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

    integer stage_idx;
    always @* begin
        output_acc_next = '0;
        for (stage_idx = 0; stage_idx < FIR_NUM_TAPS - 1; stage_idx++) begin
            stage_next[stage_idx] = stage_reg[stage_idx];
        end

        if (sample_valid) begin
            // Inject the current sample into every coefficient path and push
            // the partial sums forward by one stage.
            output_acc_next = mult_ext(sample_in, fir_coeff(0)) + stage_reg[0];
            for (stage_idx = 0; stage_idx < FIR_NUM_TAPS - 2; stage_idx++) begin
                stage_next[stage_idx] = stage_reg[stage_idx + 1] + mult_ext(sample_in, fir_coeff(stage_idx + 1));
            end
            stage_next[FIR_NUM_TAPS - 2] = mult_ext(sample_in, fir_coeff(FIR_NUM_TAPS - 1));
        end
    end

    integer reg_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (reg_idx = 0; reg_idx < FIR_NUM_TAPS - 1; reg_idx++) begin
                stage_reg[reg_idx] <= '0;
            end
            sample_out_valid <= 1'b0;
            sample_out <= '0;
        end else begin
            if (sample_valid) begin
                // Register the updated pipeline state and output sample.
                for (reg_idx = 0; reg_idx < FIR_NUM_TAPS - 1; reg_idx++) begin
                    stage_reg[reg_idx] <= stage_next[reg_idx];
                end
                sample_out <= resize_and_saturate(output_acc_next);
            end
            sample_out_valid <= sample_valid;
        end
    end

endmodule

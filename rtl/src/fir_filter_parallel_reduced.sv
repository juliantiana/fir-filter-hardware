`timescale 1ns/1ps

module fir_filter_parallel_reduced #(
    parameter int SAMPLE_WIDTH = 16,
    parameter int PARALLELISM = 2,
    parameter bit OUTPUT_PIPELINE = 1'b0
) (
    input  logic                                           clk,
    input  logic                                           rst_n,
    input  logic                                           sample_valid,
    input  logic signed [SAMPLE_WIDTH-1:0]                 sample_in [0:PARALLELISM-1],
    output logic                                           sample_out_valid,
    output logic signed [SAMPLE_WIDTH-1:0]                 sample_out [0:PARALLELISM-1]
);

    import fir_coeffs_pkg::*;

    localparam int HALF_TAPS = FIR_NUM_TAPS / 2;
    localparam bit HAS_CENTER_TAP = (FIR_NUM_TAPS % 2) != 0;
    localparam int HISTORY_DEPTH = ((FIR_NUM_TAPS + PARALLELISM - 1) / PARALLELISM) + 1;
    localparam int PAIR_SUM_WIDTH = SAMPLE_WIDTH + 1;
    localparam int PRODUCT_WIDTH = PAIR_SUM_WIDTH + FIR_COEFF_WIDTH;
    localparam int ACC_WIDTH = PRODUCT_WIDTH + $clog2(HALF_TAPS + 1) + 2;
    localparam logic signed [SAMPLE_WIDTH-1:0] SAMPLE_MAX = {1'b0, {(SAMPLE_WIDTH-1){1'b1}}};
    localparam logic signed [SAMPLE_WIDTH-1:0] SAMPLE_MIN = {1'b1, {(SAMPLE_WIDTH-1){1'b0}}};
    localparam logic signed [ACC_WIDTH-1:0] SAMPLE_MAX_EXT = {{(ACC_WIDTH-SAMPLE_WIDTH){1'b0}}, SAMPLE_MAX};
    localparam logic signed [ACC_WIDTH-1:0] SAMPLE_MIN_EXT = {{(ACC_WIDTH-SAMPLE_WIDTH){1'b1}}, SAMPLE_MIN};

    // Reduced-complexity block engine: exploit coefficient symmetry inside the
    // parallel/polyphase organization so mirrored taps share one coefficient
    // multiply after a pre-add.

    logic signed [SAMPLE_WIDTH-1:0] history [0:PARALLELISM-1][0:HISTORY_DEPTH-1];
    logic signed [SAMPLE_WIDTH-1:0] history_next [0:PARALLELISM-1][0:HISTORY_DEPTH-1];
    logic signed [SAMPLE_WIDTH-1:0] output_next [0:PARALLELISM-1];
    logic signed [SAMPLE_WIDTH-1:0] output_pipe [0:PARALLELISM-1];
    logic                           output_pipe_valid;

    function automatic logic signed [ACC_WIDTH-1:0] pair_mult_ext(
        input logic signed [SAMPLE_WIDTH-1:0] sample_a,
        input logic signed [SAMPLE_WIDTH-1:0] sample_b,
        input logic signed [FIR_COEFF_WIDTH-1:0] coeff
    );
        logic signed [PAIR_SUM_WIDTH-1:0] pair_sum;
        logic signed [PRODUCT_WIDTH-1:0] product;
        begin
            pair_sum = {sample_a[SAMPLE_WIDTH-1], sample_a} + {sample_b[SAMPLE_WIDTH-1], sample_b};
            product = pair_sum * coeff;
            pair_mult_ext = {{(ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};
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

    integer lane_idx;
    integer depth_idx;
    integer out_idx;
    integer pair_idx;
    integer low_coeff_idx;
    integer high_coeff_idx;
    integer center_coeff_idx;
    integer low_phase_idx;
    integer high_phase_idx;
    integer center_phase_idx;
    integer low_tap_idx;
    integer high_tap_idx;
    integer center_tap_idx;
    integer low_src_lane;
    integer high_src_lane;
    integer center_src_lane;
    integer low_delay_idx;
    integer high_delay_idx;
    integer center_delay_idx;
    logic signed [ACC_WIDTH-1:0] acc;
    always @* begin
        for (lane_idx = 0; lane_idx < PARALLELISM; lane_idx++) begin
            for (depth_idx = 0; depth_idx < HISTORY_DEPTH; depth_idx++) begin
                history_next[lane_idx][depth_idx] = history[lane_idx][depth_idx];
            end
        end

        if (sample_valid) begin
            for (lane_idx = 0; lane_idx < PARALLELISM; lane_idx++) begin
                history_next[lane_idx][0] = sample_in[lane_idx];
                for (depth_idx = 1; depth_idx < HISTORY_DEPTH; depth_idx++) begin
                    history_next[lane_idx][depth_idx] = history[lane_idx][depth_idx - 1];
                end
            end
        end

        for (out_idx = 0; out_idx < PARALLELISM; out_idx++) begin
            acc = '0;

            for (pair_idx = 0; pair_idx < HALF_TAPS; pair_idx++) begin
                low_coeff_idx = pair_idx;
                high_coeff_idx = FIR_NUM_TAPS - 1 - pair_idx;

                low_phase_idx = low_coeff_idx % PARALLELISM;
                low_tap_idx = low_coeff_idx / PARALLELISM;
                if (low_phase_idx > out_idx) begin
                    low_src_lane = out_idx + PARALLELISM - low_phase_idx;
                    low_delay_idx = low_tap_idx + 1;
                end else begin
                    low_src_lane = out_idx - low_phase_idx;
                    low_delay_idx = low_tap_idx;
                end

                high_phase_idx = high_coeff_idx % PARALLELISM;
                high_tap_idx = high_coeff_idx / PARALLELISM;
                if (high_phase_idx > out_idx) begin
                    high_src_lane = out_idx + PARALLELISM - high_phase_idx;
                    high_delay_idx = high_tap_idx + 1;
                end else begin
                    high_src_lane = out_idx - high_phase_idx;
                    high_delay_idx = high_tap_idx;
                end

                acc = acc + pair_mult_ext(
                    history_next[low_src_lane][low_delay_idx],
                    history_next[high_src_lane][high_delay_idx],
                    fir_coeff(pair_idx)
                );
            end

            if (HAS_CENTER_TAP) begin
                center_coeff_idx = HALF_TAPS;
                center_phase_idx = center_coeff_idx % PARALLELISM;
                center_tap_idx = center_coeff_idx / PARALLELISM;
                if (center_phase_idx > out_idx) begin
                    center_src_lane = out_idx + PARALLELISM - center_phase_idx;
                    center_delay_idx = center_tap_idx + 1;
                end else begin
                    center_src_lane = out_idx - center_phase_idx;
                    center_delay_idx = center_tap_idx;
                end

                acc = acc + pair_mult_ext(
                    history_next[center_src_lane][center_delay_idx],
                    '0,
                    fir_coeff(center_coeff_idx)
                );
            end

            output_next[out_idx] = resize_and_saturate(acc);
        end
    end

    integer reg_lane_idx;
    integer reg_depth_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                for (reg_depth_idx = 0; reg_depth_idx < HISTORY_DEPTH; reg_depth_idx++) begin
                    history[reg_lane_idx][reg_depth_idx] <= '0;
                end
                sample_out[reg_lane_idx] <= '0;
                output_pipe[reg_lane_idx] <= '0;
            end
            output_pipe_valid <= 1'b0;
            sample_out_valid <= 1'b0;
        end else begin
            if (sample_valid) begin
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    for (reg_depth_idx = 0; reg_depth_idx < HISTORY_DEPTH; reg_depth_idx++) begin
                        history[reg_lane_idx][reg_depth_idx] <= history_next[reg_lane_idx][reg_depth_idx];
                    end
                end
            end

            if (OUTPUT_PIPELINE) begin
                if (sample_valid) begin
                    for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                        output_pipe[reg_lane_idx] <= output_next[reg_lane_idx];
                    end
                end
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    sample_out[reg_lane_idx] <= output_pipe[reg_lane_idx];
                end
                sample_out_valid <= output_pipe_valid;
                output_pipe_valid <= sample_valid;
            end else begin
                if (sample_valid) begin
                    for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                        sample_out[reg_lane_idx] <= output_next[reg_lane_idx];
                    end
                end
                sample_out_valid <= sample_valid;
                output_pipe_valid <= 1'b0;
            end
        end
    end

endmodule

module fir_filter_parallel_reduced_stream #(
    parameter int SAMPLE_WIDTH = 16,
    parameter int PARALLELISM = 2,
    parameter bit OUTPUT_PIPELINE = 1'b0
) (
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           sample_valid,
    input  logic signed [SAMPLE_WIDTH-1:0] sample_in,
    output logic                           sample_out_valid,
    output logic signed [SAMPLE_WIDTH-1:0] sample_out
);

    typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;

    localparam int GATHER_COUNT_WIDTH = (PARALLELISM > 1) ? $clog2(PARALLELISM) : 1;
    // The serializer emits one sample per cycle while the block engine can
    // return PARALLELISM samples at once, so the FIFO needs extra headroom to
    // hold a burst plus any already queued outputs.
    localparam int OUTPUT_FIFO_DEPTH = (PARALLELISM * PARALLELISM) + PARALLELISM + 1;
    localparam int FIFO_COUNT_WIDTH = $clog2(OUTPUT_FIFO_DEPTH + 1);

    // Scalar wrapper that gathers samples into blocks for the reduced-
    // complexity block engine, then serializes the block outputs.
    logic                                           block_valid;
    sample_t                                        block_in [0:PARALLELISM-1];
    logic                                           block_out_valid;
    sample_t                                        block_out [0:PARALLELISM-1];
    sample_t                                        gather_buf [0:PARALLELISM-1];
    sample_t                                        gather_buf_next [0:PARALLELISM-1];
    logic        [GATHER_COUNT_WIDTH-1:0]           gather_count;
    logic        [GATHER_COUNT_WIDTH-1:0]           gather_count_next;
    sample_t                                        output_fifo [0:OUTPUT_FIFO_DEPTH-1];
    sample_t                                        output_fifo_next [0:OUTPUT_FIFO_DEPTH-1];
    logic        [FIFO_COUNT_WIDTH-1:0]             output_fifo_count;
    logic        [FIFO_COUNT_WIDTH-1:0]             output_fifo_count_next;
    logic                                           sample_out_valid_next;
    sample_t                                        sample_out_next;

    integer idx;
    integer fifo_idx;
    integer work_count;
    integer effective_fifo_count;

    always @* begin
        block_valid = 1'b0;
        for (idx = 0; idx < PARALLELISM; idx++) begin
            block_in[idx] = '0;
            gather_buf_next[idx] = gather_buf[idx];
        end

        gather_count_next = gather_count;
        if (sample_valid) begin
            if (gather_count == (PARALLELISM - 1)) begin
                block_valid = 1'b1;
                for (idx = 0; idx < PARALLELISM - 1; idx++) begin
                    block_in[idx] = gather_buf[idx];
                end
                block_in[PARALLELISM - 1] = sample_in;
                gather_count_next = '0;
            end else begin
                gather_buf_next[gather_count] = sample_in;
                gather_count_next = gather_count + 1'b1;
            end
        end

        effective_fifo_count = output_fifo_count;
        if (effective_fifo_count > OUTPUT_FIFO_DEPTH) begin
            effective_fifo_count = OUTPUT_FIFO_DEPTH;
        end

        sample_out_valid_next = (effective_fifo_count != 0);
        sample_out_next = (effective_fifo_count != 0) ? output_fifo[0] : '0;

        for (fifo_idx = 0; fifo_idx < OUTPUT_FIFO_DEPTH; fifo_idx++) begin
            output_fifo_next[fifo_idx] = '0;
        end

        work_count = 0;
        if (effective_fifo_count != 0) begin
            for (fifo_idx = 1; fifo_idx < OUTPUT_FIFO_DEPTH; fifo_idx++) begin
                if (fifo_idx < effective_fifo_count) begin
                    output_fifo_next[fifo_idx - 1] = output_fifo[fifo_idx];
                end
            end
            work_count = effective_fifo_count - 1;
        end

        if (block_out_valid) begin
            for (idx = 0; idx < PARALLELISM; idx++) begin
                if ((work_count + idx) < OUTPUT_FIFO_DEPTH) begin
                    output_fifo_next[work_count + idx] = block_out[idx];
                end
            end
            work_count = work_count + PARALLELISM;
        end

        if (work_count > OUTPUT_FIFO_DEPTH) begin
            output_fifo_count_next = OUTPUT_FIFO_DEPTH[FIFO_COUNT_WIDTH-1:0];
        end else begin
            output_fifo_count_next = work_count[FIFO_COUNT_WIDTH-1:0];
        end
    end

    fir_filter_parallel_reduced #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .PARALLELISM(PARALLELISM),
        .OUTPUT_PIPELINE(OUTPUT_PIPELINE)
    ) impl (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(block_valid),
        .sample_in(block_in),
        .sample_out_valid(block_out_valid),
        .sample_out(block_out)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < PARALLELISM; idx++) begin
                gather_buf[idx] <= '0;
            end
            for (fifo_idx = 0; fifo_idx < OUTPUT_FIFO_DEPTH; fifo_idx++) begin
                output_fifo[fifo_idx] <= '0;
            end
            gather_count <= '0;
            output_fifo_count <= '0;
            sample_out_valid <= 1'b0;
            sample_out <= '0;
        end else begin
            for (idx = 0; idx < PARALLELISM; idx++) begin
                gather_buf[idx] <= gather_buf_next[idx];
            end
            for (fifo_idx = 0; fifo_idx < OUTPUT_FIFO_DEPTH; fifo_idx++) begin
                output_fifo[fifo_idx] <= output_fifo_next[fifo_idx];
            end
            gather_count <= gather_count_next;
            output_fifo_count <= output_fifo_count_next;
            sample_out_valid <= sample_out_valid_next;
            sample_out <= sample_out_next;
        end
    end

endmodule

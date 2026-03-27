`timescale 1ns/1ps

module fir_filter_parallel_reduced_pipelined #(
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
    localparam int NUM_PRODUCTS = HALF_TAPS + (HAS_CENTER_TAP ? 1 : 0);
    localparam int PIPE_GROUP1 = 2;
    localparam int PIPE_GROUP2 = 2;
    localparam int PIPE_GROUP3 = 2;
    localparam int PIPE_GROUP4 = 2;
    localparam int NUM_PARTIALS1 = (NUM_PRODUCTS + PIPE_GROUP1 - 1) / PIPE_GROUP1;
    localparam int NUM_PARTIALS2 = (NUM_PARTIALS1 + PIPE_GROUP2 - 1) / PIPE_GROUP2;
    localparam int NUM_PARTIALS3 = (NUM_PARTIALS2 + PIPE_GROUP3 - 1) / PIPE_GROUP3;
    localparam int NUM_PARTIALS4 = (NUM_PARTIALS3 + PIPE_GROUP4 - 1) / PIPE_GROUP4;
    localparam logic signed [SAMPLE_WIDTH-1:0] SAMPLE_MAX = {1'b0, {(SAMPLE_WIDTH-1){1'b1}}};
    localparam logic signed [SAMPLE_WIDTH-1:0] SAMPLE_MIN = {1'b1, {(SAMPLE_WIDTH-1){1'b0}}};
    localparam logic signed [ACC_WIDTH-1:0] SAMPLE_MAX_EXT = {{(ACC_WIDTH-SAMPLE_WIDTH){1'b0}}, SAMPLE_MAX};
    localparam logic signed [ACC_WIDTH-1:0] SAMPLE_MIN_EXT = {{(ACC_WIDTH-SAMPLE_WIDTH){1'b1}}, SAMPLE_MIN};

    logic signed [SAMPLE_WIDTH-1:0] history [0:PARALLELISM-1][0:HISTORY_DEPTH-1];
    logic signed [SAMPLE_WIDTH-1:0] history_next [0:PARALLELISM-1][0:HISTORY_DEPTH-1];
    logic signed [ACC_WIDTH-1:0]    product_terms_next [0:PARALLELISM-1][0:NUM_PRODUCTS-1];
    logic signed [ACC_WIDTH-1:0]    product_terms_pipe [0:PARALLELISM-1][0:NUM_PRODUCTS-1];
    logic signed [ACC_WIDTH-1:0]    partial_sums1_next [0:PARALLELISM-1][0:NUM_PARTIALS1-1];
    logic signed [ACC_WIDTH-1:0]    partial_sums1_pipe [0:PARALLELISM-1][0:NUM_PARTIALS1-1];
    logic signed [ACC_WIDTH-1:0]    partial_sums2_next [0:PARALLELISM-1][0:NUM_PARTIALS2-1];
    logic signed [ACC_WIDTH-1:0]    partial_sums2_pipe [0:PARALLELISM-1][0:NUM_PARTIALS2-1];
    logic signed [ACC_WIDTH-1:0]    partial_sums3_next [0:PARALLELISM-1][0:NUM_PARTIALS3-1];
    logic signed [ACC_WIDTH-1:0]    partial_sums3_pipe [0:PARALLELISM-1][0:NUM_PARTIALS3-1];
    logic signed [ACC_WIDTH-1:0]    partial_sums4_next [0:PARALLELISM-1][0:NUM_PARTIALS4-1];
    logic signed [ACC_WIDTH-1:0]    partial_sums4_pipe [0:PARALLELISM-1][0:NUM_PARTIALS4-1];
    logic signed [ACC_WIDTH-1:0]    final_sum_next [0:PARALLELISM-1];
    logic signed [ACC_WIDTH-1:0]    final_sum_pipe [0:PARALLELISM-1];
    logic signed [SAMPLE_WIDTH-1:0] output_next [0:PARALLELISM-1];
    logic signed [SAMPLE_WIDTH-1:0] output_pipe [0:PARALLELISM-1];
    logic                           product_terms_valid;
    logic                           partial_sums1_valid;
    logic                           partial_sums2_valid;
    logic                           partial_sums3_valid;
    logic                           partial_sums4_valid;
    logic                           final_sum_valid;
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
    integer product_idx;
    integer group_idx;
    integer term_idx;
    integer start_idx;
    integer end_idx;
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
            for (product_idx = 0; product_idx < NUM_PRODUCTS; product_idx++) begin
                product_terms_next[out_idx][product_idx] = '0;
            end

            product_idx = 0;
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

                product_terms_next[out_idx][product_idx] = pair_mult_ext(
                    history_next[low_src_lane][low_delay_idx],
                    history_next[high_src_lane][high_delay_idx],
                    fir_coeff(pair_idx)
                );
                product_idx = product_idx + 1;
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

                product_terms_next[out_idx][product_idx] = pair_mult_ext(
                    history_next[center_src_lane][center_delay_idx],
                    '0,
                    fir_coeff(center_coeff_idx)
                );
            end

            for (group_idx = 0; group_idx < NUM_PARTIALS1; group_idx++) begin
                acc = '0;
                start_idx = group_idx * PIPE_GROUP1;
                end_idx = start_idx + PIPE_GROUP1;
                for (term_idx = start_idx; term_idx < end_idx; term_idx++) begin
                    if (term_idx < NUM_PRODUCTS) begin
                        acc = acc + product_terms_pipe[out_idx][term_idx];
                    end
                end
                partial_sums1_next[out_idx][group_idx] = acc;
            end

            for (group_idx = 0; group_idx < NUM_PARTIALS2; group_idx++) begin
                acc = '0;
                start_idx = group_idx * PIPE_GROUP2;
                end_idx = start_idx + PIPE_GROUP2;
                for (term_idx = start_idx; term_idx < end_idx; term_idx++) begin
                    if (term_idx < NUM_PARTIALS1) begin
                        acc = acc + partial_sums1_pipe[out_idx][term_idx];
                    end
                end
                partial_sums2_next[out_idx][group_idx] = acc;
            end

            for (group_idx = 0; group_idx < NUM_PARTIALS3; group_idx++) begin
                acc = '0;
                start_idx = group_idx * PIPE_GROUP3;
                end_idx = start_idx + PIPE_GROUP3;
                for (term_idx = start_idx; term_idx < end_idx; term_idx++) begin
                    if (term_idx < NUM_PARTIALS2) begin
                        acc = acc + partial_sums2_pipe[out_idx][term_idx];
                    end
                end
                partial_sums3_next[out_idx][group_idx] = acc;
            end

            for (group_idx = 0; group_idx < NUM_PARTIALS4; group_idx++) begin
                acc = '0;
                start_idx = group_idx * PIPE_GROUP4;
                end_idx = start_idx + PIPE_GROUP4;
                for (term_idx = start_idx; term_idx < end_idx; term_idx++) begin
                    if (term_idx < NUM_PARTIALS3) begin
                        acc = acc + partial_sums3_pipe[out_idx][term_idx];
                    end
                end
                partial_sums4_next[out_idx][group_idx] = acc;
            end

            acc = '0;
            for (group_idx = 0; group_idx < NUM_PARTIALS4; group_idx++) begin
                acc = acc + partial_sums4_pipe[out_idx][group_idx];
            end
            final_sum_next[out_idx] = acc;

            output_next[out_idx] = resize_and_saturate(final_sum_pipe[out_idx]);
        end
    end

    integer reg_lane_idx;
    integer reg_depth_idx;
    integer reg_product_idx;
    integer reg_group_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                for (reg_depth_idx = 0; reg_depth_idx < HISTORY_DEPTH; reg_depth_idx++) begin
                    history[reg_lane_idx][reg_depth_idx] <= '0;
                end
                for (reg_product_idx = 0; reg_product_idx < NUM_PRODUCTS; reg_product_idx++) begin
                    product_terms_pipe[reg_lane_idx][reg_product_idx] <= '0;
                end
                for (reg_group_idx = 0; reg_group_idx < NUM_PARTIALS1; reg_group_idx++) begin
                    partial_sums1_pipe[reg_lane_idx][reg_group_idx] <= '0;
                end
                for (reg_group_idx = 0; reg_group_idx < NUM_PARTIALS2; reg_group_idx++) begin
                    partial_sums2_pipe[reg_lane_idx][reg_group_idx] <= '0;
                end
                for (reg_group_idx = 0; reg_group_idx < NUM_PARTIALS3; reg_group_idx++) begin
                    partial_sums3_pipe[reg_lane_idx][reg_group_idx] <= '0;
                end
                for (reg_group_idx = 0; reg_group_idx < NUM_PARTIALS4; reg_group_idx++) begin
                    partial_sums4_pipe[reg_lane_idx][reg_group_idx] <= '0;
                end
                final_sum_pipe[reg_lane_idx] <= '0;
                sample_out[reg_lane_idx] <= '0;
                output_pipe[reg_lane_idx] <= '0;
            end
            product_terms_valid <= 1'b0;
            partial_sums1_valid <= 1'b0;
            partial_sums2_valid <= 1'b0;
            partial_sums3_valid <= 1'b0;
            partial_sums4_valid <= 1'b0;
            final_sum_valid <= 1'b0;
            output_pipe_valid <= 1'b0;
            sample_out_valid <= 1'b0;
        end else begin
            if (sample_valid) begin
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    for (reg_depth_idx = 0; reg_depth_idx < HISTORY_DEPTH; reg_depth_idx++) begin
                        history[reg_lane_idx][reg_depth_idx] <= history_next[reg_lane_idx][reg_depth_idx];
                    end
                    for (reg_product_idx = 0; reg_product_idx < NUM_PRODUCTS; reg_product_idx++) begin
                        product_terms_pipe[reg_lane_idx][reg_product_idx] <= product_terms_next[reg_lane_idx][reg_product_idx];
                    end
                end
            end

            if (product_terms_valid) begin
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    for (reg_group_idx = 0; reg_group_idx < NUM_PARTIALS1; reg_group_idx++) begin
                        partial_sums1_pipe[reg_lane_idx][reg_group_idx] <= partial_sums1_next[reg_lane_idx][reg_group_idx];
                    end
                end
            end

            if (partial_sums1_valid) begin
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    for (reg_group_idx = 0; reg_group_idx < NUM_PARTIALS2; reg_group_idx++) begin
                        partial_sums2_pipe[reg_lane_idx][reg_group_idx] <= partial_sums2_next[reg_lane_idx][reg_group_idx];
                    end
                end
            end

            if (partial_sums2_valid) begin
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    for (reg_group_idx = 0; reg_group_idx < NUM_PARTIALS3; reg_group_idx++) begin
                        partial_sums3_pipe[reg_lane_idx][reg_group_idx] <= partial_sums3_next[reg_lane_idx][reg_group_idx];
                    end
                end
            end

            if (partial_sums3_valid) begin
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    for (reg_group_idx = 0; reg_group_idx < NUM_PARTIALS4; reg_group_idx++) begin
                        partial_sums4_pipe[reg_lane_idx][reg_group_idx] <= partial_sums4_next[reg_lane_idx][reg_group_idx];
                    end
                end
            end

            if (partial_sums4_valid) begin
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    final_sum_pipe[reg_lane_idx] <= final_sum_next[reg_lane_idx];
                end
            end

            product_terms_valid <= sample_valid;
            partial_sums1_valid <= product_terms_valid;
            partial_sums2_valid <= partial_sums1_valid;
            partial_sums3_valid <= partial_sums2_valid;
            partial_sums4_valid <= partial_sums3_valid;
            final_sum_valid <= partial_sums4_valid;

            if (OUTPUT_PIPELINE) begin
                if (final_sum_valid) begin
                    for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                        output_pipe[reg_lane_idx] <= output_next[reg_lane_idx];
                    end
                end
                for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                    sample_out[reg_lane_idx] <= output_pipe[reg_lane_idx];
                end
                sample_out_valid <= output_pipe_valid;
                output_pipe_valid <= final_sum_valid;
            end else begin
                if (final_sum_valid) begin
                    for (reg_lane_idx = 0; reg_lane_idx < PARALLELISM; reg_lane_idx++) begin
                        sample_out[reg_lane_idx] <= output_next[reg_lane_idx];
                    end
                end
                sample_out_valid <= final_sum_valid;
                output_pipe_valid <= 1'b0;
            end
        end
    end

endmodule

module fir_filter_parallel_reduced_pipelined_stream #(
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
    localparam int OUTPUT_FIFO_DEPTH = (PARALLELISM * PARALLELISM) + PARALLELISM + 1;
    localparam int FIFO_COUNT_WIDTH = $clog2(OUTPUT_FIFO_DEPTH + 1);

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

    fir_filter_parallel_reduced_pipelined #(
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

`timescale 1ns/1ps

module fir_filter_required_regression_tb;

    import fir_coeffs_pkg::*;

    localparam int SAMPLE_WIDTH = 16;
    localparam int IMPULSE_VALID_SAMPLES = FIR_NUM_TAPS + 8;
    localparam int RANDOM_VALID_SAMPLES = 256;
    localparam int SINE_VALID_SAMPLES = 256;
    localparam int FLUSH_VALID_SAMPLES = 7;
    localparam int TOTAL_VALID_SAMPLES = IMPULSE_VALID_SAMPLES + RANDOM_VALID_SAMPLES + SINE_VALID_SAMPLES + FLUSH_VALID_SAMPLES;
    localparam int DRAIN_CYCLES = FIR_NUM_TAPS + 64;

    typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;

    integer score_idx;

`include "fir_test_utils.svh"

    `FIR_RANDOM_SAMPLE_FN
    `FIR_SINE_SAMPLE_FN

    logic clk;
    logic rst_n;
    logic sample_valid;
    sample_t sample_in;

    logic baseline_out_valid;
    sample_t baseline_out;
    logic pipelined_out_valid;
    sample_t pipelined_out;
    logic l2r_out_valid;
    sample_t l2r_out;
    logic l3r_out_valid;
    sample_t l3r_out;
    logic l3pr_out_valid;
    sample_t l3pr_out;

    sample_t expected_stream [0:TOTAL_VALID_SAMPLES-1];

    integer mismatch_count;
    integer expected_write_idx;
    integer pipelined_read_idx;
    integer l2r_read_idx;
    integer l3r_read_idx;
    integer l3pr_read_idx;

    fir_filter #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) dut_baseline (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .sample_out_valid(baseline_out_valid),
        .sample_out(baseline_out)
    );

    fir_filter_pipelined #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) dut_pipelined (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .sample_out_valid(pipelined_out_valid),
        .sample_out(pipelined_out)
    );

    fir_filter_l2_reduced #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) dut_l2r (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .sample_out_valid(l2r_out_valid),
        .sample_out(l2r_out)
    );

    fir_filter_l3_reduced #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) dut_l3r (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .sample_out_valid(l3r_out_valid),
        .sample_out(l3r_out)
    );

    fir_filter_pipelined_l3_reduced #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) dut_l3pr (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .sample_out_valid(l3pr_out_valid),
        .sample_out(l3pr_out)
    );

    function automatic sample_t stimulus_sample(input int sample_idx);
        begin
            if (sample_idx < IMPULSE_VALID_SAMPLES) begin
                stimulus_sample = (sample_idx == 0) ? 16'sh4000 : '0;
            end else if (sample_idx < IMPULSE_VALID_SAMPLES + RANDOM_VALID_SAMPLES) begin
                stimulus_sample = random_sample(sample_idx - IMPULSE_VALID_SAMPLES);
            end else if (sample_idx < IMPULSE_VALID_SAMPLES + RANDOM_VALID_SAMPLES + SINE_VALID_SAMPLES) begin
                stimulus_sample = sine_sample(sample_idx - IMPULSE_VALID_SAMPLES - RANDOM_VALID_SAMPLES, 20000.0, 29.0);
            end else begin
                stimulus_sample = '0;
            end
        end
    endfunction

    task automatic check_against_baseline(
        input logic valid,
        input sample_t actual,
        inout integer read_idx,
        input string tag
    );
        begin
            if (valid) begin
                if (read_idx >= expected_write_idx) begin
                    $display("ERROR: %s produced output before baseline reference was available", tag);
                    mismatch_count++;
                end else if (actual !== expected_stream[read_idx]) begin
                    $display(
                        "ERROR: %s output %0d expected %0d got %0d",
                        tag,
                        read_idx,
                        expected_stream[read_idx],
                        actual
                    );
                    mismatch_count++;
                end
                read_idx++;
            end
        end
    endtask

    task automatic step_and_check(
        input logic next_valid,
        input sample_t next_sample,
        input string tag,
        input int idx
    );
        begin
            sample_valid = next_valid;
            sample_in = next_sample;
            @(posedge clk);
            #1;

            if (baseline_out_valid) begin
                expected_stream[expected_write_idx] = baseline_out;
                expected_write_idx++;
            end

            if (next_valid && !baseline_out_valid) begin
                $display("ERROR: baseline missing valid for %s sample %0d", tag, idx);
                mismatch_count++;
            end

            if (!next_valid && baseline_out_valid) begin
                $display("ERROR: baseline asserted valid during idle step %s", tag);
                mismatch_count++;
            end

            check_against_baseline(pipelined_out_valid, pipelined_out, pipelined_read_idx, "pipelined");
            check_against_baseline(l2r_out_valid, l2r_out, l2r_read_idx, "l2_reduced");
            check_against_baseline(l3r_out_valid, l3r_out, l3r_read_idx, "l3_reduced");
            check_against_baseline(l3pr_out_valid, l3pr_out, l3pr_read_idx, "pipelined_l3_reduced");
        end
    endtask

    always #5 clk = ~clk;

    integer idx;
    initial begin
        $dumpfile("fir_filter_required_regression_tb.vcd");
        $dumpvars(0, fir_filter_required_regression_tb);

        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid = 1'b0;
        sample_in = '0;
        mismatch_count = 0;
        expected_write_idx = 0;
        pipelined_read_idx = 0;
        l2r_read_idx = 0;
        l3r_read_idx = 0;
        l3pr_read_idx = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        step_and_check(1'b0, '0, "post-reset idle", 0);

        for (idx = 0; idx < IMPULSE_VALID_SAMPLES; idx++) begin
            step_and_check(1'b1, stimulus_sample(idx), "impulse", idx);
        end

        step_and_check(1'b0, '0, "impulse gap", 0);

        for (idx = 0; idx < RANDOM_VALID_SAMPLES; idx++) begin
            step_and_check(1'b1, stimulus_sample(IMPULSE_VALID_SAMPLES + idx), "random", idx);
            if ((idx % 17) == 16) begin
                step_and_check(1'b0, '0, "random gap", idx);
            end
        end

        for (idx = 0; idx < SINE_VALID_SAMPLES; idx++) begin
            step_and_check(1'b1, stimulus_sample(IMPULSE_VALID_SAMPLES + RANDOM_VALID_SAMPLES + idx), "sine", idx);
            if ((idx % 23) == 22) begin
                step_and_check(1'b0, '0, "sine gap", idx);
            end
        end

        for (idx = 0; idx < FLUSH_VALID_SAMPLES; idx++) begin
            step_and_check(1'b1, '0, "flush", idx);
        end

        for (idx = 0; idx < DRAIN_CYCLES; idx++) begin
            step_and_check(1'b0, '0, "drain", idx);
        end

        if (expected_write_idx != TOTAL_VALID_SAMPLES) begin
            $display("ERROR: baseline produced %0d outputs, expected %0d", expected_write_idx, TOTAL_VALID_SAMPLES);
            mismatch_count++;
        end

        if (pipelined_read_idx != expected_write_idx) begin
            $display("ERROR: pipelined consumed %0d expected outputs, baseline produced %0d", pipelined_read_idx, expected_write_idx);
            mismatch_count++;
        end
        if (l2r_read_idx != expected_write_idx) begin
            $display("ERROR: l2_reduced consumed %0d expected outputs, baseline produced %0d", l2r_read_idx, expected_write_idx);
            mismatch_count++;
        end
        if (l3r_read_idx != expected_write_idx) begin
            $display("ERROR: l3_reduced consumed %0d expected outputs, baseline produced %0d", l3r_read_idx, expected_write_idx);
            mismatch_count++;
        end
        if (l3pr_read_idx != expected_write_idx) begin
            $display("ERROR: pipelined_l3_reduced consumed %0d expected outputs, baseline produced %0d", l3pr_read_idx, expected_write_idx);
            mismatch_count++;
        end

        if (mismatch_count == 0) begin
            $display("PASS: selected architecture regressions match the baseline across impulse, random, and sine stimulus.");
        end else begin
            $display("FAIL: detected %0d mismatches in selected architecture regressions.", mismatch_count);
            $fatal(1);
        end

        $finish;
    end

endmodule

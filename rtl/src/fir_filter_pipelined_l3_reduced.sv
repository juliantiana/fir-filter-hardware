`timescale 1ns/1ps

module fir_filter_pipelined_l3_reduced #(
    parameter int SAMPLE_WIDTH = 16
) (
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           sample_valid,
    input  logic signed [SAMPLE_WIDTH-1:0] sample_in,
    output logic                           sample_out_valid,
    output logic signed [SAMPLE_WIDTH-1:0] sample_out
);

    // Symmetry-aware reduced-complexity pipelined L=3 architecture.
    fir_filter_parallel_reduced_pipelined_stream #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .PARALLELISM(3),
        .OUTPUT_PIPELINE(1'b1)
    ) impl (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .sample_out_valid(sample_out_valid),
        .sample_out(sample_out)
    );

endmodule

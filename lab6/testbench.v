`timescale 1ns/1ps

module testbench;

// ======================================================
// wires between PATTERN <-> DUT
// ======================================================
wire        clk;
wire        rst_n;
wire        in_valid;
wire [2:0]  in_weight;
wire        out_mode;

wire        out_valid;
wire        out_code;

// ======================================================
// DUT
// ======================================================
HT_TOP dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .in_weight (in_weight),
    .out_mode  (out_mode),
    .out_valid (out_valid),
    .out_code  (out_code)
);

// ======================================================
// PATTERN
// ======================================================
PATTERN pattern (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .in_weight (in_weight),
    .out_mode  (out_mode),
    .out_valid (out_valid),
    .out_code  (out_code)
);

endmodule

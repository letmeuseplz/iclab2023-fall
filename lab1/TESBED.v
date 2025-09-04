`timescale 1ns/1ps

module TESTBENCH;

// ---------------------------
// Wire/Reg 宣告
// ---------------------------
wire clk, rst_n;
wire in_valid, direction;
wire [12:0] addr_dram;
wire [15:0] addr_sd;
wire out_valid;
wire [7:0] out_data;

// AXI-like DRAM <-> BRIDGE
wire AR_VALID, AR_READY;
wire [12:0] AR_ADDR;
wire R_VALID, R_READY;
wire [63:0] R_DATA;
wire [1:0] R_RESP;

wire AW_VALID, AW_READY;
wire [12:0] AW_ADDR;
wire W_VALID, W_READY;
wire [63:0] W_DATA;
wire B_VALID, B_READY;
wire [1:0] B_RESP;

// SPI-like SD <-> BRIDGE
wire SD_clk;
wire MOSI, MISO;

// ---------------------------
// DUT: BRIDGE
// ---------------------------
BRIDGE u_BRIDGE (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .direction(direction),
    .addr_dram(addr_dram),
    .addr_sd(addr_sd),
    .out_valid(out_valid),
    .out_data(out_data),

    // DRAM AXI-like
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),

    // SD interface
    .SD_clk(SD_clk), .MOSI(MOSI), .MISO(MISO)
);

// ---------------------------
// PATTERN (測資產生器)
// ---------------------------
PATTERN u_PATTERN (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .direction(direction),
    .addr_dram(addr_dram),
    .addr_sd(addr_sd),
    .out_valid(out_valid),
    .out_data(out_data)
);

// ---------------------------
// pseudo_DRAM
// ---------------------------
pseudo_DRAM u_DRAM (
    .clk(clk),
    .rst_n(rst_n),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP)
);

// ---------------------------
// pseudo_SD
// ---------------------------
pseudo_SD u_SD (
    .clk(SD_clk),
    .MOSI(MOSI),
    .MISO(MISO)
);

endmodule

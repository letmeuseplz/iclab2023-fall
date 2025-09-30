`timescale 1ns/1ps

module tb;

// 宣告所有 wire
wire [2:0] W_0, V_GS_0, V_DS_0;
wire [2:0] W_1, V_GS_1, V_DS_1;
wire [2:0] W_2, V_GS_2, V_DS_2;
wire [2:0] W_3, V_GS_3, V_DS_3;
wire [2:0] W_4, V_GS_4, V_DS_4;
wire [2:0] W_5, V_GS_5, V_DS_5;
wire [1:0] mode;
wire [7:0] out_n;

// ========= 實例化 Design Under Test (SMC) =========
SMC uut (
    .mode(mode),
    .W_0(W_0), .V_GS_0(V_GS_0), .V_DS_0(V_DS_0),
    .W_1(W_1), .V_GS_1(V_GS_1), .V_DS_1(V_DS_1),
    .W_2(W_2), .V_GS_2(V_GS_2), .V_DS_2(V_DS_2),
    .W_3(W_3), .V_GS_3(V_GS_3), .V_DS_3(V_DS_3),
    .W_4(W_4), .V_GS_4(V_GS_4), .V_DS_4(V_DS_4),
    .W_5(W_5), .V_GS_5(V_GS_5), .V_DS_5(V_DS_5),
    .out_n(out_n)
);

// ========= 實例化 PATTERN（test pattern generator） =========
PATTERN pattern (
    .mode(mode),
    .W_0(W_0), .V_GS_0(V_GS_0), .V_DS_0(V_DS_0),
    .W_1(W_1), .V_GS_1(V_GS_1), .V_DS_1(V_DS_1),
    .W_2(W_2), .V_GS_2(V_GS_2), .V_DS_2(V_DS_2),
    .W_3(W_3), .V_GS_3(V_GS_3), .V_DS_3(V_DS_3),
    .W_4(W_4), .V_GS_4(V_GS_4), .V_DS_4(V_DS_4),
    .W_5(W_5), .V_GS_5(V_GS_5), .V_DS_5(V_DS_5),
    .out_n(out_n)
);

endmodule

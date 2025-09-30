`timescale 1ns/1ps

module tb;

  // Inputs
  reg [2:0] W_0, V_GS_0, V_DS_0;
  reg [2:0] W_1, V_GS_1, V_DS_1;
  reg [2:0] W_2, V_GS_2, V_DS_2;
  reg [2:0] W_3, V_GS_3, V_DS_3;
  reg [2:0] W_4, V_GS_4, V_DS_4;
  reg [2:0] W_5, V_GS_5, V_DS_5;
  reg [1:0] mode;

  // Output
  wire [7:0] out_n;

  // Instantiate the SMC module
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

  // Stimulus
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);

    // Test Case 1
    mode = 2'b01;  // max mode
    W_0 = 3'd3; V_GS_0 = 3'd2; V_DS_0 = 3'd1;
    W_1 = 3'd4; V_GS_1 = 3'd2; V_DS_1 = 3'd2;
    W_2 = 3'd2; V_GS_2 = 3'd1; V_DS_2 = 3'd3;
    W_3 = 3'd5; V_GS_3 = 3'd1; V_DS_3 = 3'd1;
    W_4 = 3'd1; V_GS_4 = 3'd2; V_DS_4 = 3'd3;
    W_5 = 3'd3; V_GS_5 = 3'd2; V_DS_5 = 3'd2;
    #10;

    // Test Case 2
    mode = 2'b00;  // min mode
    W_0 = 3'd1; V_GS_0 = 3'd1; V_DS_0 = 3'd1;
    W_1 = 3'd2; V_GS_1 = 3'd2; V_DS_1 = 3'd2;
    W_2 = 3'd3; V_GS_2 = 3'd3; V_DS_2 = 3'd3;
    W_3 = 3'd4; V_GS_3 = 3'd1; V_DS_3 = 3'd2;
    W_4 = 3'd2; V_GS_4 = 3'd2; V_DS_4 = 3'd1;
    W_5 = 3'd1; V_GS_5 = 3'd3; V_DS_5 = 3'd2;
    #10;

    $finish;
  end

  // Display output
  initial begin
    $monitor("Time = %0t | mode = %b | out_n = %d", $time, mode, out_n);
  end

endmodule

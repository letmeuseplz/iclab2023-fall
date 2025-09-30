
`timescale 1ns/10ps
/*
`include "PATTERN.v"
*/
`ifdef RTL
  `include "SMC.v"
`endif
`ifdef GATE
  `include "./Netlist/SMC_SYN.v"
`endif
            
module TESTBENCH; 

//Connection wires
wire [2:0] W_0,V_GS_0,V_DS_0;
wire [2:0] W_1,V_GS_1,V_DS_1;
wire [2:0] W_2,V_GS_2,V_DS_2;
wire [2:0] W_3,V_GS_3,V_DS_3;
wire [2:0] W_4,V_GS_4,V_DS_4;
wire [2:0] W_5,V_GS_5,V_DS_5;
wire [7:0] out_n; 
wire [1:0] mode;


initial begin
/*
  `ifdef RTL
    $fsdbDumpfile("CC.fsdb");
  $fsdbDumpvars(0,"+mda");
    $fsdbDumpvars();
  `endif
*/
  `ifdef GATE
    $sdf_annotate("./Netlist/SMC_SYN.sdf", inst_SMC);
    //$fsdbDumpfile("CC_SYN.fsdb");
  //$fsdbDumpvars(0,"+mda");
    //$fsdbDumpvars();    
  `endif
end


  SMC inst_SMC
    (
      .W_0    (W_0),
      .V_GS_0 (V_GS_0),
      .V_DS_0 (V_DS_0),
      .W_1    (W_1),
      .V_GS_1 (V_GS_1),
      .V_DS_1 (V_DS_1),
      .W_2    (W_2),
      .V_GS_2 (V_GS_2),
      .V_DS_2 (V_DS_2),
      .W_3    (W_3),
      .V_GS_3 (V_GS_3),
      .V_DS_3 (V_DS_3),
      .W_4    (W_4),
      .V_GS_4 (V_GS_4),
      .V_DS_4 (V_DS_4),
      .W_5    (W_5),
      .V_GS_5 (V_GS_5),
      .V_DS_5 (V_DS_5),
      .mode   (mode),
      .out_n  (out_n)
    );


  PATTERN inst_PATTERN
    (
      .W_0    (W_0),
      .V_GS_0 (V_GS_0),
      .V_DS_0 (V_DS_0),
      .W_1    (W_1),
      .V_GS_1 (V_GS_1),
      .V_DS_1 (V_DS_1),
      .W_2    (W_2),
      .V_GS_2 (V_GS_2),
      .V_DS_2 (V_DS_2),
      .W_3    (W_3),
      .V_GS_3 (V_GS_3),
      .V_DS_3 (V_DS_3),
      .W_4    (W_4),
      .V_GS_4 (V_GS_4),
      .V_DS_4 (V_DS_4),
      .W_5    (W_5),
      .V_GS_5 (V_GS_5),
      .V_DS_5 (V_DS_5),
      .mode   (mode),
      .out_n  (out_n)
    );

 
endmodule
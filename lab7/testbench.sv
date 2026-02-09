`timescale 1ns/1ps

//`ifdef RTL
  //  `include "prng.v" 
//`endif

//`ifdef GATE
//    `include "PRGN_TOP_SYN.v" // ??…å«??ˆæ?å?Œç?? Gate-level è¨­è??
//`endif

//`include "pattern.sv" 

module TESTBED;
    // ---------------------------------------------------------
    // Wires for Connection
    // ---------------------------------------------------------
    wire        clk1, clk2, clk3;
    wire        rst_n;
    wire        in_valid;
    wire [31:0] seed;
    wire        out_valid;
    wire [31:0] rand_num;

    // ---------------------------------------------------------
    // Design Under Test (DUT) Instantiation
    // ---------------------------------------------------------
    prng u_PRGN_TOP (
        .clk1(clk1),
        .clk2(clk2),
        .clk3(clk3),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .seed(seed),
        .out_valid(out_valid),
        .rand_num(rand_num)
    );

    // ---------------------------------------------------------
    // PATTERN Instantiation
    // ---------------------------------------------------------
    pattern u_PATTERN (
        .clk1(clk1),
        .clk2(clk2),
        .clk3(clk3),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .seed(seed),
        .out_valid(out_valid),
        .rand_num(rand_num)
    );

    // ---------------------------------------------------------
    // Dump Waveform (?”¨?–¼ Verdi ??? Vivado)
    // ---------------------------------------------------------
 //   initial begin
    //    `ifdef RTL
            // å¦‚æ?œæ˜¯?œ¨å·¥ä?œç?™ç’°å¢ƒï?Œä½¿?”¨ Verdi
     //       $fsdbDumpfile("PRGN.fsdb");
    //        $fsdbDumpvars(0, TESTBED, "+mda");
    //    `endif
        
        // å¦‚æ?œæ˜¯?œ¨ Vivadoï¼Œé?™æ®µæ²’ç”¨ï¼ŒVivado ??‰è‡ªå·±ç?„æ³¢å½¢è¨­å®?
 //   end

endmodule
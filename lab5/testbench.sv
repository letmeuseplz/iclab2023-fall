`timescale 1ns/1ps
`include "PATTERN.v"
`ifdef RTL
  `include "TMIP.v"
`elsif GATE
  `include "TMIP_SYN.v"
`endif

module TESTBED;
    wire         clk;
    wire         rst_n;
    wire         in_valid;
    wire         in_valid2;
    wire [7:0]   image;
    wire [7:0]   template;
    wire [1:0]   image_size;
    wire [2:0]   action;
    wire         out_valid;
    wire [19:0]  out_value;

    initial begin
        `ifdef RTL
            $fsdbDumpfile("TMIP.fsdb");
            $fsdbDumpvars(0, "+mda");
        `elsif GATE
            $fsdbDumpfile("TMIP_SYN.fsdb");
            $sdf_annotate("TMIP.sdf", I_TMIP);
            $fsdbDumpvars(0, "+mda");
        `endif
    end

    TMIP I_TMIP (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_valid2(in_valid2),
        .image(image),
        .template(template),
        .image_size(image_size),
        .action(action),
        .out_valid(out_valid),
        .out_value(out_value)
    );

    PATTERN I_PATTERN (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_valid2(in_valid2),
        .image(image),
        .template(template),
        .image_size(image_size),
        .action(action),
        .out_valid(out_valid),
        .out_value(out_value)
    );
endmodule
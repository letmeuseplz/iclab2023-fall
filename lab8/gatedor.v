`timescale 1ns/1ps

module GATED_OR (
    input  CLOCK,
    input  SLEEP_CTRL,
    input  RST_N,
    output CLOCK_GATED
);

    reg enable_latch;

    always @(*) begin
        if (!CLOCK) begin
           
            enable_latch = ~SLEEP_CTRL;
        end
    end


    assign CLOCK_GATED = CLOCK & enable_latch;

endmodule
`timescale 1ns/1ps
`define CYCLE_TIME 12

module PATTERN(
    output reg        clk,
    output reg        rst_n,
    output reg        in_valid,
    output reg [2:0]  in_weight,
    output reg        out_mode,

    input             out_valid,
    input             out_code
);

//======================================
// clock
//======================================
initial clk = 0;
always #(`CYCLE_TIME/2) clk = ~clk;

//======================================
// file handle
//======================================
integer fin, fgold;
integer pat_cnt;

//======================================
// input buffer
//======================================
integer w[0:7];
integer mode_buf;

//======================================
// golden buffer
//======================================
reg [1023:0] golden;
integer golden_len;

// DUT output buffer
reg [1023:0] dut_bits;
integer out_cnt;

//======================================
// latency
//======================================
integer latency;

//======================================
// main
//======================================
initial begin
    rst_n     = 1'b1;
    in_valid  = 1'b0;
    in_weight = 'bx;
    out_mode  = 1'b0;

    fin   = $fopen("input.txt",  "r");
    fgold = $fopen("golden.txt", "r");

    if (fin == 0 || fgold == 0) begin
        $display("❌ FILE OPEN ERROR");
        $finish;
    end

    reset_task;

    pat_cnt = 0;
    while (!$feof(fin)) begin
        read_input_task;
        read_golden_task;

        send_pattern_task;
        wait_out_valid_task;
        check_output_task;

        $display("✅ PASS pattern %0d, latency=%0d",
                  pat_cnt, latency);
        pat_cnt = pat_cnt + 1;
    end

    $display("====================================");
    $display("   🎉 ALL PATTERNS PASS");
    $display("====================================");
    $finish;
end

//======================================
// TASK: reset
//======================================
task reset_task;
begin
    rst_n = 1'b0;
    #(5 * `CYCLE_TIME);
    rst_n = 1'b1;
end
endtask

//======================================
// TASK: read input
//======================================
task read_input_task;
begin
    $fscanf(fin, "%d %d %d %d %d %d %d %d %d\n",
            w[0], w[1], w[2], w[3],
            w[4], w[5], w[6], w[7],
            mode_buf);
end
endtask

//======================================
// TASK: read golden
//======================================
task read_golden_task;
    integer c;
    integer done;
begin
    golden_len = 0;
    done = 0;

    while (done == 0) begin
        c = $fgetc(fgold);
        if (c == 8'd10 || c == -1)
            done = 1;
        else begin
            golden[golden_len] = (c == 8'd49); // '1'
            golden_len = golden_len + 1;
        end
    end
end
endtask

//======================================
// TASK: send pattern
//======================================
task send_pattern_task;
    integer i;
begin
    repeat(2) @(negedge clk);

    @(negedge clk);
    in_valid = 1'b1;
    out_mode = mode_buf[0];

    for (i = 0; i < 8; i = i + 1) begin
        in_weight = w[i][2:0];
        @(negedge clk);
    end

    in_valid  = 1'b0;
    in_weight = 'bx;
end
endtask

//======================================
// TASK: wait out_valid
//======================================
task wait_out_valid_task;
begin
    latency = 0;
    while (out_valid !== 1'b1) begin
        latency = latency + 1;
        if (latency > 2000) begin
            $display("❌ LATENCY FAIL");
            $finish;
        end
        @(negedge clk);
    end
end
endtask

//======================================
// TASK: dump golden bits
//======================================
task dump_golden_task;
    integer i;
begin
    $display("Golden bits (%0d):", golden_len);
    $write("  ");
    for (i = 0; i < golden_len; i = i + 1)
        $write("%0d", golden[i]);
    $write("\n");
end
endtask

//======================================
// TASK: dump DUT bits
//======================================
task dump_dut_task;
    integer i;
begin
    $display("DUT bits (%0d):", out_cnt);
    $write("  ");
    for (i = 0; i < out_cnt; i = i + 1)
        $write("%0d", dut_bits[i]);
    $write("\n");
end
endtask

//======================================
// TASK: check output (FULL DEBUG)
//======================================
task check_output_task;
begin
    out_cnt = 0;

    while (out_valid === 1'b1) begin
        dut_bits[out_cnt] = out_code;

        if (out_code !== golden[out_cnt]) begin
            $display("====================================");
            $display("❌ OUTPUT MISMATCH");
            $display("Pattern row   : %0d", pat_cnt);
            $display("Bit index     : %0d", out_cnt);
            $display("Expected bit  : %0d", golden[out_cnt]);
            $display("Got bit       : %0d", out_code);
            dump_golden_task;
            dump_dut_task;
            $display("====================================");
            $finish;
        end

        out_cnt = out_cnt + 1;
        @(negedge clk);
    end

    if (out_cnt !== golden_len) begin
        $display("====================================");
        $display("❌ OUTPUT LENGTH ERROR");
        $display("Pattern row   : %0d", pat_cnt);
        $display("Expected len  : %0d", golden_len);
        $display("Got len       : %0d", out_cnt);
        dump_golden_task;
        dump_dut_task;
        $display("====================================");
        $finish;
    end

    @(negedge clk);
    out_mode = 1'b0;
end
endtask

endmodule

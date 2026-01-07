`timescale 1ns/1ps
`define CYCLE_TIME 12

module PATTERN(
    output reg        clk,
    output reg        rst_n,
    output reg        in_valid,
    output reg [4:0]  in_weight,   // ★ 改成 5-bit
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
        $display("FILE OPEN ERROR");
        $finish;
    end

    reset_task;

    pat_cnt = 0;
    while (!$feof(fin)) begin
        read_input_task;
        read_golden_task;

        send_pattern_task;     // ★ 改成單一 task
        wait_out_valid_task;
        check_output_task;

        $display("PASS pattern %0d, latency=%0d",
                  pat_cnt, latency);
        pat_cnt = pat_cnt + 1;
    end

    $display("====================================");
    $display("   ALL PATTERNS PASS");
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
// TASK: read golden (Vivado OK)
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
// TASK: send pattern (★ DUT-aligned)
//======================================
task send_pattern_task;
    integer i;
begin
    repeat(2) @(negedge clk);

    @(negedge clk);
    in_valid = 1'b1;
    out_mode = mode_buf[0];    // ★ mode 第一拍就給

    for (i = 0; i < 8; i = i + 1) begin
        in_weight = w[i][4:0];
        @(negedge clk);
    end

    in_valid  = 1'b0;
    in_weight = 'bx;

    // ★ out_mode 持續保持，不能變 X
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
            $display("LATENCY FAIL");
            $finish;
        end
        @(negedge clk);
    end
end
endtask

//======================================
// TASK: check output
//======================================
task check_output_task;
begin
    out_cnt = 0;
    while (out_valid === 1'b1) begin
        if (out_code !== golden[out_cnt]) begin
            $display("MISMATCH at bit %0d", out_cnt);
            $finish;
        end
        out_cnt = out_cnt + 1;
        @(negedge clk);
    end

    if (out_cnt !== golden_len) begin
        $display("LENGTH ERROR exp=%0d got=%0d",
                  golden_len, out_cnt);
        $finish;
    end

    // ★ output 完成後才釋放 mode
    @(negedge clk);
    out_mode = 1'b0;
end
endtask

endmodule

`define RTL
`ifdef RTL
    `define CYCLE_TIME 40.0
`endif
`ifdef GATE
    `define CYCLE_TIME 40.0
`endif    


//`include "../00_TESTBED/pseudo_DRAM.v"
//`include "../00_TESTBED/pseudo_SD.v"

module PATTERN(
    output reg clk,
    output reg rst_n,
    output reg in_valid,
    output reg direction,
    output reg [12:0] addr_dram,
    output reg [15:0] addr_sd,

    input out_valid,
    input [7:0] out_data
);

    // ------------------------------
    // 參數 & 宣告
    // ------------------------------
    localparam DRAM_TO_SD = 0;
    localparam SD_TO_DRAM = 1;

    real CYCLE = `CYCLE_TIME;
    integer i, pat_read;
    integer PAT_NUM;
    integer temp, i_pat, cycles;

    // DRAM / SD 記憶體
    reg [63:0] DRAM [0:8191];    // 8192 entries
    reg [63:0] SD   [0:65535];   // 65536 entries

    reg [63:0] golden;
    integer cnt;

    // ------------------------------
    // Clock
    // ------------------------------
    always #(CYCLE/2.0) clk = ~clk;

    // ------------------------------
    // Initial
    // ------------------------------
    initial begin
        clk       = 0;
        rst_n     = 1;
        in_valid  = 0;
        direction = 0;
        addr_dram = 0;
        addr_sd   = 0;

        reset_task;

        if (out_valid !== 0 || out_data !== 0) begin
            $display("SPEC MAIN-1 FAIL: Output not reset after reset");
            $finish;
        end

        // 載入記憶體初始值
        $readmemh("DRAM_init.dat", DRAM);
        $readmemh("SD_init.dat", SD);

        // 打開 Input 檔
        pat_read = $fopen("Input3.txt", "r");
        if (pat_read == 0) begin
            $display("ERROR: Cannot open Input3.txt");
            $finish;
        end

        temp = $fscanf(pat_read, "%d\n", PAT_NUM);

        for (i_pat = 0; i_pat < PAT_NUM; i_pat = i_pat + 1) begin
            input_task;
            wait_out_valid_task;
            check_ans_task;
            $display("PASS PATTERN %0d", i_pat);
        end

        $display("========================================");
        $display("Congratulations! All patterns passed.");
        $display("========================================");

        // dump 最後記憶體內容
        $writememh("DRAM_final.dat", DRAM);
        $writememh("SD_final.dat", SD);

        $finish;
    end

    // ------------------------------
    // Reset
    // ------------------------------
    task reset_task;
    begin
        force clk = 0;
        rst_n = 0;
        #(2.0*CYCLE);
        rst_n = 1;
        release clk;
    end
    endtask

    // ------------------------------
    // Input
    // ------------------------------
    task input_task;
    begin
        @(negedge clk);
        in_valid = 1;
        temp = $fscanf(pat_read, "%d\n", direction);
        temp = $fscanf(pat_read, "%d\n", addr_dram);
        temp = $fscanf(pat_read, "%d\n", addr_sd);

        // 計算 golden
        if (direction == DRAM_TO_SD) begin
            golden = DRAM[addr_dram];
        end else begin
            golden = SD[addr_sd];
        end

        $display("Pattern input: dir=%0d, DRAM=%0d, SD=%0d, Golden=%h",
                 direction, addr_dram, addr_sd, golden);

        @(negedge clk);
        in_valid = 0; // 僅 1 cycle
    end
    endtask

    // ------------------------------
    // Wait for out_valid
    // ------------------------------
    task wait_out_valid_task;
    begin
        cycles = 0;
        while(out_valid !== 1) begin
            cycles = cycles + 1;
            if (cycles > 10000) begin
                $display("SPEC FAIL: Timeout waiting out_valid");
                $finish;
            end
            @(negedge clk);
        end
    end
    endtask

    // ------------------------------
    // Check Answer
    // ------------------------------
    task check_ans_task;
    begin
        cnt = 0;
        while(out_valid === 1) begin
            if (out_data !== golden[(63-cnt*8)-:8]) begin
                $display("SPEC FAIL: Pattern %0d, Byte %0d, Expected=%h, Got=%h",
                         i_pat, cnt, golden[(63-cnt*8)-:8], out_data);
                $finish;
            end

            cnt = cnt + 1;
            if (cnt > 8) begin
                $display("SPEC FAIL: out_valid too long (>8 cycles)");
                $finish;
            end
            @(negedge clk);
        end

        if (cnt !== 8) begin
            $display("SPEC FAIL: out_valid not 8 cycles");
            $finish;
        end
    end
    endtask

endmodule

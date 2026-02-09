`timescale 1ns/1ps
`define PAT_NUM 10
`define SEED_FILE "../00_TESTBED/seeds.txt"

module PATTERN (

    output reg        rst_n,
    output reg        clk1,
    output reg        clk2,
    output reg        clk3,
    output reg        in_valid,
    output reg [31:0] seed,


    input             out_valid,
    input      [31:0] rand_num
);

    // ===============================================================
    // Parameter & Clock Definition
    // ===============================================================
   
    real CLK1_PERIOD = 14.1;
    real CLK2_PERIOD = 3.9;
    real CLK3_PERIOD = 20.7; // RTL default

    initial clk1 = 0; always #(CLK1_PERIOD/2.0) clk1 = ~clk1;
    initial clk2 = 0; always #(CLK2_PERIOD/2.0) clk2 = ~clk2;
    initial clk3 = 0; always #(CLK3_PERIOD/2.0) clk3 = ~clk3;

    // ===============================================================
    // Variables
    // ===============================================================
    integer file_in;
    integer pat_idx;
    integer scan_val;
    
    // Latency related
    integer latency;
    integer total_latency;
    reg     count_latency_en;

    // Counters & Flags
    integer out_cnt;
    reg [31:0] golden_seed;
    reg [31:0] golden_q [0:255];
    
    reg wait_output_done;

    // ===============================================================
    // Main Process
    // ===============================================================
    initial begin
        // 1. 產生種子檔 (若不存在)
        task_gen_seed_file();
        
        // 2. 開檔與重置
        task_open_file();
        task_reset_sequence();
        total_latency = 0;

        // 3. Pattern 迴圈
        for (pat_idx = 0; pat_idx < `PAT_NUM; pat_idx = pat_idx + 1) begin
            
            // 讀取種子
            scan_val = $fscanf(file_in, "%d", golden_seed);
            if (scan_val == -1) begin
                $display("\033[1;33m[INFO] End of seed file reached earlier than expected.\033[0m");
                $finish;
            end

            // 計算 Golden Answer [cite: 44-59]
            task_calc_golden(golden_seed);
            
            // 輸入資料
            task_drive_input(golden_seed);

            // 等待輸出完成 (包含 Watchdog 防止卡死)
            fork 
                begin
                    wait(wait_output_done);
                end
                begin
                    // Watchdog: 如果跑太久(例如10萬單位時間)強制結束
                    #2000000; 
                    $display("\033[1;31m[FAIL] Simulation Timeout! Pattern %0d hangs.\033[0m", pat_idx);
                    $finish;
                end
            join_any
            disable fork;

            // 顯示當前 Pattern 結果
            $display("\033[1;32m[PASS] Pattern %2d | Seed %10d | Latency %4d (clk3 cycles)\033[0m", 
                     pat_idx, golden_seed, latency);
            
            total_latency = total_latency + latency;

            // Spec[cite: 199]: Next pattern comes 1~3 clk1 cycles after output
            task_inter_pattern_delay();
        end

        // 4. 全部通過
        task_pass_message();
        $finish;
    end

    // ===============================================================
    // Tasks
    // ===============================================================

    // 自動產生種子檔，避免找不到檔案報錯
    task task_gen_seed_file; begin
        integer f_seed, i;
        // 嘗試以讀取模式打開，如果失敗代表檔案不存在
        f_seed = $fopen(`SEED_FILE, "r");
        if (f_seed == 0) begin
            $display("[INFO] seeds.txt not found. Generating new one...");
            f_seed = $fopen(`SEED_FILE, "w");
            for (i=0; i<`PAT_NUM; i=i+1) begin
                // 產生非零正整數種子
                $fwrite(f_seed, "%d\n", {$random} % 2147483647 + 1);
            end
            $fclose(f_seed);
        end else begin
            $fclose(f_seed);
        end
    end endtask

    task task_open_file; begin
        file_in = $fopen(`SEED_FILE, "r");
        if (file_in == 0) begin
            $display("\033[1;31m[FATAL] Cannot open seeds.txt even after generation.\033[0m");
            $finish;
        end
    end endtask

    // Reset 任務：只在最開始執行一次 [cite: 164]
    task task_reset_sequence; begin
        rst_n = 1;
        in_valid = 0;
        seed = 32'dx;
        
        // 確保初始狀態
        force clk1 = 0; force clk2 = 0; force clk3 = 0;
        #10 rst_n = 0;
        #20 rst_n = 1;
        
        // 檢查 Reset 後輸出是否為低 [cite: 165]
        if (out_valid !== 0 || rand_num !== 0) begin
            $display("\033[1;31m[FAIL] Output signals must be 0 after reset.\033[0m");
            $finish;
        end

        release clk1; release clk2; release clk3;
        repeat(5) @(negedge clk1);
    end endtask

    task task_drive_input(input [31:0] cur_seed); begin
        // 初始化旗標
        latency = 0;
        out_cnt = 0;
        wait_output_done = 0;
        
        // 為了安全，等待 clk1 下降緣給值
        @(negedge clk1);
        in_valid = 1;
        seed = cur_seed;

        @(negedge clk1);
        in_valid = 0;
        seed = 32'dx; // Don't care

        // Spec[cite: 195]: Latency start from falling edge of in_valid
        count_latency_en = 1; 
    end endtask

    // Xorshift 黃金模型 [cite: 44-59]
    task task_calc_golden(input [31:0] ini_seed);
        integer i;
        reg [31:0] x, x_next;
        begin
            x = ini_seed;
            for (i = 0; i < 256; i = i + 1) begin
                // 1. Left shift 13
                x_next = x ^ (x << 13);
                // 2. Right shift 17
                x_next = x_next ^ (x_next >> 17);
                // 3. Left shift 5
                x_next = x_next ^ (x_next << 5);
                
                golden_q[i] = x_next;
                x = x_next;
            end
        end
    endtask

    task task_inter_pattern_delay; begin
        // Spec[cite: 199]: 1~3 clk1 cycles delay
        repeat($urandom_range(1,3)) @(negedge clk1);
    end endtask

    task task_pass_message; begin
        if (file_in) $fclose(file_in);
        $display("\n-----------------------------------------------------------------");
        $display("              \033[1;32mCONGRATULATIONS! ALL PASS\033[0m");
        $display("        Total Latency : %d", total_latency);
        $display("-----------------------------------------------------------------\n");
    end endtask

    // ===============================================================
    // Always Blocks (Checkers & Counters)
    // ===============================================================

    // Latency Counter (CLK3 Domain)
    // 注意：in_valid 在 clk1 域，但在這邊模擬用 flag 傳遞通常沒問題
    always @(negedge clk3) begin
        if (count_latency_en) begin
            latency = latency + 1;
            // Spec[cite: 197]: Latency must be < 2000 cycles
            if (latency > 2000) begin
                $display("\033[1;31m[FAIL] Latency limit exceeded (>2000 cycles).\033[0m");
                $finish;
            end
        end
    end

    // Output Verification (CLK3 Domain)
    always @(negedge clk3) begin
        if (rst_n && count_latency_en) begin
            if (out_valid) begin
                // 檢查資料正確性
                if (out_cnt >= 256) begin
                    $display("\033[1;31m[FAIL] Output exceeded 256 numbers.\033[0m");
                    $finish;
                end
                
                if (rand_num !== golden_q[out_cnt]) begin
                    $display("\n\033[1;31m[FAIL] Value Mismatch @ Index %0d\033[0m", out_cnt);
                    $display("Expected: %8h | Got: %8h", golden_q[out_cnt], rand_num);
                    $finish;
                end
                
                out_cnt = out_cnt + 1;

                // 如果是最後一筆資料 (第 256 筆)
                if (out_cnt == 256) begin
                    count_latency_en = 0; // 停止計算 Latency [cite: 195]
                    wait_output_done = 1; // 通知主迴圈可以結束等待
                end
            end 
            else begin
                // Spec: rand_num should be reset when out_valid is low
                // 這裡要很小心，如果是剛開始還沒輸出，rand_num 應該也是 0
                if (rand_num !== 0) begin
                    $display("\033[1;31m[FAIL] rand_num must be 0 when out_valid is low.\033[0m");
                    $finish;
                end
            end
        end
    end

endmodule
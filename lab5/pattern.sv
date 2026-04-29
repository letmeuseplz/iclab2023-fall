`timescale 1ns/1ps
`define CYCLE_TIME 10.0 // 可依需求調整，最大不得超過 20ns

module PATTERN (
    output reg        clk,
    output reg        rst_n,
    output reg        in_valid,
    output reg        in_valid2,
    output reg [7:0]  image,
    output reg [7:0]  template,
    output reg [1:0]  image_size,
    output reg [2:0]  action,
    input  wire       out_valid,
    input  wire[19:0] out_value
);

// ---------------------------------------------------------
// 參數與變數宣告
// ---------------------------------------------------------
parameter PATNUM = 1; 
integer pat_idx, set_idx;
integer i, delay_cycles, latency;
integer max_latency = 5000;

integer img_dim, num_pixels, num_actions;
integer out_cnt, exp_out_cnt;

// 獨立的檔案 I/O
integer img_fd, tpl_fd, act_fd, ans_fd, status;
integer read_img, read_tpl, read_act, golden_ans;

// ---------------------------------------------------------
// 時鐘產生
// ---------------------------------------------------------
always #(`CYCLE_TIME/2.0) clk = ~clk;

// ---------------------------------------------------------
// 主測試流程
// ---------------------------------------------------------
initial begin
    // 開啟四個獨立的測資檔案
    img_fd = $fopen("../00_TESTBED/img.dat", "r");
    tpl_fd = $fopen("../00_TESTBED/template.dat", "r");
    act_fd = $fopen("../00_TESTBED/action.dat", "r");
    ans_fd = $fopen("../00_TESTBED/golden.dat", "r");
    
    if (img_fd == 0 || tpl_fd == 0 || act_fd == 0 || ans_fd == 0) begin
        $display("\033[0;31m[ERROR] Cannot open dat files. Please run Python script first!\033[m");
        $finish;
    end

    // 初始狀態設定
    clk = 0;
    rst_n = 1;
    in_valid = 0;
    in_valid2 = 0;
    image = 8'bx;
    template = 8'bx;
    image_size = 2'bx;
    action = 3'bx;
    
    force clk = 0;
    reset_task;
    
    for (pat_idx = 0; pat_idx < PATNUM; pat_idx = pat_idx + 1) begin
        input_image_task;
        
        for (set_idx = 0; set_idx < 8; set_idx = set_idx + 1) begin
            wait_delay_task;
            input_action_task;
            wait_out_valid_task;
        end
        $display("\033[0;32m  -> Pass Pattern No.%4d\033[m\n", pat_idx);
    end
    
    $fclose(img_fd);
    $fclose(tpl_fd);
    $fclose(act_fd);
    $fclose(ans_fd);
    
    $display("\033[1;33m========================================\033[m");
    $display("\033[1;33m    Congratulations! All PATTERNs PASS  \033[m");
    $display("\033[1;33m========================================\033[m");
    $finish;
end

// ---------------------------------------------------------
// 任務：重置 (Reset)
// ---------------------------------------------------------
task reset_task; begin
    #(10);
    rst_n = 0;
    #(10);
    if (out_valid !== 0 || out_value !== 0) begin
        $display("\033[0;31m[ERROR] Output should be 0 after reset!\033[m");
        $finish;
    end
    #(10);
    rst_n = 1;
    release clk;
end endtask

// ---------------------------------------------------------
// 任務：讀取並輸入影像與樣板 (Image & Template)
// ---------------------------------------------------------
task input_image_task; begin
    @(negedge clk);
    in_valid = 1'b1;
    
    // 從 img.dat 讀取 image_size
    status = $fscanf(img_fd, "%d", image_size);
    if (image_size == 0)      begin img_dim = 4;  num_pixels = 16;  end
    else if (image_size == 1) begin img_dim = 8;  num_pixels = 64;  end
    else                      begin img_dim = 16; num_pixels = 256; end
    
    $display("\033[0;36m[INFO] Pattern %0d Started! Image Size = %0d (%0dx%0d)\033[m", pat_idx, image_size, img_dim, img_dim);
    
    for (i = 0; i < (num_pixels * 3); i = i + 1) begin
        // 讀取 Image
        status = $fscanf(img_fd, "%d", read_img);
        image = read_img[7:0];
        
        // 讀取 Template (只有前 9 拍要給)
        if (i < 9) begin
            status = $fscanf(tpl_fd, "%d", read_tpl);
            template = read_tpl[7:0];
        end else begin
            template = 8'bx;
        end
        
        if (i != 0) image_size = 2'bx; 
        
        @(negedge clk);
    end
    
    in_valid = 1'b0;
    image = 8'bx;
    template = 8'bx;
    image_size = 2'bx;
end endtask

// ---------------------------------------------------------
// 任務：讀取並輸入動作指令 (Action)
// ---------------------------------------------------------
task input_action_task; begin
    @(negedge clk);
    in_valid2 = 1'b1;
    
    // 從 act_fd 讀取 Action 數量
    status = $fscanf(act_fd, "%d", num_actions);
    $display("  -> [INFO] Set %0d: Reading %0d actions...", set_idx, num_actions);
    
    for (i = 0; i < num_actions; i = i + 1) begin
        status = $fscanf(act_fd, "%d", read_act);
        action = read_act[2:0];
        @(negedge clk);
    end
    
    in_valid2 = 1'b0;
    action = 3'bx;
end endtask

// ---------------------------------------------------------
// 任務：隨機等待延遲
// ---------------------------------------------------------
task wait_delay_task; begin
    delay_cycles = $urandom_range(2, 4);
    for (i = 0; i < delay_cycles; i = i + 1) begin
        @(negedge clk);
    end
end endtask

// ---------------------------------------------------------
// 任務：等待並嚴格比對輸出 (Check Output)
// ---------------------------------------------------------
task wait_out_valid_task; begin
    latency = 0;
    out_cnt = 0;
    
    // 從 ans_fd 讀取這回合的輸出數量
    status = $fscanf(ans_fd, "%d", exp_out_cnt);
    
    while (out_valid === 1'b0) begin
        latency = latency + 1;
        if (latency > max_latency) begin
            $display("\033[0;31m[ERROR] Execution Latency exceeds %d cycles at Pattern %d, Set %d!\033[m", max_latency, pat_idx, set_idx);
            $finish;
        end
        @(negedge clk);
    end
    
    while (out_valid === 1'b1) begin
        if (in_valid === 1'b1 || in_valid2 === 1'b1) begin
            $display("\033[0;31m[ERROR] out_valid cannot overlap with inputs!\033[m");
            $finish;
        end
        
        status = $fscanf(ans_fd, "%d", golden_ans);
        
        if (out_value !== golden_ans) begin
            $display("\033[0;31m==================================================\033[m");
            $display("\033[0;31m [ERROR] Pattern %d, Set %d, Output Index %d\033[m", pat_idx, set_idx, out_cnt);
            $display("\033[0;31m         Expected : %20d\033[m", golden_ans);
            $display("\033[0;31m         Your Ans : %20d\033[m", out_value);
            $display("\033[0;31m==================================================\033[m");
            $finish;
        end
        
        out_cnt = out_cnt + 1;
        @(negedge clk);
    end
    
    if (out_cnt !== exp_out_cnt) begin
        $display("\033[0;31m[ERROR] Output Count mismatch at Pattern %d, Set %d! Expected %d, Got %d\033[m", pat_idx, set_idx, exp_out_cnt, out_cnt);
        $finish;
    end
end endtask

// ---------------------------------------------------------
// 規格檢查
// ---------------------------------------------------------
always @(negedge clk) begin
    if (out_valid === 1'b0 && out_value !== 20'd0 && rst_n === 1'b1) begin
        $display("\033[0;31m[ERROR] out_value must be 0 when out_valid is 0\033[m");
        $finish;
    end
end

endmodule
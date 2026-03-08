`define PAT_NUM 1

`define OPT_FILE  "./opt.dat"
`define IMG_FILE  "./img.dat"
`define KER_FILE  "./kernel.dat"
`define WGT_FILE  "./weight.dat"
`define OUT_FILE  "./golden.dat"

module PATTERN (
    // Output to DUT
    output reg        clk,
    output reg        rst_n,
    output reg        cg_en,
    output reg        in_valid,
    output reg [31:0] Img,
    output reg [31:0] Kernel,
    output reg [31:0] Weight,
    output reg [1:0]  Opt,

    // Input from DUT
    input             out_valid,
    input      [31:0] out_data
);

    // ===============================================================
    // Parameter & Clock Definition
    // ===============================================================
    real CLK_PERIOD = 20.5; 
    always #(CLK_PERIOD/2.0) clk = ~clk;

    localparam IMG_LEN = 96;  
    localparam KER_LEN = 27;
    localparam WGT_LEN = 4;
    localparam MAX_IN_LEN = 96; // 依照 Lab04 規格，in_valid 總共 high 96 拍

    // ===============================================================
    // Variables
    // ===============================================================
    integer f_opt, f_img, f_ker, f_wgt, f_out;
    integer pat_idx;
    integer scan_val;
    integer i;
    
    reg [8*200:1] line_buffer; // 💡 [新增] 暫存整行字串的 buffer，用來安全過濾掉註解
    
    integer latency;
    integer total_latency;
    reg     count_latency_en;

    reg wait_output_done;
    reg out_valid_last; 
    reg reset_done;     // 💡 用來標記 Reset 是否完全結束

    // Data Buffers
    reg [31:0] pat_img    [0:IMG_LEN-1];
    reg [31:0] pat_kernel [0:KER_LEN-1];
    reg [31:0] pat_weight [0:WGT_LEN-1];
    reg [1:0]  pat_opt;
    reg [31:0] golden_ans;

    // ===============================================================
    // IEEE-754 Float to Real Conversion Function
    // ===============================================================
    function real bits2real;
        input [31:0] bits;
        real sign, exp, frac;
        begin
            if (bits[30:0] == 31'b0) begin
                bits2real = 0.0;
            end else begin
                sign = (bits[31] == 1'b1) ? -1.0 : 1.0;
                exp  = bits[30:23] - 127.0;
                frac = 1.0 + (bits[22:0] / (2.0**23));
                bits2real = sign * frac * (2.0**exp);
            end
        end
    endfunction

    function real abs_diff;
        input real a, b;
        begin
            abs_diff = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    // ===============================================================
    // Main Process
    // ===============================================================
    initial begin
        clk = 0;
        out_valid_last = 0;
        reset_done = 0; 
        $display("\033[1;34m[SYSTEM] Starting SNN Simulation...\033[0m");
        
        task_open_file();
        task_reset_sequence();
        
        total_latency = 0;

        for (pat_idx = 0; pat_idx < `PAT_NUM; pat_idx = pat_idx + 1) begin
            
            task_read_pattern();
            
            $display("\033[1;34m[PATTERN %0d] Opt: %0d | CG_EN: %0b\033[0m", pat_idx, pat_opt, cg_en);

            task_drive_input();

            // 等待輸出與 Watchdog (Timeout limit = 1000 cycles)
            fork 
                begin
                    wait(wait_output_done);
                end
                begin
                    #(1000 * CLK_PERIOD); 
                    $display("\033[1;31m[FAIL] Timeout! Latency > 1000 at Pattern %0d. Time: %0t\033[0m", pat_idx, $time);
                    $finish;
                end
            join_any
            disable fork;

            $display("\033[1;32m[PASS] Pattern %2d | Latency: %4d\033[0m", pat_idx, latency);
            
            total_latency = total_latency + latency;
            task_inter_pattern_delay();
        end

        task_pass_message();
        $finish;
    end

    // ===============================================================
    // Tasks
    // ===============================================================

    task task_open_file; begin
        f_opt = $fopen(`OPT_FILE, "r");
        f_img = $fopen(`IMG_FILE, "r");
        f_ker = $fopen(`KER_FILE, "r");
        f_wgt = $fopen(`WGT_FILE, "r");
        f_out = $fopen(`OUT_FILE, "r");
        
        if (f_opt == 0 || f_img == 0 || f_ker == 0 || f_wgt == 0 || f_out == 0) begin
            $display("\033[1;31m[FATAL] Error opening one or more pattern files!\033[0m");
            $finish;
        end
    end endtask

    task task_reset_sequence; begin
        rst_n    = 1;
        in_valid = 0;
        cg_en    = 0;
        
        Img      = 32'bx;
        Kernel   = 32'bx;
        Weight   = 32'bx;
        Opt      = 2'bx;

        force clk = 0;
        #10 rst_n = 0; 
        #20 rst_n = 1; 
        
        if (out_valid !== 0 || out_data !== 0) begin
            $display("\033[1;31m[FAIL] Signals must be 0 after reset at %0t\033[0m", $time);
            $finish;
        end
        release clk;
        repeat(5) @(negedge clk);
        
        reset_done = 1; 
        
        $display("\033[1;32m[DEBUG] Reset Completed Successfully.\033[0m");
    end endtask

    task task_read_pattern; begin
        // 讀取 Option
        scan_val = $fscanf(f_opt, "%d", pat_opt);
        if (scan_val == -1) begin
            $display("\033[1;33m[INFO] End of file reached.\033[0m");
            task_pass_message();
            $finish;
        end
        
        // 💡 [修改] 讀取 Image：先抓整行，再從開頭挑出 16 進位數值，完美忽略後面的註解
        for (i=0; i<IMG_LEN; i=i+1) begin
            scan_val = $fgets(line_buffer, f_img);
            scan_val = $sscanf(line_buffer, "%h", pat_img[i]);
        end
        
        // 💡 [修改] 讀取 Kernel
        for (i=0; i<KER_LEN; i=i+1) begin
            scan_val = $fgets(line_buffer, f_ker);
            scan_val = $sscanf(line_buffer, "%h", pat_kernel[i]);
        end
        
        // 💡 [修改] 讀取 Weight
        for (i=0; i<WGT_LEN; i=i+1) begin
            scan_val = $fgets(line_buffer, f_wgt);
            scan_val = $sscanf(line_buffer, "%h", pat_weight[i]);
        end
        
        // 💡 [修改] 讀取 Golden Answer (以防裡面也有註解)
        scan_val = $fgets(line_buffer, f_out);
        scan_val = $sscanf(line_buffer, "%h", golden_ans);
    end endtask

    task task_drive_input; begin
        latency = 0;
        wait_output_done = 0;
        
        cg_en = $random % 2; 

        @(negedge clk);
        in_valid = 1;
        
        for (i = 0; i < MAX_IN_LEN; i = i + 1) begin
            if (out_valid === 1'b1) begin
                $display("\033[1;31m[FAIL] in_valid and out_valid cannot overlap!\033[0m");
                $finish;
            end
            
            Opt    = (i == 0) ? pat_opt : 2'bx;
            Img    = pat_img[i];
            Kernel = (i < KER_LEN) ? pat_kernel[i] : 32'bx;
            Weight = (i < WGT_LEN) ? pat_weight[i] : 32'bx;
            
            @(negedge clk);
        end

        in_valid = 0;
        Img      = 32'bx;
        Kernel   = 32'bx;
        Weight   = 32'bx;
        Opt      = 2'bx;
        
        count_latency_en = 1; 
    end endtask

    task task_inter_pattern_delay; begin
        repeat($urandom_range(2, 5)) @(negedge clk);
    end endtask

    task task_pass_message; begin
        $display("\n-----------------------------------------------------------------");
        $display("              \033[1;32mCONGRATULATIONS! ALL PASS\033[0m");
        $display("        Total Latency : %d", total_latency);
        $display("-----------------------------------------------------------------\n");
    end endtask

    // ===============================================================
    // Verification Monitors
    // ===============================================================

    always @(negedge clk) begin
        if (count_latency_en) begin
            latency = latency + 1;
        end
    end

    real real_golden, real_out, err;
    
    always @(negedge clk) begin
        if (rst_n && reset_done) begin
            
            if (out_valid && out_valid_last) begin
                $display("\033[1;31m[FAIL] out_valid must be high for ONLY 1 cycle! at %0t\033[0m", $time);
                $finish;
            end
            out_valid_last = out_valid;

            if (out_valid) begin
                
                real_golden = bits2real(golden_ans);
                real_out    = bits2real(out_data);
                err         = abs_diff(real_golden, real_out);

                if (err >= 0.01) begin // 依照 Lab08 容忍度 0.01
                    $display("\n\033[1;31m[FAIL] Floating Point Error >= 0.01 @ Pattern %0d\033[0m", pat_idx);
                    $display("Expected: %h (%f)", golden_ans, real_golden);
                    $display("Got     : %h (%f)", out_data, real_out);
                    $display("Error   : %f", err);
                    $finish;
                end
                
                count_latency_en = 0; 
                wait_output_done = 1; 
                
            end 
            else begin
                if (out_data !== 0) begin
                    $display("\033[1;31m[FAIL] out_data is NOT 0 when out_valid is LOW at %0t\033[0m", $time);
                    $display("Current value: %h", out_data);
                    $finish;
                end
            end
        end
    end

endmodule
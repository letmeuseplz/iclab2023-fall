`include "Usertype_BEV.sv"

program automatic PATTERN(input clk, INF.PATTERN inf);
    
    integer total_latency;

    initial begin
        $display("==========================================================");
        $display("  🚀 Starting Custom Plaintext PATTERN...");
        $display("==========================================================");
        
        // 1. 初始化與 Reset
        total_latency = 0;
        reset_task();
        
        // --------------------------------------------------------
        // 測試案例 1：補貨 (Supply)
        // 對 Box 0 補貨，今天補貨日期: 12/31
        // 補貨量: 紅茶 100, 綠茶 200, 牛奶 300, 鳳梨 400
        // --------------------------------------------------------
        $display(">>> TEST 1: Supply (Box 0, Date 12/31, BT:100, GT:200, M:300, P:400)");
        test_supply(8'd0, 4'd12, 5'd31, 12'd100, 12'd200, 12'd300, 12'd400); 
        
        // --------------------------------------------------------
        // 測試案例 2：製作飲料 (Make Drink)
        // 點一杯 特調奶茶(Type 2), L杯(Size 0), 今天日期: 10/15, 使用 Box 0
        // --------------------------------------------------------
        $display(">>> TEST 2: Make Drink (Extra Milk Tea, Size L, Today 10/15, Box 0)");
        test_make_drink(3'd2, 2'd0, 4'd10, 5'd15, 8'd0); 
        
        // --------------------------------------------------------
        // 測試案例 3：檢查日期 (Check Valid Date)
        // 檢查 Box 0 的過期狀態，今天日期: 12/15
        // --------------------------------------------------------
        $display(">>> TEST 3: Check Date (Today 12/15, Box 0)");
        test_check_date(4'd12, 5'd15, 8'd0); 

        $display("==========================================================");
        $display("  🎉 All Custom Patterns Finished!");
        $display("  打開 Verdi 看看你的 C_addr, C_data_w 到底寫了什麼吧！");
        $display("==========================================================");
        $finish;
    end

    // ====================================================================
    // Tasks 實作區 (模擬 Pattern 發送訊號)
    // ====================================================================
    task reset_task();
        inf.rst_n = 1'b1;
        inf.sel_action_valid = 0;
        inf.type_valid = 0;
        inf.size_valid = 0;
        inf.date_valid = 0;
        inf.box_no_valid = 0;
        inf.box_sup_valid = 0;
        inf.D = 'bx;
        #(10);
        inf.rst_n = 1'b0; // 觸發 Reset
        #(20);
        inf.rst_n = 1'b1; // 結束 Reset
        #(20);
    endtask

    // ---------------------------------------------------------
    // 模擬 Make Drink 輸入
    // ---------------------------------------------------------
    task test_make_drink(logic [2:0] b_type, logic [1:0] b_size, logic [3:0] M, logic [4:0] D, logic [7:0] box);
        @(negedge clk);
        inf.sel_action_valid = 1; inf.D = {10'd0, 2'b00}; // Action 0: Make Drink
        @(negedge clk);
        inf.sel_action_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk); // 模擬 Spec 規定的 1~4 cycles 隨機延遲
        
        inf.type_valid = 1; inf.D = {9'd0, b_type};
        @(negedge clk);
        inf.type_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.size_valid = 1; inf.D = {10'd0, b_size};
        @(negedge clk);
        inf.size_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.date_valid = 1; inf.D = {3'd0, M, D};
        @(negedge clk);
        inf.date_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.box_no_valid = 1; inf.D = {4'd0, box};
        @(negedge clk);
        inf.box_no_valid = 0; inf.D = 'bx;

        wait_out_valid(); // 等待電路運算並接收輸出
    endtask

    // ---------------------------------------------------------
    // 模擬 Supply 輸入
    // ---------------------------------------------------------
    task test_supply(logic [7:0] box, logic [3:0] M, logic [4:0] d, logic [11:0] bt, logic [11:0] gt, logic [11:0] m, logic [11:0] p);
        @(negedge clk);
        inf.sel_action_valid = 1; inf.D = {10'd0, 2'b01}; // Action 1: Supply
        @(negedge clk);
        inf.sel_action_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.date_valid = 1; inf.D = {3'd0, M, d};
        @(negedge clk);
        inf.date_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.box_no_valid = 1; inf.D = {4'd0, box};
        @(negedge clk);
        inf.box_no_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk);
        
        // 連續 4 次 Supply Material
        inf.box_sup_valid = 1; inf.D = bt; @(negedge clk);
        inf.box_sup_valid = 0; inf.D = 'bx; repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.box_sup_valid = 1; inf.D = gt; @(negedge clk);
        inf.box_sup_valid = 0; inf.D = 'bx; repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.box_sup_valid = 1; inf.D = m; @(negedge clk);
        inf.box_sup_valid = 0; inf.D = 'bx; repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.box_sup_valid = 1; inf.D = p; @(negedge clk);
        inf.box_sup_valid = 0; inf.D = 'bx;

        wait_out_valid();
    endtask

    // ---------------------------------------------------------
    // 模擬 Check Date 輸入
    // ---------------------------------------------------------
    task test_check_date(logic [3:0] M, logic [4:0] D, logic [7:0] box);
        @(negedge clk);
        inf.sel_action_valid = 1; inf.D = {10'd0, 2'b10}; // Action 2: Check Date
        @(negedge clk);
        inf.sel_action_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.date_valid = 1; inf.D = {3'd0, M, D};
        @(negedge clk);
        inf.date_valid = 0; inf.D = 'bx;
        repeat($urandom_range(1,3)) @(negedge clk);
        
        inf.box_no_valid = 1; inf.D = {4'd0, box};
        @(negedge clk);
        inf.box_no_valid = 0; inf.D = 'bx;

        wait_out_valid();
    endtask

    // ---------------------------------------------------------
    // 接收並印出 BEV 的運算結果
    // ---------------------------------------------------------
    task wait_out_valid();
        integer latency = 0;
        while (inf.out_valid !== 1'b1) begin
            latency++;
            if (latency > 1000) begin
                $display("    [ERROR ❌] Latency > 1000 cycles! FSM 或是 AXI 死結卡住了！");
                $finish;
            end
            @(negedge clk);
        end
        // 當 out_valid 變高時，擷取當下的輸出
        $display("    => [RESULT] complete: %b, err_msg: %b (花費時間: %0d cycles)", inf.complete, inf.err_msg, latency);
        @(negedge clk);
    endtask

endprogram
`include "Usertype_BEV.sv"

module Checker(input clk, INF.CHECKER inf);
    import usertype::*;

    // ============================================================================
    // 1. 內部暫存器 (幫助 Coverage 收集資料)
    // ============================================================================
    // 因為 type 和 size 在不同時間點送進來，如果要算 Cross Coverage (交叉覆蓋率)，
    // 我們需要在 Checker 裡面把沿路看到的訊號先記下來，等最後一起結算。
    Action act_reg;
    Bev_Type type_reg;
    Bev_Size size_reg;

    always_ff @(posedge clk or negedge inf.rst_n) begin
        if (!inf.rst_n) begin
            act_reg  <= Make_drink; // 給個初始值
            type_reg <= Black_Tea;
            size_reg <= L;
        end else begin
            if (inf.sel_action_valid) act_reg  <= inf.D.d_act[0];
            if (inf.type_valid)       type_reg <= inf.D.d_type[0];
            if (inf.size_valid)       size_reg <= inf.D.d_size[0];
        end
    end

    // ============================================================================
    // 2. Coverage (功能覆蓋率) 區塊
    // ============================================================================
    // 這裡實作文件要求你必須「踩好踩滿」的條件 (例如每種飲料 100 次等)

    // Spec 1 & 2 & 3: 飲料種類、大小、以及兩者的交叉組合 (Cross)
    // 我們選在 size_valid 拉高時來採樣，因為這時候 type_reg 已經記住了，size 也剛好進來
    covergroup CG_Drink_Spec @(posedge clk iff inf.size_valid);
        cp_type: coverpoint type_reg {
            option.at_least = 100; // 每種飲料至少 100 次
        }
        cp_size: coverpoint inf.D.d_size[0] {
            option.at_least = 100; // 每種大小至少 100 次
        }
        // Cross Coverage: 飲料種類 x 飲料大小 (8 * 3 = 24 種組合)
        cp_cross_type_size: cross cp_type, cp_size {
            option.at_least = 100; // 每種組合至少 100 次
        }
    endgroup

    // Spec 4: 每種 Action 至少發生 100 次
    covergroup CG_Action_Spec @(posedge clk iff inf.sel_action_valid);
        cp_act: coverpoint inf.D.d_act[0] {
            option.at_least = 100;
        }
    endgroup

    // Spec 5: 確保每種 Error Message 都有被觸發到
    covergroup CG_Error_Spec @(posedge clk iff inf.out_valid);
        cp_err: coverpoint inf.err_msg {
            option.at_least = 20; // 假設文件規定每種 Error 至少 20 次
        }
    endgroup

    // 宣告並實體化 Covergroup
    CG_Drink_Spec   cov_drink;
    CG_Action_Spec  cov_act;
    CG_Error_Spec   cov_err;

    initial begin
        cov_drink = new();
        cov_act   = new();
        cov_err   = new();
    end

    // ============================================================================
    // 3. SystemVerilog Assertions (SVA) 區塊
    // ============================================================================
    // 這裡負責抓硬體的錯！注意：字串 "Assertion X is violated" 必須跟文件一字不差！

    // ----------------------------------------------------------------------------
    // Assertion 1: Reset 發生時，所有的輸出必須為 0
    // ----------------------------------------------------------------------------
    always_comb begin
        if (inf.rst_n === 1'b0) begin
            assert_1: assert (inf.out_valid === 1'b0 && inf.err_msg === 2'b00 && inf.complete === 1'b0)
            else $fatal(0, "Assertion 1 is violated");
        end
    end

    // ----------------------------------------------------------------------------
    // Assertion 2: 當 out_valid 掉下來變成 0 時，err_msg 和 complete 也必須是 0
    // (這條依據各年 Spec 可能編號不同，請確認文件)
    // ----------------------------------------------------------------------------
    property check_out_zero;
        @(posedge clk) (inf.out_valid === 1'b0) |-> (inf.err_msg === 2'b00 && inf.complete === 1'b0);
    endproperty
    assert_2: assert property(check_out_zero) else $fatal(0, "Assertion 2 is violated");

    // ----------------------------------------------------------------------------
    // Assertion 3: out_valid 拉高後，下一個 cycle 必須馬上降回 0 (只能維持 1 cycle)
    // ----------------------------------------------------------------------------
    property check_out_valid_one_cycle;
        @(posedge clk) (inf.out_valid === 1'b1) |=> (inf.out_valid === 1'b0);
    endproperty
    assert_3: assert property(check_out_valid_one_cycle) else $fatal(0, "Assertion 3 is violated");

    // ----------------------------------------------------------------------------
    // Assertion 4: 所有的 valid 訊號 (input) 都不能重疊 (Overlap)
    // (這裡用 $onehot0 來檢查：所有 valid 訊號加起來最多只能有 1 個是 high)
    // ----------------------------------------------------------------------------
    logic [5:0] all_valids;
    assign all_valids = {inf.sel_action_valid, inf.type_valid, inf.size_valid, inf.date_valid, inf.box_no_valid, inf.box_sup_valid};
    
    property check_no_overlap;
        @(posedge clk) $onehot0(all_valids);
    endproperty
    assert_4: assert property(check_no_overlap) else $fatal(0, "Assertion 4 is violated");

   // 宣告一個計數器來數 Supply 吃到了第幾個
    logic [2:0] sup_cnt;
    always_ff @(posedge clk or negedge inf.rst_n) begin
        if (!inf.rst_n) sup_cnt <= 0;
        else if (inf.box_sup_valid) sup_cnt <= sup_cnt + 1;
        else if (inf.out_valid) sup_cnt <= 0; // 結算完清空
    end

    // 定義什麼叫做「真的輸入結束了」
    logic input_done;
    assign input_done = (act_reg == Make_drink && inf.box_no_valid) || 
                        (act_reg == Check_Valid_Date && inf.box_no_valid) || 
                        (act_reg == Supply && inf.box_sup_valid && sup_cnt == 3); // 第 4 次 sup_valid

    // 然後你的 Assertion 就可以寫成這樣完美無瑕的版本：
    property check_latency;
        @(posedge clk) (input_done) |=> (inf.out_valid === 1'b0)[*0:1000] ##1 (inf.out_valid === 1'b1);
    endproperty
    assert_5: assert property(check_latency) else $fatal(0, "Assertion 5 is violated");


endmodule
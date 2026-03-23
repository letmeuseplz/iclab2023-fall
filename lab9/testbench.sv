`timescale 1ns/1ps

// 引入所有需要的定義與模組
`include "beverge.sv"
`include "bridge.sv"
`include "pattern.sv"
`include "pseudo_dram.sv"
`include "Usertype_BEV.sv"
`include "INF.sv"

module TESTBED;

    // =======================================================
    // 1. 時脈產生 (Clock Generation)
    // =======================================================
    logic clk;
    
    // 設定 Clock 週期，這裡預設為 10ns (依你們 Lab 規定可調整)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // =======================================================
    // 2. 實例化官方 Interface
    // =======================================================
    INF inf();

    // =======================================================
    // 3. 實例化官方測資與 DRAM 模型
    // =======================================================
    PATTERN I_PATTERN(.clk(clk), .inf(inf));
    pseudo_DRAM I_pseudo_DRAM(.clk(clk), .inf(inf));

    // =======================================================
    // 4. 建立 BEV 與 Bridge 之間的內部溝通線路
    // =======================================================
    logic [7:0]  C_addr;
    logic        C_r_wb;
    logic        C_in_valid;
    logic [63:0] C_data_w;
    logic        C_out_valid;
    logic [63:0] C_data_r;

    // =======================================================
    // 5. 實例化你的核心大腦 (BEV.sv)
    // =======================================================
    BEV I_BEV (
        // 系統與控制訊號 (連接到 inf)
        .clk(clk),
        .rst_n(inf.rst_n),
        .sel_action_valid(inf.sel_action_valid),
        .type_valid(inf.type_valid),
        .size_valid(inf.size_valid),
        .date_valid(inf.date_valid),
        .box_no_valid(inf.box_no_valid),
        .box_sup_valid(inf.box_sup_valid),
        .D(inf.D),
        
        // 輸出結果 (連接到 inf)
        .out_valid(inf.out_valid),
        .complete(inf.complete),
        .err_msg(inf.err_msg),

        // 與 Bridge 溝通的介面 (內部線路)
        .C_addr(C_addr),
        .C_r_wb(C_r_wb),
        .C_in_valid(C_in_valid),
        .C_data_w(C_data_w),
        .C_out_valid(C_out_valid),
        .C_data_r(C_data_r)
    );

    // =======================================================
    // 6. 實例化你的 AXI 橋樑 (Bridge.sv)
    // =======================================================
    Bridge I_Bridge (
        // 系統訊號
        .clk(clk),
        .rst_n(inf.rst_n),
        
        // 與 BEV 溝通的介面 (內部線路)
        .C_in_valid(C_in_valid),
        .C_r_wb(C_r_wb),
        .C_addr(C_addr),
        .C_data_w(C_data_w),
        .C_out_valid(C_out_valid),
        .C_data_r(C_data_r),

        // AXI4-Lite 介面 (直接 Mapping 到官方 inf)
        .AR_VALID(inf.AR_VALID),
        .AR_ADDR(inf.AR_ADDR),
        .AR_READY(inf.AR_READY),
        
        .R_VALID(inf.R_VALID),
        .R_DATA(inf.R_DATA),
        .R_RESP(inf.R_RESP),
        .R_READY(inf.R_READY),
        
        .AW_VALID(inf.AW_VALID),
        .AW_ADDR(inf.AW_ADDR),
        .AW_READY(inf.AW_READY),
        
        .W_VALID(inf.W_VALID),
        .W_DATA(inf.W_DATA),
        .W_READY(inf.W_READY),
        
        .B_VALID(inf.B_VALID),
        .B_RESP(inf.B_RESP),
        .B_READY(inf.B_READY)
    );

    // =======================================================
    // 7. 產生 Verdi/nWave 觀察用的波形檔 (FSDB)
    // =======================================================
    initial begin
        $fsdbDumpfile("BEV.fsdb");
        // +mda 代表展開並記錄多維陣列 (如 Memory Array)
        $fsdbDumpvars(0, "+mda"); 
    end

endmodule
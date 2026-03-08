    `timescale 1ns/1ps


//`include "PATTERN.v"
//`ifdef RTL
//  `include "SNN.v"
//`elsif GATE
 // `include "SNN_SYN.v"
//`endif

module TESTBED;

    // ===============================================================
    // Wires Declaration (用來連接 PATTERN 與 SNN)
    // ===============================================================
    wire        clk;
    wire        rst_n;
    wire        cg_en;
    wire        in_valid;
    wire [31:0] Img;
    wire [31:0] Kernel;
    wire [31:0] Weight;
    wire [1:0]  Opt;

    wire        out_valid;
    wire [31:0] out_data;

    // ===============================================================
    // PATTERN Instantiation (考官)
    // ===============================================================
    PATTERN I_PATTERN (
        .clk(clk),
        .rst_n(rst_n),
        .cg_en(cg_en),
        .in_valid(in_valid),
        .Img(Img),
        .Kernel(Kernel),
        .Weight(Weight),
        .Opt(Opt),
        .out_valid(out_valid),
        .out_data(out_data)
    );

    // ===============================================================
    // DUT Instantiation (考生：你的硬體設計)
    // ===============================================================
    SNN I_SNN (
        .clk(clk),
        .rst_n(rst_n),
        
        // 💡 警告：請務必確認你的 SNN.v 已經加入了 input cg_en
        .cg_en(cg_en),    

        .in_valid(in_valid),
        .Img(Img),
        .Kernel(Kernel),
        .Weight(Weight),
        .Opt(Opt),
        .out_valid(out_valid),
        
        // 💡 PATTERN 的 out_data 接到你 SNN 的 out
        .out(out_data)    
    );

    // ===============================================================
    // Waveform Dump (波形輸出設定)
    // ===============================================================
    initial begin
        `ifdef RTL
            // 跑 RTL Simulation 時的波形檔
            $fsdbDumpfile("SNN.fsdb");
            $fsdbDumpvars(0, TESTBED); // 💡 明確告訴它：從 TESTBED 這一層開始，往下所有的線都抓！
            $fsdbDumpMDA(10, TESTBED); // 💡 專門用來抓二維陣列 (img_buf, feat_buf 等)
        `elsif GATE
            // 跑 Gate-level Simulation 時的波形檔與 SDF 標註
            $fsdbDumpfile("SNN_GATE.fsdb");
            $sdf_annotate("Netlist/SNN_SYN.sdf", I_SNN);
            $fsdbDumpvars(0, TESTBED);
            $fsdbDumpMDA(10, TESTBED);
        `endif
    end

endmodule
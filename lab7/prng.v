`timescale 1ns/1ps
module CLK_1_MODULE (
    input              clk1,
    input              rst_n,
    input              in_valid,
    input       [31:0] seed,

    // to handshake_sync
    output reg         hs_valid,
    output reg  [31:0] hs_data,
    input              hs_done
);

    reg busy;

    always @(posedge clk1 or negedge rst_n) begin
        if (!rst_n) begin
            hs_valid <= 1'b0;
            hs_data  <= 32'd0;
            busy     <= 1'b0;
        end else begin
            // Start handshake when valid input comes and not busy
            if (in_valid && !busy) begin
                hs_valid <= 1'b1;
                hs_data  <= seed;
                busy     <= 1'b1;
            end
            // Finish handshake when done signal is received
            else if (busy && hs_done) begin
                hs_valid <= 1'b0;
                busy     <= 1'b0;
            end
        end
    end

endmodule


module CLK_2_MODULE (
    input              clk2,
    input              rst_n,

    // from handshake_sync
    input              seed_fire, // 接來自 Handshake 的 dst_fire
    input       [31:0] seed_data,

    // to FIFO_syn
    input              fifo_full,
    output reg         wr_en,
    output reg  [31:0] fifo_wr_data
);

    localparam WAIT_SEED = 1'b0;
    localparam GEN       = 1'b1;

    reg        state;
    reg [31:0] rand_reg;
    reg [7:0]  gen_cnt;

    // Xorshift Algorithm Logic
    wire [31:0] x1, x2, x3;
    assign x1 = rand_reg ^ (rand_reg << 13);
    assign x2 = x1       ^ (x1 >> 17);
    assign x3 = x2       ^ (x2 << 5);

    always @(posedge clk2 or negedge rst_n) begin
        if (!rst_n) begin
            state        <= WAIT_SEED;
            rand_reg     <= 32'd0;
            gen_cnt      <= 8'd0;
            wr_en        <= 1'b0;
            fifo_wr_data <= 32'd0;
        end else begin
            wr_en <= 1'b0; 

            case (state)
                WAIT_SEED: begin
                    if (seed_fire) begin
                        rand_reg <= seed_data;
                        gen_cnt  <= 8'd0;
                        state    <= GEN;
                    end
                end

                GEN: begin
                    if (!fifo_full) begin
                        rand_reg     <= x3;
                        fifo_wr_data <= x3;
                        wr_en        <= 1'b1;
                        
                        if (gen_cnt == 8'd255) begin
                            state   <= WAIT_SEED;
                            gen_cnt <= 8'd0;
                        end else begin
                            gen_cnt <= gen_cnt + 1'b1;
                        end
                    end
                end
            endcase
        end
    end
endmodule

module CLK_3_MODULE (
    input               clk3,
    input               rst_n,

    // From FIFO
    input               fifo_empty,
    input      [31:0]   fifo_rd_data,
    output reg          fifo_rd_en,

    // To PATTERN / Output
    output reg          out_valid,
    output reg [31:0]   rand_num
);

    // =====================================================
    // FSM states
    // =====================================================
    localparam S_IDLE    = 2'd0;
    localparam S_RD_REQ  = 2'd1; // 發出讀取請求
    localparam S_RD_DATA = 2'd2; // 接收資料 (FIFO Latency = 1)
    localparam S_DONE    = 2'd3;

    reg [1:0] state, next_state;
    reg [7:0] out_cnt;   // 0~255

    // -------------------------
    // State register
    // -------------------------
    always @(posedge clk3 or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // -------------------------
    // Next-state logic
    // -------------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                // 只有當 FIFO 有資料時才開始動作
                if (!fifo_empty)
                    next_state = S_RD_REQ;
            end

            S_RD_REQ: begin
                // 發出讀取請求後，下一 cycle 資料才會準備好
                next_state = S_RD_DATA;
            end

            S_RD_DATA: begin
                // 資料已讀取，判斷是否已滿 256筆
                if (out_cnt == 8'd255)
                    next_state = S_DONE;
                else if (!fifo_empty) 
                    // 如果還沒滿且 FIFO 還有資料，繼續讀下一筆
                    next_state = S_RD_REQ;
                else 
                    // 如果還沒滿但 FIFO 空了，回到 IDLE 等待資料
                    next_state = S_IDLE;
            end

            S_DONE: begin
                // 完成任務，回到 IDLE (或停留在 DONE，視需求而定)
                next_state = S_IDLE;
            end
        endcase
    end

    // -------------------------
    // Output / Datapath
    // -------------------------
    always @(posedge clk3 or negedge rst_n) begin
        if (!rst_n) begin
            fifo_rd_en <= 1'b0;
            out_valid  <= 1'b0;
            rand_num   <= 32'd0;
            out_cnt    <= 8'd0;
        end else begin
            
            // Default values for pulses
            out_valid  <= 1'b0; 
            fifo_rd_en <= 1'b0;

            case (state)
                S_IDLE: begin
                    // 保持計數器 (如果是重跑則需在此歸零，視 Spec 而定)
                    // 這裡假設回到 IDLE 不會清空計數器，除非是從 DONE 回來
                    if (next_state == S_RD_REQ) begin
                         // 預備動作
                    end
                end

                S_RD_REQ: begin
                    fifo_rd_en <= 1'b1;   // Assert Read Enable
                end

                S_RD_DATA: begin
                    rand_num  <= fifo_rd_data; // Capture Data
                    out_valid <= 1'b1;         // Output Valid Pulse
                    out_cnt   <= out_cnt + 1'b1;
                end

                S_DONE: begin
                    out_cnt <= 8'd0; // Reset counter for next batch
                end
            endcase
        end
    end

endmodule

module PRGN_TOP (
    // Clock & Reset
    input               clk1,
    input               clk2,
    input               clk3,
    input               rst_n,
    // Input signals
    input               in_valid,
    input      [31:0]   seed,
    // Output signals
    output wire         out_valid,
    output wire [31:0]  rand_num
);

    // =====================================================
    // Internal Wires
    // =====================================================

    // CLK_1 to Handshake
    wire [31:0] hs_data_src;
    wire        hs_valid_src;
    wire        hs_done_src;  // [新增] 來自 Handshake 的完成訊號

    // Handshake to CLK_2
    wire [31:0] seed_data_dest;
    wire        seed_fire_dest; // [新增] Handshake 輸出的 Pulse

    // CLK_2 to FIFO
    wire        wr_en;
    wire [31:0] fifo_wr_data;
    wire        fifo_full;

    // FIFO to CLK_3
    wire        fifo_rd_en;
    wire [31:0] fifo_rd_data;
    wire        fifo_empty;

    // =====================================================
    // Module Instantiations
    // =====================================================

    // --- Module 1: 接收 Seed (CLK1) ---
    CLK_1_MODULE u_clk1_mod (
        .clk1     (clk1),
        .rst_n    (rst_n),
        .in_valid (in_valid),
        .seed     (seed),
        
        // 連接到 Handshake Source 端
        .hs_valid (hs_valid_src), 
        .hs_data  (hs_data_src),
        .hs_done  (hs_done_src)   // [修正] 必須連接
    );

    // --- Handshake Synchronizer: clk1 -> clk2 ---
    // 這裡的 Port 名稱必須對應之前定義的 handshake_sync 模組
    handshake_sync #(.W(32)) u_handshake (
        // Source Domain (CLK1)
        .sclk      (clk1),
        .srst_n    (rst_n),
        .src_valid (hs_valid_src), // CLK1 發出的請求
        .src_data  (hs_data_src),  // CLK1 發出的資料
        .src_done  (hs_done_src),  // 回傳給 CLK1 的完成訊號 (ACK回來後)

        // Destination Domain (CLK2)
        .dclk      (clk2),
        .drst_n    (rst_n),
        .dst_fire  (seed_fire_dest), // 輸出給 CLK2 的 Pulse
        .dst_data  (seed_data_dest)  // 輸出給 CLK2 的資料
    );

    // --- Module 2: Xorshift 運算 (CLK2) ---
    CLK_2_MODULE u_clk2_mod (
        .clk2         (clk2),
        .rst_n        (rst_n),
        
        // 來自 Handshake 的輸出
        .seed_fire    (seed_fire_dest),
        .seed_data    (seed_data_dest),
        
        // FIFO 介面
        .fifo_full    (fifo_full),
        .wr_en        (wr_en),
        .fifo_wr_data (fifo_wr_data)
    );

    // --- FIFO Synchronizer: clk2 -> clk3 ---
    // DEPTH = 2^8 = 256
    async_fifo #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) u_fifo (
        // Write Domain (CLK2)
        .wr_clk   (clk2),
        .wr_rst_n (rst_n),
        .wr_en    (wr_en),
        .wr_data  (fifo_wr_data),
        .full     (fifo_full),

        // Read Domain (CLK3)
        .rd_clk   (clk3),
        .rd_rst_n (rst_n),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .empty    (fifo_empty)
    );

    // --- Module 3: 輸出結果 (CLK3) ---
    CLK_3_MODULE u_clk3_mod (
        .clk3         (clk3),
        .rst_n        (rst_n),
        
        // FIFO 介面
        .fifo_empty   (fifo_empty),
        .fifo_rd_data (fifo_rd_data),
        .fifo_rd_en   (fifo_rd_en),
        
        // 最終輸出
        .out_valid    (out_valid),
        .rand_num     (rand_num)
    );

endmodule
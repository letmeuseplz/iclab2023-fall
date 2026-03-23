`timescale 1ns/1ps

module Bridge (
    input  logic        clk,
    input  logic        rst_n,

    // ====================================================
    // from bev
    // ====================================================
    input  logic        C_in_valid,
    input  logic        C_r_wb,     
    input  logic [7:0]  C_addr,   
    input  logic [63:0] C_data_w,   
    
    output logic        C_out_valid,
    output logic [63:0] C_data_r,  

    // ====================================================
    // AXI4-Lite 
    // ====================================================
  
    output logic        AR_VALID,
    output logic [16:0] AR_ADDR,
    input  logic        AR_READY,
    // Read Data Channel
    input  logic        R_VALID,
    input  logic [63:0] R_DATA,
    input  logic [1:0]  R_RESP,
    output logic        R_READY,

    output logic        AW_VALID,
    output logic [16:0] AW_ADDR,
    input  logic        AW_READY,
    // Write Data Channel
    output logic        W_VALID,
    output logic [63:0] W_DATA,
    input  logic        W_READY,
    // Write Response Channel
    input  logic        B_VALID,
    input  logic [1:0]  B_RESP,
    output logic        B_READY
);

    // ====================================================
    // 1. 狀態定義 (極簡化的 AXI 五大通道握手)
    // ====================================================
    typedef enum logic [2:0] {
        ST_IDLE     = 3'd0,
        ST_READ_AR  = 3'd1, // 等待 AR_READY
        ST_READ_R   = 3'd2, // 等待 R_VALID
        ST_WRITE_AW = 3'd3, // 等待 AW_READY
        ST_WRITE_W  = 3'd4, // 等待 W_READY
        ST_WRITE_B  = 3'd5  // 等待 B_VALID
    } state_t;

    state_t state, next_state;

    // ====================================================
    // 2. Next-State 暫存器定義
    // ====================================================
    logic        next_C_out_valid;
    logic [63:0] next_C_data_r;

    logic        next_AR_VALID;
    logic [16:0] next_AR_ADDR;
    logic        next_R_READY;

    logic        next_AW_VALID;
    logic [16:0] next_AW_ADDR;
    logic        next_W_VALID;
    logic [63:0] next_W_DATA;
    logic        next_B_READY;

    // ====================================================
    // 3. 組合邏輯：狀態跳轉與 Next-State 賦值
    // ====================================================
    always_comb begin
       
        next_state       = state;
        
  
        next_C_out_valid = 1'b0;
        next_AR_VALID    = 1'b0;
        next_R_READY     = 1'b0;
        next_AW_VALID    = 1'b0;
        next_W_VALID     = 1'b0;
        next_B_READY     = 1'b0;
    
        next_C_data_r    = C_data_r;
        next_AR_ADDR     = AR_ADDR;
        next_AW_ADDR     = AW_ADDR;
        next_W_DATA      = W_DATA;

        case (state)
            ST_IDLE: begin
                if (C_in_valid) begin
 
                    if (C_r_wb == 1'b1) begin 
                        next_state   = ST_READ_AR;
                        next_AR_ADDR = 17'h10000 + {6'b0, C_addr, 3'b000}; 
                    end else begin            
                        next_state   = ST_WRITE_AW;
                        next_AW_ADDR = 17'h10000 + {6'b0, C_addr, 3'b000};
                        next_W_DATA  = C_data_w;
                    end
                end
            end

            // ---------------------------------------------
            // AXI 讀取通道 (Read Channel)
            // ---------------------------------------------
            ST_READ_AR: begin
                next_AR_VALID = 1'b1;
                if (AR_READY) begin
                    next_state = ST_READ_R;
                end
            end

            ST_READ_R: begin
                next_R_READY = 1'b1;
                if (R_VALID) begin
                    next_C_data_r    = R_DATA;
                    next_C_out_valid = 1'b1; // 準備在下個 cycle 拉高 out_valid
                    next_state       = ST_IDLE; // 省略 OUT 狀態，直接回 IDLE 提升效能
                end
            end

            // ---------------------------------------------
            // AXI 寫入通道 (Write Channel)
            // ---------------------------------------------
            ST_WRITE_AW: begin
                next_AW_VALID = 1'b1;
                if (AW_READY) begin
                    next_state = ST_WRITE_W;
                end
            end

            ST_WRITE_W: begin
                next_W_VALID = 1'b1;
                if (W_READY) begin
                    next_state = ST_WRITE_B;
                end
            end

            ST_WRITE_B: begin
                next_B_READY = 1'b1;
                if (B_VALID) begin
                    next_C_out_valid = 1'b1; // 通知 BEV 寫入完成
                    next_state       = ST_IDLE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // ====================================================
    // 4. 循序邏輯：暫存器更新
    // ====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            C_out_valid <= 1'b0;
            C_data_r    <= 64'd0;
            
            AR_VALID    <= 1'b0;
            AR_ADDR     <= 17'd0;
            R_READY     <= 1'b0;
            
            AW_VALID    <= 1'b0;
            AW_ADDR     <= 17'd0;
            W_VALID     <= 1'b0;
            W_DATA      <= 64'd0;
            B_READY     <= 1'b0;
        end else begin
            state       <= next_state;
            C_out_valid <= next_C_out_valid;
            C_data_r    <= next_C_data_r;
            
            AR_VALID    <= next_AR_VALID;
            AR_ADDR     <= next_AR_ADDR;
            R_READY     <= next_R_READY;
            
            AW_VALID    <= next_AW_VALID;
            AW_ADDR     <= next_AW_ADDR;
            W_VALID     <= next_W_VALID;
            W_DATA      <= next_W_DATA;
            B_READY     <= next_B_READY;
        end
    end

endmodule
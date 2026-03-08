    `timescale 1ns/1ps
module SNN #(
    parameter IMG_W   = 4,
    parameter IMG_H   = 4,
    parameter CH      = 3,
    parameter DATA_W  = 32,
    parameter SIG_W   = 23,
    parameter EXP_W   = 8,
   
    parameter PIPE_LAT = 4
)(
    input                   clk,
    input                   rst_n,
    input                   in_valid,
    input                   cg_en,     // clock gating enable for power saving (1 to enable gating, 0 to disable gating)
    input  [DATA_W-1:0]     Img,
    input  [DATA_W-1:0]     Kernel,
    input  [DATA_W-1:0]     Weight,
    input  [1:0]            Opt,      // Opt[0]: 1=zero padding, 0=replicate; Opt[1]: 0=sigmoid,1=tanh
    output reg              out_valid,
    output reg [DATA_W-1:0] out



);

    // -------------------------
    // Derived params
    // -------------------------
    localparam CELLS_PER_IMG = IMG_W * IMG_H;        // 16
    localparam IMG_MEM_SZ    = CELLS_PER_IMG * CH;   // 48 (one image channel-major)
    localparam IMG_BUF_SZ    = IMG_MEM_SZ * 2;       // 96 (two images)
    localparam KERNEL_SZ     = 9 * CH;               // 27
    localparam FEAT_SZ       = CELLS_PER_IMG * 2;    // 32 (two images)
    localparam NUM_ELEM_PER_IMG = 4;


    // -------------------------
    // FSM states (top-level simplified)
    // -------------------------
    localparam ST_IDLE = 3'd0,
               ST_RUN  = 3'd1, // receive & conv overlapped
               ST_EQUAL = 3'd2, 
               ST_POOL = 3'd3,
               ST_FC   = 3'd4,
               ST_NORM = 3'd5,
               ST_ACTV = 3'd6,
               ST_OUT  = 3'd7;

    reg [2:0] state, nstate;

    // -------------------------
    // Inputs reception
    // -------------------------
    reg [6:0] recv_count; // 0..95 global count of Img inputs received
  
    reg [6:0] ker_ptr;
    reg [2:0] wt_ptr;
  
    reg [1:0]  opt_reg;

    // memories
    reg [DATA_W-1:0] img_buf [0:IMG_BUF_SZ-1]; // 96 entries (two images)
    reg [DATA_W-1:0] ker_buf [0:KERNEL_SZ-1];  // 27
    reg [DATA_W-1:0] weight_buf [0:3];         // 4

    // -------------------------
    // Convolution control counters (streaming)
    // -------------------------
    reg [3:0] conv_pos;   // 0..15 (center pos in 4x4)
    reg [1:0] conv_ch;    // 0..2
    reg       conv_img;   // 0..1



    // local variables for loops
    integer i, p;

    integer k;
    reg  gflag1, gflag0;
    reg [3:0] idx_hist[0:6];
    reg img_hist[0:6];
    reg valid_hist[0:6];
    reg [7:0] cnt_img0;
    reg [7:0] cnt_img1;
    assign gflag_all = (cnt_img0 == 48)& (cnt_img1 == 48);
    
    reg [1:0] ch_hist [0:PIPE_LAT-1];
    integer m;

    // -------------------------
    // Fully connected round control
    // -------------------------

    reg  fc_round;      // 0 or 1
    reg  fc_done;       // 該輪完成旗標
    reg  actv_done;
    reg  sum_ch;
    reg [DATA_W-1:0] a01_reg, a23_reg, a45_reg, a67_reg;
    reg [DATA_W-1:0]flatten[0:7];
    reg [3:0] fc_cnt;
    // -------------------------
    // Pooling cintrol signals
    // -------------------------

    
    reg [DATA_W-1:0] feat_buf [0:31];   // 一維存兩張圖
    reg [DATA_W-1:0] max_top[0:3];
    reg [DATA_W-1:0] max_bot[0:3];
    reg [DATA_W-1:0] pooled[0:7];
    reg [2:0]         pool_stage;
    reg [3:0]         idx_ul, idx_ur, idx_dl, idx_dr;
    reg               pool_done;
    reg               pool_round;      // 0: 第一張, 1: 第二張
    wire              pool_all_done;
    wire [4:0] pool_base = pool_round ? 5'd16 : 5'd0;

    // -------------------------
    // 暫存器共用
    // -------------------------

    reg [DATA_W-1:0] mult_a_reg [0:8];
    reg [DATA_W-1:0] mult_b_reg [0:8];
    
    wire [DATA_W-1:0] shared_sub_z;

  
    wire [DATA_W-1:0] shared_div_z;
    reg [DATA_W-1:0] act_a1, act_b1, act_a2, act_b2;
    reg [DATA_W-1:0] cmp_a0_r, cmp_b0_r, cmp_a1_r, cmp_b1_r;
    wire[DATA_W-1:0] cmp_a0_w, cmp_b0_w, cmp_a1_w, cmp_b1_w;
 
    wire cmp0_gt, cmp1_gt, cmp0_unord, cmp1_unord;
    // -------------------------
    // NORMALIZED CONTROL SIGNALS
    // -------------------------

    reg [3:0] norm_s;
    reg [1:0] norm_img_idx;
    reg [3:0] elem_idx;
    reg [DATA_W-1:0] max_01, min_01, max_23, min_23;
    reg [DATA_W-1:0] global_max, global_min;
    reg [DATA_W-1:0] denom_reg;
    reg [DATA_W-1:0] sub_reg;
    reg norm_done;

    // -------------------------
    // ACTIVATE CONTROL SIGNALS
    // -------------------------

    reg local_add_out;
    reg [2:0] actv_s;
    reg [3:0] actv_idx;

    reg [DATA_W-1:0] actv_tmp1;
    reg [DATA_W-1:0] exp_x_reg;
    wire[DATA_W-1:0] exp_x;
    reg [DATA_W-1:0] inv_exp_reg;
    reg [DATA_W-1:0] add_out_reg;
    reg [DATA_W-1:0] add_out_reg2;
    reg [DATA_W-1:0] sub_out_reg;

    reg local_add_a;
    reg local_add_b;
    reg [2:0] l1_stage;
    reg [2:0] l1_idx;
    reg [DATA_W-1:0] l1_abs [0:3];
    reg [DATA_W-1:0] acc;

    // shared_sub / shared_add
    reg  [DATA_W-1:0] sub_in_a, sub_in_b;
    reg [DATA_W-1:0] sub_in_al1, sub_in_bl1;
    wire [DATA_W-1:0] sub_out;
    
    reg  [DATA_W-1:0] add_a, add_b;
  

    wire do_div = (elem_idx > 0 && elem_idx <= NUM_ELEM_PER_IMG);
    wire do_sub = (elem_idx < NUM_ELEM_PER_IMG);
    wire is_last = (elem_idx == NUM_ELEM_PER_IMG+1);
    wire do_store = (elem_idx > 1);
    wire equal_done = (state == ST_EQUAL) && (cnt_img0 == 16) && (cnt_img1 == 16);
    // =========================================================
    // Clock Gating Cells 
    // =========================================================
  
// 💡 確保在加法運算、輸出答案，或是接收新測資時，Clock 都有在跳動
    wire sleep_add = cg_en && !(state == ST_FC || state == ST_RUN || state == ST_EQUAL || state == ST_ACTV || state == ST_OUT || in_valid || out_valid);
    wire clk_add;
    GATED_OR GATED_ADD (.CLOCK(clk), .SLEEP_CTRL(sleep_add), .RST_N(rst_n), .CLOCK_GATED(clk_add));

    wire sleep_mult = cg_en && !(state == ST_RUN || state == ST_EQUAL || state == ST_FC || in_valid || out_valid);
    wire clk_mult;
    GATED_OR GATED_MULT (.CLOCK(clk), .SLEEP_CTRL(sleep_mult), .RST_N(rst_n), .CLOCK_GATED(clk_mult));

    // 💡 兇手在這裡！加上 in_valid 和 out_valid，讓 feat_buf 可以在換題時順利起床洗澡！
    wire sleep_feat = cg_en && !(state == ST_RUN || state == ST_EQUAL || in_valid || out_valid);
    wire clk_feat;
    GATED_OR GATED_FEAT (.CLOCK(clk), .SLEEP_CTRL(sleep_feat), .RST_N(rst_n), .CLOCK_GATED(clk_feat));

    wire sleep_pool    = cg_en && !(state == ST_POOL || pool_done || in_valid || out_valid);
    wire clk_pool;
    GATED_OR GATED_POOL (.CLOCK(clk), .SLEEP_CTRL(sleep_pool), .RST_N(rst_n), .CLOCK_GATED(clk_pool));

    wire sleep_flatten = cg_en && !(state == ST_FC || state == ST_ACTV || in_valid || out_valid);
    wire clk_flatten;
    GATED_OR GATED_FLATTEN (.CLOCK(clk), .SLEEP_CTRL(sleep_flatten), .RST_N(rst_n), .CLOCK_GATED(clk_flatten));

    wire sleep_fc_ctrl = cg_en && !(state == ST_FC || fc_done || in_valid || out_valid);
    wire clk_fc;
    GATED_OR GATED_FC_CTRL (.CLOCK(clk), .SLEEP_CTRL(sleep_fc_ctrl), .RST_N(rst_n), .CLOCK_GATED(clk_fc));

    wire sleep_norm    = cg_en && !(state == ST_NORM || norm_done || in_valid || out_valid);
    wire clk_norm;
    GATED_OR GATED_NORM (.CLOCK(clk), .SLEEP_CTRL(sleep_norm), .RST_N(rst_n), .CLOCK_GATED(clk_norm));

    wire sleep_actv    = cg_en && !(state == ST_ACTV || actv_done || in_valid || out_valid);
    wire clk_actv;
    GATED_OR GATED_ACTV (.CLOCK(clk), .SLEEP_CTRL(sleep_actv), .RST_N(rst_n), .CLOCK_GATED(clk_actv));

    wire sleep_out     = cg_en && !(state == ST_OUT || out_valid || in_valid);
    wire clk_out;
    GATED_OR GATED_OUT (.CLOCK(clk), .SLEEP_CTRL(sleep_out), .RST_N(rst_n), .CLOCK_GATED(clk_out));
    // -------------------------
    // FSM MACHINE CONTROL
    // -------------------------

    always @(*) begin
    nstate = state;
        case (state)
            ST_IDLE: if (in_valid) nstate = ST_RUN;

            ST_RUN:  if (gflag_all) nstate = ST_EQUAL;

            ST_EQUAL: if (equal_done) nstate = ST_POOL;

            ST_POOL: if (pool_done) nstate = ST_FC;

            ST_FC: begin
                 if (fc_done && fc_round == 1)
                    nstate = ST_NORM;    // 兩輪都結束才進 normalize
                else
                    nstate = ST_FC;
                end

            ST_NORM: if (norm_done) nstate = ST_ACTV;
            ST_ACTV: if (actv_done) nstate = ST_OUT;
            ST_OUT:  if (out_valid) nstate = ST_IDLE;

            default: nstate = ST_IDLE;
        endcase
        end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= nstate;
        end
    end

   // Input reception: write incoming Img/Kernels/Weights into buffers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            recv_count <= 0;
            ker_ptr <= 0;
            wt_ptr <= 0;
            opt_reg <= 2'b00;

        end 
        else if(out_valid) begin
            recv_count <= 0;
            ker_ptr <= 0;
            wt_ptr <= 0;
            end
        else begin
            if (in_valid) begin
                if (recv_count == 0) 
                    opt_reg <= Opt;
            
                if (recv_count < IMG_BUF_SZ) begin
                    img_buf[recv_count] <= Img;
                    recv_count <= recv_count + 1;
                end

                // kernel loading (first 27 cycles)
                if (ker_ptr < KERNEL_SZ) begin
                    ker_buf[ker_ptr] <= Kernel;
          
                    ker_ptr <= ker_ptr + 1;
                end

                // weight loading (4 cycles)
                if (wt_ptr < 4) begin
                    weight_buf[wt_ptr] <= Weight;
                    wt_ptr <= wt_ptr + 1;
                end
            end
        end

    end


    // DesignWare multiplier instances (combinational)
    // NOTE: pipeline parameter set to 0 => combinational (depends on your DW version).
    // Verify with DW manual and change param position/value if your vendor differs.
    // -------------------------
    wire [DATA_W-1:0] prod_wire [0:8];
    reg [DATA_W-1:0] prod_reg[0:8];
    genvar gi;
    generate
        for (gi=0; gi<9; gi=gi+1) begin : MULTS
            DW_fp_mult #(SIG_W, EXP_W, 0) mult_i (
                .a(mult_a_reg[gi]),
                .b(mult_b_reg[gi]),
                .rnd(3'b000),
                .z(prod_wire[gi]),
                .status()
            );
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            for (p=0; p<9; p=p+1)
                prod_reg[p] <= 0;
        else
            for (p=0; p<9; p=p+1)
                prod_reg[p] <= prod_wire[p];
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (m = 0; m < PIPE_LAT; m = m + 1) 
                ch_hist[m] <= 0;
        end else if (state == ST_RUN) begin
            ch_hist[0] <= conv_ch;
            for (m = 1; m < PIPE_LAT; m = m + 1) 
                ch_hist[m] <= ch_hist[m-1];
        end
        // else: hold previous values (do nothing)
    end
    
    // ---------------------------------------------------------
    // combinational: compute win_addr_next and win_pad_flag_next
    // ---------------------------------------------------------
    reg [15:0] win_addr_next [0:8];
    reg        win_pad_flag_next [0:8];
    reg [15:0] win_addr_reg [0:8];
    reg        win_pad_flag_reg [0:8]; 
    integer center_r, center_c;
    integer rr, cc, r, c;
    integer rr_cl, cc_cl;
    
   wire [15:0] base_addr = (state == ST_RUN) ? 
                            (conv_img * IMG_MEM_SZ + (conv_ch * CELLS_PER_IMG)) : // ST_RUN 讀 3 通道原圖
                            (conv_img * CELLS_PER_IMG);
    integer ch_offset;

    always @(*) begin
        // 1. 預設值（避免 latches）
        for (p = 0; p < 9; p = p + 1) begin
            win_addr_next[p]     = 16'd0;
            win_pad_flag_next[p] = 1'b0;
        end

        if ((state == ST_RUN && recv_count > 15) || (state == ST_EQUAL)) begin
            
            center_r = conv_pos[3:2];
            center_c = conv_pos[1:0];

         
           

            for (p=0; p<9; p=p+1) begin
                case (p)
                    0: begin rr = -1; cc = -1; end
                    1: begin rr = -1; cc =  0; end
                    2: begin rr = -1; cc =  1; end
                    3: begin rr =  0; cc = -1; end  
                    4: begin rr =  0; cc =  0; end
                    5: begin rr =  0; cc =  1; end
                    6: begin rr =  1; cc = -1; end
                    7: begin rr =  1; cc =  0; end
                    8: begin rr =  1; cc =  1; end
                endcase
                
                r = center_r + rr;
                c = center_c + cc;
                
                if (r < 0 || r >= IMG_H || c < 0 || c >= IMG_W) begin
                    if (opt_reg[0] == 1'b1) begin // ZERO PADDING
                        win_pad_flag_next[p] = 1'b1;
                        win_addr_next[p]     = 16'd0;
                    end else begin // REPLICATE PADDING
                        rr_cl = (r < 0) ? 0 : ((r >= IMG_H) ? IMG_H-1 : r);
                        cc_cl = (c < 0) ? 0 : ((c >= IMG_W) ? IMG_W-1 : c);
                        win_pad_flag_next[p] = 1'b0;
                       
                       win_addr_next[p] = base_addr + rr_cl * IMG_W + cc_cl;
                    end
                end else begin
                    win_pad_flag_next[p] = 1'b0;
                    
                    win_addr_next[p] = base_addr + r * IMG_W + c;
                end
            end
        end
    end


    //-----------------------------------------------------
    // EQUAL Stage: 準備 9 個輸入給加法樹 
    //-----------------------------------------------------
    wire [DATA_W-1:0] equal_val [0:8];
    genvar g;
    generate
        for (g = 0; g < 9; g = g + 1) begin : EQUAL_VAL_GEN
            
            assign equal_val[g] = (win_pad_flag_reg[g]) ? 32'd0 : feat_buf[win_addr_reg[g]];
        end
    endgenerate

    //-----------------------------------------------------
    // Adder Tree 輸入 MUX
    //-----------------------------------------------------
    // 第一層 (吃 equal_val 或 乘法器結果)
    wire [DATA_W-1:0] add01_a = (state == ST_EQUAL) ? equal_val[0] : ((state == ST_ACTV) ? act_a1 : prod_reg[0]);
    wire [DATA_W-1:0] add01_b = (state == ST_EQUAL) ? equal_val[1] : ((state == ST_ACTV) ? act_b1 : prod_reg[1]);

    wire [DATA_W-1:0] add02_a = (state == ST_EQUAL) ? equal_val[2] : ((state == ST_ACTV) ? act_a2 : prod_reg[2]);
    wire [DATA_W-1:0] add02_b = (state == ST_EQUAL) ? equal_val[3] : ((state == ST_ACTV) ? act_b2 : prod_reg[3]);

    wire [DATA_W-1:0] add03_a = (state == ST_EQUAL) ? equal_val[4] : ((state == ST_OUT)  ? add_a  : prod_reg[4]);
    wire [DATA_W-1:0] add03_b = (state == ST_EQUAL) ? equal_val[5] : ((state == ST_OUT)  ? add_b  : prod_reg[5]);

    wire [DATA_W-1:0] add67_a = (state == ST_EQUAL) ? equal_val[6] : prod_reg[6];
    wire [DATA_W-1:0] add67_b = (state == ST_EQUAL) ? equal_val[7] : prod_reg[7];
    wire [DATA_W-1:0] add_final_b = (state == ST_EQUAL) ? equal_val[8] : prod_reg[8];
   
    wire [DATA_W-1:0] a01, a23, a45, a67;
    reg [DATA_W-1:0] add_final_b_reg;
    
    wire [DATA_W-1:0] a0123, a4567, tmp_all, sum_shared;
    wire [DATA_W-1:0] acc_in_feat; 
    wire [DATA_W-1:0] acc_out;     
    reg [DATA_W-1:0] equal_buf [0:FEAT_SZ-1];
    wire[4:0] feat_idx = idx_hist[PIPE_LAT-1] + (img_hist[PIPE_LAT-1] << 4);
    wire [4:0] equal_idx = idx_hist[PIPE_LAT-1] + (img_hist[PIPE_LAT-1] << 4);
    assign acc_in_feat = feat_buf[feat_idx];

    //-----------------------------------------------------
    //
    //-----------------------------------------------------
    DW_fp_add #(SIG_W, EXP_W, 0) add01(.a(add01_a), .b(add01_b), .rnd(3'b000), .z(a01),.status());
    DW_fp_add #(SIG_W, EXP_W, 0) add23(.a(add02_a), .b(add02_b), .rnd(3'b000), .z(a23),.status());
    DW_fp_add #(SIG_W, EXP_W, 0) add45(.a(add03_a), .b(add03_b), .rnd(3'b000), .z(a45),.status());
    DW_fp_add #(SIG_W, EXP_W, 0) add67(.a(add67_a), .b(add67_b), .rnd(3'b000), .z(a67),.status());

 
    always @(posedge clk_add or negedge rst_n) begin
        if (!rst_n) begin
            a01_reg <= 0;
            a23_reg <= 0;
            a45_reg <= 0;
            a67_reg <= 0;
            add_final_b_reg <= 0;
        end else if (state == ST_FC || state == ST_RUN || state == ST_EQUAL || state == ST_ACTV || state == ST_OUT) begin
            a01_reg <= a01;
            a23_reg <= a23;
            a45_reg <= a45;
            a67_reg <= a67;
            add_final_b_reg <= add_final_b; 
        end
    end


    //-----------------------------------------------------
    //
    //-----------------------------------------------------
    DW_fp_add #(SIG_W, EXP_W, 0) add0123(.a(a01_reg), .b(a23_reg), .rnd(3'b000), .z(a0123),.status());
    DW_fp_add #(SIG_W, EXP_W, 0) add4567(.a(a45_reg), .b(a67_reg), .rnd(3'b000), .z(a4567),.status());
    DW_fp_add #(SIG_W, EXP_W, 0) add_all(.a(a0123), .b(a4567), .rnd(3'b000), .z(tmp_all),.status());
    DW_fp_add #(SIG_W, EXP_W, 0) add_final(.a(tmp_all), .b(add_final_b_reg), .rnd(3'b000), .z(sum_shared),.status());
   
 

    
    
    DW_fp_add #(SIG_W, EXP_W, 0) add_acc (
        .a(acc_in_feat), 
        .b(sum_shared), 
        .rnd(3'b000), 
        .z(acc_out),
        .status()
    );
    //-----------------------------------------------------
    // MULT inputs (共用 FC / CONV / EQUAL) + Clock Gating
    //-----------------------------------------------------
    always @(posedge clk_mult or negedge rst_n) begin
        if (!rst_n) begin
            for (p=0; p<9; p=p+1) begin
                mult_a_reg[p] <= 32'd0;
                mult_b_reg[p] <= 32'd0;
            end
        end else begin
            
            for (p=0; p<9; p=p+1) begin
                mult_a_reg[p] <= mult_a_reg[p];
                mult_b_reg[p] <= mult_b_reg[p];
            end

            case (state)
                // -----------------------------
                // 卷積層 (9 顆全開)
                // -----------------------------
                ST_RUN: begin
                    for (p=0; p<9; p=p+1) begin
                        if (win_pad_flag_reg[p])
                            mult_a_reg[p] <= {DATA_W{1'b0}};
                        else
                            mult_a_reg[p] <= img_buf[win_addr_reg[p]];

                        mult_b_reg[p] <= ker_buf[p + (ch_hist[0] * 9)];
                    end
                end

               
                ST_EQUAL: begin
                  
                    mult_a_reg[0] <= sum_shared;
                    mult_b_reg[0] <= 32'h3DE38E39; //  1/9
                    
                 
                end

                // -----------------------------
                // 全連接層 (用到 8 顆，第 9 顆休眠)
                // -----------------------------
                ST_FC: begin
                    if (fc_round == 0) begin
                        mult_a_reg[0] <= pooled[0];
                        mult_a_reg[1] <= pooled[1];
                        mult_a_reg[2] <= pooled[0];
                        mult_a_reg[3] <= pooled[1];
                        mult_a_reg[4] <= pooled[2];
                        mult_a_reg[5] <= pooled[3];
                        mult_a_reg[6] <= pooled[2];
                        mult_a_reg[7] <= pooled[3];
                    end else begin
                        mult_a_reg[0] <= pooled[4];
                        mult_a_reg[1] <= pooled[5];
                        mult_a_reg[2] <= pooled[4];
                        mult_a_reg[3] <= pooled[5];
                        mult_a_reg[4] <= pooled[6];
                        mult_a_reg[5] <= pooled[7];
                        mult_a_reg[6] <= pooled[6];
                        mult_a_reg[7] <= pooled[7];
                    end

                    mult_b_reg[0] <= weight_buf[0];
                    mult_b_reg[1] <= weight_buf[2];
                    mult_b_reg[2] <= weight_buf[1];
                    mult_b_reg[3] <= weight_buf[3];
                    mult_b_reg[4] <= weight_buf[0];
                    mult_b_reg[5] <= weight_buf[2];
                    mult_b_reg[6] <= weight_buf[1];
                    mult_b_reg[7] <= weight_buf[3];
                    
                  
                end
            endcase
        end
    end


    // ---------------------------------------------------------
    // Cycle 1 → Cycle 2 : registers
    // ---------------------------------------------------------


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (p=0; p<9; p=p+1) begin
                win_addr_reg[p]     <= 16'd0;
                win_pad_flag_reg[p] <= 1'b0;
            end
        end else begin

            for (p=0; p<9; p=p+1) begin
                win_addr_reg[p]     <= win_addr_next[p];
                win_pad_flag_reg[p] <= win_pad_flag_next[p];
            end
        end
    end

  

    // ==========================================
    // CONTROL for convolution and equalization 
    // ==========================================
    reg gen_done; 

    wire run_en   = (state == ST_RUN)   && (recv_count > 15) && !gen_done;
    wire equal_en = (state == ST_EQUAL) && !gen_done;

    wire clear_cnt = (state == ST_IDLE) || (state == ST_RUN && gflag_all);
    // ==========================================
    //coordinate generation for convolution and equalization (with padding handling)
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conv_ch  <= 0;
            conv_pos <= 0;
            conv_img <= 0;
            gen_done <= 0;
        end 
        else if (clear_cnt) begin
            conv_ch  <= 0;
            conv_pos <= 0;
            conv_img <= 0;
            gen_done <= 0;
        end
        else if (run_en) begin
            if (conv_pos == 15) begin
                conv_pos <= 0;
                if (conv_ch == 2) begin
                    conv_ch <= 0;
                    if (conv_img == 1) begin
                        conv_img <= 0;
                        gen_done <= 1'b1; 
                    end else begin
                        conv_img <= conv_img + 1;
                    end
                end
                else begin
                    conv_ch <= conv_ch + 1;
                end
            end else begin
                conv_pos <= conv_pos + 1;
            end
        end
        else if (equal_en) begin
            if (conv_pos == 15) begin
                conv_pos <= 0;
                if (conv_img == 1) begin
                    conv_img <= 0;
                    gen_done <= 1'b1; 
                end else begin
                    conv_img <= conv_img + 1;
                end
            end else begin
                conv_pos <= conv_pos + 1;
            end
        end
        else if (state != ST_RUN && state != ST_EQUAL) begin
             gen_done <= 1'b0;
        end
    end

   // ==========================================
    // 管線歷史紀錄與影像計數器
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < PIPE_LAT; k = k + 1) begin
                idx_hist[k]   <= 0;
                img_hist[k]   <= 0;
                valid_hist[k] <= 0;
            end
            cnt_img0 <= 0;
            cnt_img1 <= 0;
            gflag0   <= 0;
            gflag1   <= 0;
        end
        // 💡 修正處：在 IDLE 狀態準備迎接新測資時，將計數器與有效訊號洗乾淨
        else if (out_valid) begin 
            cnt_img0 <= 0;
            cnt_img1 <= 0;
            gflag0   <= 0;
            gflag1   <= 0;
            for (k = 0; k < PIPE_LAT; k = k + 1) begin
                valid_hist[k] <= 0; // 順便清掉 valid 歷史，避免誤寫入
            end
        end
        else if (state == ST_RUN && cnt_img0 == 48 && cnt_img1 == 48) begin
            cnt_img0 <= 0;
            cnt_img1 <= 0;
        end
        else begin
            if (state == ST_RUN || state == ST_EQUAL) begin
                for (k = PIPE_LAT-1; k > 0; k = k - 1) begin
                    idx_hist[k]   <= idx_hist[k-1];
                    img_hist[k]   <= img_hist[k-1];
                    valid_hist[k] <= valid_hist[k-1];
                end

                idx_hist[0] <= conv_pos;
                img_hist[0] <= conv_img;
                
                if (state == ST_RUN) begin
                    valid_hist[0] <= run_en;
                end else begin // state == ST_EQUAL
                    valid_hist[0] <= equal_en;
                end
            end

            if (state == ST_RUN) begin
                if (valid_hist[PIPE_LAT-1]) begin
                    if (img_hist[PIPE_LAT-1] == 1'b0) begin
                        if (cnt_img0 < 48) cnt_img0 <= cnt_img0 + 1;
                    end else begin
                        if (cnt_img1 < 48) cnt_img1 <= cnt_img1 + 1;
                    end
                end
            end
            else if (state == ST_EQUAL) begin
                if (valid_hist[PIPE_LAT-2]) begin
                    if (img_hist[PIPE_LAT-2] == 1'b0) begin
                        if (cnt_img0 < 16) cnt_img0 <= cnt_img0 + 1;
                    end else begin
                        if (cnt_img1 < 16) cnt_img1 <= cnt_img1 + 1;
                    end
                end
            end
        end
    end

    // ===============================================================
    // 1. Feature Buffer: 專門存 ST_RUN 算出來的原始卷積結果 (acc_out)
    // ===============================================================
    always @(posedge clk_feat or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < FEAT_SZ; i = i + 1) begin
                feat_buf[i] <= {DATA_W{1'b0}};
            end
        end
        // 💡 修正：在吐出答案的那 1 拍 (out_valid == 1) 順便洗乾淨
        // 此時你的 sleep_feat 剛好會讓 clk_feat 醒著，清零才能成功！
        else if (out_valid) begin
            for (i = 0; i < FEAT_SZ; i = i + 1) begin
                feat_buf[i] <= {DATA_W{1'b0}};
            end
        end
        else begin
            if (state == ST_RUN && valid_hist[PIPE_LAT-1]) begin
                feat_buf[feat_idx] <= acc_out;
            end
        end
    end


    // ===============================================================
    // 2. Equal Buffer: 專門存 ST_EQUAL 算完 1/9 的結果 (prod_reg[0])
    // ===============================================================
 
    always @(posedge clk_feat or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < FEAT_SZ; i = i + 1) begin
                equal_buf[i] <= {DATA_W{1'b0}};
            end
        end
        else begin
          
            if (state == ST_EQUAL && valid_hist[PIPE_LAT-1]) begin
                equal_buf[equal_idx] <= prod_reg[0];
            end
        end
    end
    // ---------------------------------------------------------
    // COMPARATOR INPUT ROUTING (With Global Power Gating)
    // ---------------------------------------------------------
 
    wire cmp_en = (state == ST_NORM) || (state == ST_POOL);

    assign cmp_a0_w = 
        (!cmp_en) ? {DATA_W{1'b0}} : 
        (state == ST_NORM) ? cmp_a0_r :
        (pool_stage < 3'd4) ? equal_buf[pool_base + idx_ul] : 
                            max_top[pool_stage - 3'd4];

    assign cmp_b0_w = 
        (!cmp_en) ? {DATA_W{1'b0}} :
        (state == ST_NORM) ? cmp_b0_r :
        (pool_stage < 3'd4) ? equal_buf[pool_base + idx_ur] : 
                            max_bot[pool_stage - 3'd4];

    assign cmp_a1_w = 
        (!cmp_en) ? {DATA_W{1'b0}} :
        (state == ST_NORM) ? cmp_a1_r :
        (pool_stage < 3'd4) ? equal_buf[pool_base + idx_dl] : 
                            {DATA_W{1'b0}};

    assign cmp_b1_w = 
        (!cmp_en) ? {DATA_W{1'b0}} :
        (state == ST_NORM) ? cmp_b1_r :
        (pool_stage < 3'd4) ? equal_buf[pool_base + idx_dr] : 
                            {DATA_W{1'b0}};





    // =============================================================
    // Two-comparator 2x2 max pooling (for two 4x4 feature maps)
    // equal_buf[0:15]  = image 0
    // equal_buf[16:31] = image 1
    // =============================================================



    DW_fp_cmp #(SIG_W, EXP_W, 0) cmp_upper (
        .a(cmp_a0_w),
        .b(cmp_b0_w),
        .zctr(1'b0),          
        .agtb(cmp0_gt),
        .unordered(cmp0_unord),
        .aeqb(),            
        .altb(),
        .z0(),
        .z1(),
        .status0(),
        .status1()
    );

   
    DW_fp_cmp #(SIG_W, EXP_W, 0) cmp_lower (
        .a(cmp_a1_w),
        .b(cmp_b1_w),
        .zctr(1'b0),       
        .agtb(cmp1_gt),
        .unordered(cmp1_unord),
        .aeqb(),
        .altb(),
        .z0(),
        .z1(),
        .status0(),
        .status1()
    );
    //-----------------------------------------------------
    // POOL INPUT ROUTING (pure combinational)
    //-----------------------------------------------------

    always @(*) begin
        case (pool_stage)
            3'd0: begin idx_ul = 0;  idx_ur = 1;  idx_dl = 4;  idx_dr = 5; end
            3'd1: begin idx_ul = 2;  idx_ur = 3;  idx_dl = 6;  idx_dr = 7; end
            3'd2: begin idx_ul = 8;  idx_ur = 9;  idx_dl = 12; idx_dr = 13; end
            3'd3: begin idx_ul = 10; idx_ur = 11; idx_dl = 14; idx_dr = 15; end
            default: begin idx_ul = 0; idx_ur = 0; idx_dl = 0; idx_dr = 0; end
        endcase
    end

  
   

    reg [DATA_W-1:0] norm_div_a, norm_div_b;
    reg [DATA_W-1:0] actv_div_a, actv_div_b;
    wire[DATA_W-1:0] shared_div_a,shared_div_b;
    assign shared_div_a = (state == ST_NORM) ? norm_div_a : actv_div_a;
    assign shared_div_b = (state == ST_NORM) ? norm_div_b : actv_div_b;


   // ==========================================
    // Max Pooling 控制邏輯
    // ==========================================
    always @(posedge clk_pool or negedge rst_n) begin
        if (!rst_n) begin
            pool_stage <= 3'd0;
            pool_round <= 1'b0;
            pool_done  <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                max_top[i] <= 0;
                max_bot[i] <= 0;
                pooled[i]  <= 0;
            end
        end 
        else if (state == ST_POOL) begin
            pool_done <= 1'b0;
            case (pool_stage)
                3'd0,3'd1,3'd2,3'd3: begin
                    max_top[pool_stage] <= cmp0_unord ? cmp_a0_w : (cmp0_gt ? cmp_a0_w : cmp_b0_w);
                    max_bot[pool_stage] <= cmp1_unord ? cmp_a1_w : (cmp1_gt ? cmp_a1_w : cmp_b1_w);
                    pool_stage <= pool_stage + 1'b1;
                end
                3'd4,3'd5,3'd6,3'd7: begin
                    pooled[pool_round*4+pool_stage - 3'd4] <= cmp0_unord ? cmp_a0_w : (cmp0_gt ? cmp_a0_w: cmp_b0_w);
                    if (pool_stage == 3'd7) begin
                        pool_stage <= 3'd0;
                        if (pool_round == 1'b0)
                            pool_round <= 1'b1;  // 下一張
                        else begin
                            pool_round <= 1'b0;
                            pool_done  <= 1'b1;  // 兩張都完成
                        end
                    end
                    else
                        pool_stage <= pool_stage + 1'b1;
                end
                default: pool_stage <= 3'd0;
            endcase
        end
        else begin
            pool_stage <= 3'd0;
            pool_done  <= 1'b0;
            pool_round <= 1'b0; 
        end
    end
    

    
    //-----------------------------------------------------
    // Flatten output buffer (合併兩輪 FC 結果)
    //-----------------------------------------------------

     
    localparam  ACTV_S_IDLE        = 3'd0,
                ACTV_S_EXP_START   = 3'd1,
                ACTV_S_EXP_WAIT    = 3'd2,
                ACTV_S_INV_LATCH   = 3'd3,
                ACTV_S_POSTINV_PRE = 3'd4,
                ACTV_S_FINAL_PREP  = 3'd5,
                ACTV_S_DONE        = 3'd6;

    localparam  NORM_S_SET01    = 4'd0,
                NORM_S_WAIT01   = 4'd1,
                NORM_S_PREP23   = 4'd2,
                NORM_S_WAIT23   = 4'd3,
                NORM_S_DENOM_SUB= 4'd4,
                NORM_S_WAIT_DEN = 4'd5,
                NORM_S_PIPE     = 4'd6,
                NORM_S_DONE     = 4'd7;     





    always @(posedge clk_flatten or negedge rst_n) begin
        if (!rst_n) begin
            for (p=0; p<8; p=p+1)
                flatten[p] <= 0;
        end 
        else if (state == ST_FC) begin
            if (fc_cnt == 3) begin
                flatten[0] <= a01_reg;
                flatten[1] <= a23_reg;
                flatten[2] <= a45_reg;
                flatten[3] <= a67_reg;
            end 
            // 第二張圖的資料在 Cycle 6 抵達
            else if (fc_cnt == 6) begin
                flatten[4] <= a01_reg;
                flatten[5] <= a23_reg;
                flatten[6] <= a45_reg;
                flatten[7] <= a67_reg;
            end
        end
        else if (state == ST_ACTV && actv_s == ACTV_S_DONE) begin
                flatten[actv_idx] <= shared_div_z;
            end
    end
    //-----------------------------------------------------
    // FC 控制流程（支援 cy0~cy6 節奏）
    //-----------------------------------------------------
    always @(posedge clk_fc or negedge rst_n) begin
        if (!rst_n) begin
            fc_cnt   <= 0;
            fc_round <= 0;
            fc_done  <= 0;
        end 
        else if (state == ST_FC) begin
            // --- cycle counter ---
            if (fc_cnt < 6)
                fc_cnt <= fc_cnt + 1;
            else
                fc_cnt <= fc_cnt;

            // --- round control ---
            case (fc_cnt)
                0: begin
                    fc_round <= 0;  // 第一張圖
                    fc_done  <= 0;
                end
                2: begin
                    fc_round <= 1;  // 第二張圖
                    fc_done  <= 0;
                end
                6: begin
                    fc_done <= 1;   // 第二張圖完成
                end
                default: begin
                    fc_done <= 0;
                end
            endcase
        end 
        else begin
            fc_cnt   <= 0;
            fc_round <= 0;
            fc_done  <= 0;
        end
    end



    //-----------------------------------------------------
    //  NORMALIZE INSTANCES
    //---------------------------------------------------


    wire [DATA_W-1:0] abs_out = {1'b0, shared_sub_z[DATA_W-2:0]};

    wire sub_en = (state == ST_ACTV) || (state == ST_NORM) || (state == ST_OUT);
    
    reg [DATA_W-1:0] sub_in_a_out, sub_in_b_out;
        
    wire [DATA_W-1:0] shared_sub_a, shared_sub_b;
    assign shared_sub_a = (!sub_en)          ? {DATA_W{1'b0}} :
                          (state == ST_ACTV) ? sub_in_a       : 
                          (state == ST_NORM) ? sub_in_al1     :
                                               sub_in_a_out;  

    assign shared_sub_b = (!sub_en)          ? {DATA_W{1'b0}} :
                          (state == ST_ACTV) ? sub_in_b       : 
                          (state == ST_NORM) ? sub_in_bl1     :
                                               sub_in_b_out;  



    DW_fp_sub #(SIG_W, EXP_W, 0) U1 ( 
        .a(shared_sub_a), 
        .b(shared_sub_b), 
        .rnd(3'b000),         
        .z(shared_sub_z), 
        .status()              
    );
   
    DW_fp_div #(SIG_W, EXP_W, 0) U8 ( 
        .a(shared_div_a), 
        .b(shared_div_b), 
        .rnd(3'b000),          
        .z(shared_div_z), 
        .status()             
    );

    reg [DATA_W-1:0] normalized [0:2*NUM_ELEM_PER_IMG-1];


    always @(posedge clk_norm or negedge rst_n) begin
        if (!rst_n) begin
            norm_s      <= NORM_S_SET01;
            norm_img_idx<= 0;
            elem_idx    <= 0;
            max_01 <= 0; min_01 <= 0; max_23 <= 0; min_23 <= 0;
            global_max <= 0; global_min <= 0;
            denom_reg <= 0; sub_reg <= 0;
            norm_done <= 1'b0;
            norm_div_a <= 0; norm_div_b <= 0;
        end
        else if (state == ST_NORM) begin
            case (norm_s)
                NORM_S_SET01: begin
                    cmp_a0_r <= flatten[norm_img_idx*4 + 0]; cmp_b0_r <= flatten[norm_img_idx*4 + 1];
                    cmp_a1_r <= flatten[norm_img_idx*4 + 2]; cmp_b1_r <= flatten[norm_img_idx*4 + 3];
                    norm_s   <= NORM_S_WAIT01;
                end
                NORM_S_WAIT01: begin
                    max_01 <= cmp0_unord ? cmp_a0_w : (cmp0_gt ? cmp_a0_w : cmp_b0_w);
                    min_01 <= cmp0_unord ? cmp_b0_w : (cmp0_gt ? cmp_b0_w : cmp_a0_w);
                    max_23 <= cmp1_unord ? cmp_a1_w : (cmp1_gt ? cmp_a1_w : cmp_b1_w);
                    min_23 <= cmp1_unord ? cmp_b1_w : (cmp1_gt ? cmp_b1_w : cmp_a1_w);
                    norm_s <= NORM_S_PREP23;
                end
                NORM_S_PREP23: begin
                    cmp_a0_r <= max_01; cmp_b0_r <= max_23;
                    cmp_a1_r <= min_01; cmp_b1_r <= min_23;
                    norm_s <= NORM_S_WAIT23;
                end
                NORM_S_WAIT23: begin
                    global_max <= (cmp0_gt) ? cmp_a0_w : cmp_b0_w;
                    global_min <= (cmp1_gt) ? cmp_b1_w : cmp_a1_w;
                    norm_s <= NORM_S_DENOM_SUB;
                end
                NORM_S_DENOM_SUB: begin
                    sub_in_al1 <= global_max; sub_in_bl1 <= global_min;
                    norm_s <= NORM_S_WAIT_DEN;
                end
                NORM_S_WAIT_DEN: begin
                    denom_reg <= shared_sub_z; elem_idx <= 0; 
                    norm_s <= NORM_S_PIPE;
                end
                NORM_S_PIPE: begin
                    if (do_div) begin
                        norm_div_a <= shared_sub_z;
                        norm_div_b <= denom_reg;
                    end else begin
                        norm_div_a <= 0; norm_div_b <= 0;
                    end
                    if (do_sub) begin
                        sub_in_al1 <= flatten[norm_img_idx*NUM_ELEM_PER_IMG + elem_idx];
                        sub_in_bl1 <= global_min;
                    end else begin
                        sub_in_al1 <= 0; sub_in_bl1 <= 0;
                    end

                    if (is_last) norm_s <= NORM_S_DONE;
                    else begin elem_idx <= elem_idx + 1; norm_s <= NORM_S_PIPE; end
                    
                    if (do_store) normalized[norm_img_idx*NUM_ELEM_PER_IMG + (elem_idx - 2)] <= shared_div_z;
                end
                NORM_S_DONE: begin
                    if (norm_img_idx == 0) begin
                        norm_img_idx <= 1; norm_s <= NORM_S_SET01;
                    end else begin
                        norm_done <= 1'b1; norm_img_idx <= 0; norm_s <= NORM_S_SET01;
                    end
                end
                default: norm_s <= NORM_S_SET01;
            endcase
        end
     
        else begin
            norm_s <= NORM_S_SET01;
            norm_done <= 1'b0;
 
            norm_img_idx <= 0; // 💡 補上：確保下一題從第 0 張圖開始
            elem_idx <= 0;     // 💡 補上：確保下一題從第 0 個像素開始
        end
        
    end

    // -------------------------
    // Activation FSM (per-element over 8 elements) sequencing shared units
    // Steps per element (sigmoid): exp(x) -> inv_exp = 1/exp -> denom = 1 + inv_exp -> out = 1/denom
    // Steps per element (tanh): exp(x) -> inv_exp = 1/exp -> num = exp - inv_exp -> den = exp + inv_exp -> out = num/den
    // We'll sequence safely using shared_div and shared_sub only when needed, with explicit WAIT states.
    // -------------------------


    DW_fp_exp #(SIG_W, EXP_W, 0, 0) U9 (
        .a(actv_tmp1),
        .z(exp_x),
        .status()         
    );




   

    always @(posedge clk_actv or negedge rst_n) begin
        if (!rst_n) begin
            actv_s <= ACTV_S_IDLE; actv_idx <= 0; actv_tmp1 <= 0;
            exp_x_reg <= 0; inv_exp_reg <= 0; add_out_reg <= 0; sub_out_reg <= 0; actv_done <= 1'b0;
            actv_div_a <= 0; actv_div_b <= 0;
        end else if (state == ST_ACTV) begin
            case (actv_s)
                ACTV_S_IDLE: begin actv_tmp1 <= normalized[actv_idx]; actv_done <= 1'b0; actv_s <= ACTV_S_EXP_START; end
                ACTV_S_EXP_START: actv_s <= ACTV_S_EXP_WAIT;
                ACTV_S_EXP_WAIT: begin
                    exp_x_reg <= exp_x; 
                    actv_div_a <= 32'h3f800000; actv_div_b <= exp_x;
                    actv_s <= ACTV_S_INV_LATCH;
                end
                ACTV_S_INV_LATCH: begin
                    act_a1 <= exp_x_reg; act_b1 <= shared_div_z;
                    act_a2 <= 32'h3f800000; act_b2 <= shared_div_z;
                    sub_in_a <= exp_x_reg; sub_in_b <= shared_div_z;
                    actv_s <= ACTV_S_POSTINV_PRE;
                end
                ACTV_S_POSTINV_PRE: begin
                    add_out_reg <= a01; add_out_reg2 <= a23; sub_out_reg <= shared_sub_z;
                    actv_s <= ACTV_S_FINAL_PREP;
                end
                ACTV_S_FINAL_PREP: begin
                    if (opt_reg[1] == 1'b0) begin
                        actv_div_a <= 32'h3f800000; actv_div_b <= add_out_reg2;
                    end else begin
                        actv_div_a <= sub_out_reg; actv_div_b <= add_out_reg;
                    end
                    actv_s <= ACTV_S_DONE;
                end
                ACTV_S_DONE: begin
                    if (actv_idx == 7) actv_done <= 1'b1;
                    else begin actv_idx <= actv_idx + 1; actv_s <= ACTV_S_IDLE; end
                end
                default: actv_s <= ACTV_S_IDLE;
            endcase
        end else begin
            actv_s <= ACTV_S_IDLE; actv_done <= 1'b0; actv_idx <= 0;
        end
    end 

    // =========================================================
    // L1 distance stage 
    // =========================================================

   

    always @(posedge clk_out or negedge rst_n) begin
        if (!rst_n) begin
            l1_stage <= 0; l1_idx <= 0; out <= 0; out_valid <= 0;
            sub_in_a_out <= 0; sub_in_b_out <= 0;
            for(p=0; p<4; p=p+1) l1_abs[p] <= 0;
        end 
        else if (state == ST_OUT) begin
            case (l1_stage)
                3'd0: begin sub_in_a_out <= flatten[l1_idx]; sub_in_b_out <= flatten[l1_idx + 4]; l1_stage <= 3'd1; end
                3'd1: begin
                    l1_abs[l1_idx] <= abs_out;
                    if (l1_idx == 3) l1_stage <= 3'd2;
                    else begin l1_idx <= l1_idx + 1; l1_stage <= 3'd0; end
                end
                3'd2: begin add_a <= l1_abs[0]; add_b <= l1_abs[1]; l1_stage <= 3'd3; end
                3'd3: begin add_a <= a45; add_b <= l1_abs[2]; l1_stage <= 3'd4; end
                3'd4: begin add_a <= a45; add_b <= l1_abs[3]; l1_stage <= 3'd5; end
                3'd5: begin out <= a45; out_valid <= 1'b1; l1_stage <= 3'd6; end
                3'd6: begin out_valid <= 1'b0; out <= 0; l1_stage <= 3'd0; l1_idx <= 0; end // 💡 確保拉低 valid 同時歸零 out
            endcase
        end 
        else begin
            out_valid <= 1'b0;
            out       <= 32'd0; 
            l1_stage  <= 0;
            l1_idx    <= 0;
        end
    end

    endmodule
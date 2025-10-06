`timescale 1ns/1ps
module SNN #(
    parameter IMG_W   = 4,
    parameter IMG_H   = 4,
    parameter CH      = 3,
    parameter DATA_W  = 32,
    parameter SIG_W   = 23,
    parameter EXP_W   = 8,
    // For combinational DW IP approach we set PIPE_LAT = 1 (effectively no extra DW pipeline).
    // If you later switch DW IP to pipelined mode, set this accordingly and adapt logic.
    parameter PIPE_LAT = 1
)(
    input                   clk,
    input                   rst_n,
    input                   in_valid,
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
    localparam PEND_DEPTH    = PIPE_LAT + 4;

    // -------------------------
    // FSM states (top-level simplified)
    // -------------------------
    localparam ST_IDLE = 3'd0,
               ST_RUN  = 3'd1, // receive & conv overlapped
               ST_POOL = 3'd2,
               ST_FC   = 3'd3,
               ST_NORM = 3'd4,
               ST_ACTV = 3'd5,
               ST_OUT  = 3'd6;

    reg [2:0] state, nstate;

    // -------------------------
    // Inputs reception
    // -------------------------
    reg [6:0] recv_count; // 0..95 global count of Img inputs received
    reg [15:0] in_cnt;
    reg [6:0] ker_ptr;
    reg [1:0] wt_ptr;
    reg        ker_loaded;
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

    // hist pipeline to align with sum_ch return
    reg [3:0] pos_hist [0:PIPE_LAT-1];
    reg [1:0] ch_hist  [0:PIPE_LAT-1];
    reg       img_hist [0:PIPE_LAT-1];

    // fire shift (align valid of adder-tree output)
    reg [PIPE_LAT-1:0] fire_shift;

    // win & ker registers (registered by sequential)
    reg [DATA_W-1:0] win_pix_reg [0:8];
    reg [DATA_W-1:0] ker_reg [0:8];
    reg ker_reg_valid;

    // combinational next values (from combinational window generator)
    reg [DATA_W-1:0] win_pix_next [0:8];
    reg [DATA_W-1:0] ker_next     [0:8];
    reg ker_valid_next;

    // mult drive arrays (combinational outputs to DW mult)
    reg [DATA_W-1:0] mult_a [0:8];
    reg [DATA_W-1:0] mult_b [0:8];

    // outputs of multipliers and adder tree (combinational)
    wire [DATA_W-1:0] prod [0:8];
    wire [DATA_W-1:0] a01,a23,a45,a67,a0123,a4567,tmp_all,sum_ch;

    // feature accumulator (final conv outputs sit here)
    reg [DATA_W-1:0] feat_acc [0:FEAT_SZ-1]; // 32 entries (img0:0..15, img1:16..31)

    // done masking to track per-pixel completion (per image)
    reg [CELLS_PER_IMG-1:0] done_mask0;
    reg [CELLS_PER_IMG-1:0] done_mask1;
    reg [1:0] proc_img_cnt; // 0..2

    // local variables for loops
    integer i, p;
// -------------------------
// DesignWare multiplier instances (combinational)
// NOTE: pipeline parameter set to 0 => combinational (depends on your DW version).
// Verify with DW manual and change param position/value if your vendor differs.
// -------------------------
genvar gi;
generate
    for (gi=0; gi<9; gi=gi+1) begin : MULTS
        DW_fp_mult #(SIG_W, EXP_W, 0) mult_i (
            .a(mult_a_reg[gi]),     // <<< 改成打一拍後的 mult_a_reg
            .b(mult_b_reg[gi]),     // <<< 改成打一拍後的 mult_b_reg
            .rnd(3'b000),
            .z(prod[gi]),
            .status()
        );
    end
endgenerate

// adder tree (combinational, Cycle 4)
DW_fp_add #(SIG_W, EXP_W, 0) add01(.a(prod[0]), .b(prod[1]), .rnd(3'b000), .z(a01), .status());
DW_fp_add #(SIG_W, EXP_W, 0) add23(.a(prod[2]), .b(prod[3]), .rnd(3'b000), .z(a23), .status());
DW_fp_add #(SIG_W, EXP_W, 0) add45(.a(prod[4]), .b(prod[5]), .rnd(3'b000), .z(a45), .status());
DW_fp_add #(SIG_W, EXP_W, 0) add67(.a(prod[6]), .b(prod[7]), .rnd(3'b000), .z(a67), .status());
DW_fp_add #(SIG_W, EXP_W, 0) add0123(.a(a01), .b(a23), .rnd(3'b000), .z(a0123), .status());
DW_fp_add #(SIG_W, EXP_W, 0) add4567(.a(a45), .b(a67), .rnd(3'b000), .z(a4567), .status());
DW_fp_add #(SIG_W, EXP_W, 0) add_all(.a(a0123), .b(a4567), .rnd(3'b000), .z(tmp_all), .status());
DW_fp_add #(SIG_W, EXP_W, 0) add_final(.a(tmp_all), .b(prod[8]), .rnd(3'b000), .z(sum_ch), .status());

// ---------------------------------------------------------
// combinational: compute win_addr_next and win_pad_flag_next
// ---------------------------------------------------------
reg [15:0] win_addr_next [0:8];
reg        win_pad_flag_next [0:8];
reg [DATA_W-1:0] win_pad_val_next [0:8];

always @(*) begin
    integer center_r, center_c;
    integer rr, cc, r, c;
    integer p;
    // default
    for (p=0; p<9; p=p+1) begin
        win_addr_next[p] = 16'd0;
        win_pad_flag_next[p] = 1'b0;
        win_pad_val_next[p] = {DATA_W{1'b0}};
    end

    if (/* state==ST_RUN && recv_count >= 16 */) begin
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
                // out of bounds -> padding case
                if (opt_reg[0] == 1'b1) begin
                    win_pad_flag_next[p] = 1'b1;
                    win_pad_val_next[p]  = {DATA_W{1'b0}}; // zero pad
                    win_addr_next[p] = 16'd0;
                end else begin
                    // replicate/clamp
                    integer rr_cl, cc_cl;
                    rr_cl = (r < 0) ? 0 : ((r >= IMG_H) ? IMG_H-1 : r);
                    cc_cl = (c < 0) ? 0 : ((c >= IMG_W) ? IMG_W-1 : c);
                    win_pad_flag_next[p] = 1'b0;
                    win_addr_next[p] = conv_img * IMG_MEM_SZ + conv_ch * CELLS_PER_IMG + rr_cl * IMG_W + cc_cl;
                end
            end else begin
                win_pad_flag_next[p] = 1'b0;
                win_addr_next[p] = conv_img * IMG_MEM_SZ + conv_ch * CELLS_PER_IMG + r * IMG_W + c;
            end
        end
    end
end

// ---------------------------------------------------------
// Cycle 1 → Cycle 2 : 寄存器對齊
// ---------------------------------------------------------
reg [15:0] win_addr_reg [0:8];
reg        win_pad_flag_reg [0:8];
reg [DATA_W-1:0] win_pad_val_reg [0:8];
reg addr_req_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (p=0; p<9; p=p+1) begin
            win_addr_reg[p]     <= 16'd0;
            win_pad_flag_reg[p] <= 1'b0;
            win_pad_val_reg[p]  <= {DATA_W{1'b0}};
        end
        addr_req_r <= 1'b0;
    end else begin
        if (prep_can_present) begin
            for (p=0; p<9; p=p+1) begin
                win_addr_reg[p]     <= win_addr_next[p];
                win_pad_flag_reg[p] <= win_pad_flag_next[p];
                win_pad_val_reg[p]  <= win_pad_val_next[p];
            end
        end
        addr_req_r <= prep_can_present;
    end
end

// ---------------------------------------------------------
// Cycle 2: 讀 BRAM → mult_a_reg / mult_b_reg
// ---------------------------------------------------------
reg [DATA_W-1:0] mult_a_reg [0:8];
reg [DATA_W-1:0] mult_b_reg [0:8];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (p=0; p<9; p=p+1) begin
            mult_a_reg[p] <= {DATA_W{1'b0}};
            mult_b_reg[p] <= {DATA_W{1'b0}};
        end
    end else if (addr_req_r) begin
        for (p=0; p<9; p=p+1) begin
            if (win_pad_flag_reg[p])
                mult_a_reg[p] <= win_pad_val_reg[p];
            else
                mult_a_reg[p] <= img_buf[ win_addr_reg[p] ]; // BRAM data valid
        end
        if (ker_reg_valid) begin
            for (p=0; p<9; p=p+1)
                mult_b_reg[p] <= ker_reg[p];
        end
    end
end

    // ==========================================================
    // Input reception & basic FSM next-state
    // ==========================================================
    // simple nextstate for top-level: allow ST_RUN when in_valid begins
    always @(*) begin
        nstate = state;
        case (state)
            ST_IDLE: if (in_valid) nstate = ST_RUN;
            ST_RUN: if (&done_mask0 && &done_mask1) nstate = ST_POOL;
            ST_POOL: nstate = ST_FC;
            ST_FC:   nstate = ST_NORM;
            ST_NORM: nstate = ST_ACTV;
            ST_ACTV: nstate = ST_OUT;
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
            ker_loaded <= 1'b0;
            opt_reg <= 2'b00;
            // clear img_buf & kernel & weight
            for (i=0; i<IMG_BUF_SZ; i=i+1) img_buf[i] <= {DATA_W{1'b0}};
            for (i=0; i<KERNEL_SZ; i=i+1) ker_buf[i] <= {DATA_W{1'b0}};
            for (i=0; i<4; i=i+1) weight_buf[i] <= {DATA_W{1'b0}};
        end else begin
            // latch opt on first valid if desired
            if (state == ST_RUN && in_valid) begin
                if (recv_count == 0) opt_reg <= Opt;
                // write image into img_buf contiguously: recv_count 0..95
                if (recv_count < IMG_BUF_SZ) begin
                    img_buf[recv_count] <= Img;
                    recv_count <= recv_count + 1;
                end

                // kernel loading (first 27 cycles)
                if (ker_ptr < KERNEL_SZ) begin
                    ker_buf[ker_ptr] <= Kernel;
                    if (ker_ptr == KERNEL_SZ - 1) ker_loaded <= 1'b1;
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
reg [DATA_W-1:0] prod_reg [0:8];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (p=0; p<9; p=p+1)
            prod_reg[p] <= {DATA_W{1'b0}};
    end else begin
        for (p=0; p<9; p=p+1)
            prod_reg[p] <= prod[p];  // 把 multiplier 結果打一拍
    end
end

   // ==========================================================
   // 控制邏輯 (FSM + iterators for convolution)
   // ==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conv_pos <= 0;
            conv_ch  <= 0;
            conv_img <= 0;
            fire_shift <= {PIPE_LAT{1'b0}};
            done_mask0 <= {CELLS_PER_IMG{1'b0}};
            done_mask1 <= {CELLS_PER_IMG{1'b0}};
            proc_img_cnt <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    conv_pos <= 0;
                    conv_ch  <= 0;
                    conv_img <= 0;
                    fire_shift <= {PIPE_LAT{1'b0}};
                end

                ST_RUN: begin
                    // only run pipeline if we've received enough data OR there are pending things
                    if (recv_count >= 16) begin
                        // advance pipeline shift register
                        fire_shift <= {fire_shift[PIPE_LAT-2:0], 1'b1};

                        // conv iterators update
                        if (conv_pos < CELLS_PER_IMG - 1) begin
                            conv_pos <= conv_pos + 1;
                        end else begin
                            conv_pos <= 0;
                            if (conv_ch < CH - 1) begin
                                conv_ch <= conv_ch + 1;
                            end else begin
                                conv_ch <= 0;
                                // move to second image processing only when we've received at least 48 pixels
                                if (conv_img == 0 && recv_count >= IMG_MEM_SZ)
                                    conv_img <= 1;
                            end
                        end
                    end else begin
                        fire_shift <= {PIPE_LAT{1'b0}};
                    end
                end

                default: begin
                    // leave iterators unchanged in other states
                end
            endcase
        end
    end

    // ==========================================================
    // 資料管線 (window/kernel latch + hist pipeline + direct accumulate)
    // ==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<PIPE_LAT; i=i+1) begin
                pos_hist[i] <= 0;
                ch_hist[i]  <= 0;
                img_hist[i] <= 0;
            end
            for (i=0; i<9; i=i+1) begin
                win_pix_reg[i] <= {DATA_W{1'b0}};
                ker_reg[i]     <= {DATA_W{1'b0}};
            end
            ker_reg_valid <= 1'b0;
            // clear feat_acc
            for (i=0;i<FEAT_SZ;i=i+1) feat_acc[i] <= {DATA_W{1'b0}};
            done_mask0 <= {CELLS_PER_IMG{1'b0}};
            done_mask1 <= {CELLS_PER_IMG{1'b0}};
            proc_img_cnt <= 0;
        end else begin
            if (state == ST_RUN && recv_count >= 16) begin
                // shift history
                for (i=PIPE_LAT-1; i>0; i=i-1) begin
                    pos_hist[i] <= pos_hist[i-1];
                    ch_hist[i]  <= ch_hist[i-1];
                    img_hist[i] <= img_hist[i-1];
                end
                pos_hist[0] <= conv_pos;
                ch_hist[0]  <= conv_ch;
                img_hist[0] <= conv_img;

                // latch window & kernel into registers (these become stable for combinational DW)
                for (i=0; i<9; i=i+1) begin
                    win_pix_reg[i] <= win_pix_next[i];
                    ker_reg[i]     <= ker_next[i];
                end
                ker_reg_valid <= ker_valid_next;
            end

            // when the adder-tree/combinational sum_ch aligns (fire_shift tail), directly accumulate
            if (fire_shift[PIPE_LAT-1]) begin
                integer hist_idx;
                hist_idx = img_hist[PIPE_LAT-1] * CELLS_PER_IMG + pos_hist[PIPE_LAT-1];
                // Direct accumulate: feat_acc[idx] <= feat_acc[idx] + sum_ch;
                // Note: using non-blocking <= to avoid race in sequential block
                feat_acc[ hist_idx ] <= feat_acc[ hist_idx ] + sum_ch;

                // if last channel for this pos, mark done mask
                if (ch_hist[PIPE_LAT-1] == (CH - 1)) begin
                    if (img_hist[PIPE_LAT-1] == 0) done_mask0[ pos_hist[PIPE_LAT-1] ] <= 1'b1;
                    else done_mask1[ pos_hist[PIPE_LAT-1] ] <= 1'b1;
                end

                // update proc_img_cnt when masks complete
                if (&done_mask0) proc_img_cnt <= (proc_img_cnt < 1) ? 1 : proc_img_cnt;
                if (&done_mask1) proc_img_cnt <= 2;
            end
        end
    end



 // -------------------------
// Pooling stage (all mux as wires, FSM only registers)
// -------------------------

reg [DATA_W-1:0] cmp_a_r, cmp_b_r, pool_tmp_r;
reg cmp_gt_r;
reg [1:0] pool_stage;
reg [1:0] pool_img, pool_r, pool_c;
reg pool_done;
reg [DATA_W-1:0] pool_out[0:POOL_OUT_SZ-1];

wire cmp_gt_w, cmp_eq_w, cmp_unord_w;

// DW_fp_cmp instance
DW_fp_cmp #(SIG_W, EXP_W) pool_cmp (
    .a(cmp_a_r),
    .b(cmp_b_r),
    .agtb(cmp_gt_w),
    .aeqb(cmp_eq_w),
    .altb(),
    .unordered(cmp_unord_w)
);

// -------------------------
// Address calculation (optimized)
// -------------------------
wire [15:0] base_addr = pool_img << LOG_CELLS_PER_IMG;

wire [15:0] addr00 = base_addr + ((pool_r << 1) << LOG_IMG_W) + (pool_c << 1);
wire [15:0] addr01 = addr00 + 1;
wire [15:0] addr10 = base_addr + ((pool_r << 1 + 1) << LOG_IMG_W) + (pool_c << 1);
wire [15:0] addr11 = addr10 + 1;

// -------------------------
// Mux / max selection (all combinational wires)
// -------------------------
wire [DATA_W-1:0] cmp0 = feat_acc[addr00];
wire [DATA_W-1:0] cmp1 = feat_acc[addr01];
wire [DATA_W-1:0] cmp2 = feat_acc[addr10];
wire [DATA_W-1:0] cmp3 = feat_acc[addr11];

// Stage 1: compare cmp0 vs cmp1
wire [DATA_W-1:0] max01 = cmp_unord_w ? cmp0 : (cmp_gt_w ? cmp0 : cmp1);
// Stage 2: compare max01 vs cmp2
wire [DATA_W-1:0] max012 = cmp_unord_w ? max01 : (cmp_gt_w ? max01 : cmp2);
// Stage 3: compare max012 vs cmp3
wire [DATA_W-1:0] max0123 = cmp_unord_w ? max012 : (cmp_gt_w ? max012 : cmp3);

// -------------------------
// FSM for register updates
// -------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pool_stage <= 0;
        pool_img   <= 0;
        pool_r     <= 0;
        pool_c     <= 0;
        pool_done  <= 1'b0;
        cmp_a_r   <= 0;
        cmp_b_r   <= 0;
        pool_tmp_r <= 0;
        cmp_gt_r  <= 0;
    end else if (state == ST_POOL) begin
        case(pool_stage)
            2'd0: begin
                cmp_a_r <= cmp0;
                cmp_b_r <= cmp1;
                pool_stage <= 1;
            end
            2'd1: begin
                cmp_a_r <= max01;
                cmp_b_r <= cmp2;
                pool_tmp_r <= max01;
                pool_stage <= 2;
            end
            2'd2: begin
                cmp_a_r <= max012;
                cmp_b_r <= cmp3;
                pool_tmp_r <= max012;
                pool_stage <= 3;
            end
            2'd3: begin
                pool_out[ pool_img*4 + pool_r*2 + pool_c ] <= max0123;
                pool_stage <= 0;
                // update indices
                if (pool_c < 1) pool_c <= pool_c + 1;
                else begin
                    pool_c <= 0;
                    if (pool_r < 1) pool_r <= pool_r + 1;
                    else begin
                        pool_r <= 0;
                        if (pool_img == 0) pool_img <= 1;
                        else pool_done <= 1'b1;
                    end
                end
            end
        endcase
    end
end
// -------------------------
// Fully-Connected stage (all mux/pipeline outside FSM)
// -------------------------
reg [1:0] fc_img;
reg [1:0] fc_out_idx;
reg [2:0] fc_mul_idx;
reg fc_done;
reg [DATA_W-1:0] flatten [0:NUM_IMG*FC_OUT_PER_IMG-1];

// Pipeline registers
reg [DATA_W-1:0] mac_a_r, mac_b_r, mac_prev_r;
reg [DATA_W-1:0] mac_mult_r, mac_add_r;

// Reuse prod[0] for multiply
wire [DATA_W-1:0] mac_mult_wire;
assign mac_mult_wire = prod[0];

// DW_fp_add output
wire [DATA_W-1:0] mac_add_wire;
DW_fp_add #(SIG_W, EXP_W, 1) mac_adder (
    .a(mac_prev_r),
    .b(mac_mult_r),
    .rnd(3'b000),
    .z(mac_add_wire),
    .status()
);

// -------------------------
// Index calculation (optimized)
// -------------------------
wire [2:0] base_idx = fc_img << 2; // *4
wire [2:0] pool_idx = base_idx + fc_mul_idx;
wire [2:0] flat_idx = base_idx + fc_out_idx;

// -------------------------
// FSM: only updates registers and indices
// -------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fc_img     <= 0;
        fc_out_idx <= 0;
        fc_mul_idx <= 0;
        fc_done    <= 1'b0;
        mac_a_r    <= 0;
        mac_b_r    <= 0;
        mac_prev_r <= 0;
        mac_mult_r <= 0;
        mac_add_r  <= 0;
        for (integer i=0;i<NUM_IMG*FC_OUT_PER_IMG;i=i+1)
            flatten[i] <= 0;
    end else if (state == ST_FC) begin
        // Latch multiply inputs
        mac_a_r    <= pool_out[pool_idx];
        mac_b_r    <= weight_buf[fc_mul_idx];
        mac_prev_r <= (fc_mul_idx==0) ? 0 : mac_add_r;

        // Pipeline multiply
        mac_mult_r <= mac_mult_wire;

        // Pipeline add
        mac_add_r  <= mac_add_wire;

        // Update indices
        if (fc_mul_idx == FC_WEIGHT_SZ-1) begin
            flatten[flat_idx] <= mac_add_r; // store result after last weight
            fc_mul_idx <= 0;

            if (fc_out_idx == FC_OUT_PER_IMG-1) begin
                fc_out_idx <= 0;
                if (fc_img == NUM_IMG-1) fc_done <= 1'b1;
                else fc_img <= fc_img + 1;
            end else fc_out_idx <= fc_out_idx + 1;

        end else fc_mul_idx <= fc_mul_idx + 1;

    end else begin
        // Reset FSM internal counters when not in ST_FC
        fc_img     <= 0;
        fc_out_idx <= 0;
        fc_mul_idx <= 0;
        fc_done    <= 1'b0;
        mac_a_r    <= 0;
        mac_b_r    <= 0;
        mac_prev_r <= 0;
        mac_mult_r <= 0;
        mac_add_r  <= 0;
    end
end

    // -------------------------
    // Shared subtract and divide (single instances)
    // -------------------------
    reg [DATA_W-1:0] shared_sub_a, shared_sub_b;
    wire [DATA_W-1:0] shared_sub_z;
    reg [DATA_W-1:0] shared_div_a, shared_div_b;
    wire [DATA_W-1:0] shared_div_z;

    // instantiate shared units (combinational designware) - treat as zero-latency combinational
    DW_fp_sub #(SIG_W,EXP_W,1) shared_sub_inst (.a(shared_sub_a), .b(shared_sub_b), .z(shared_sub_z), .rnd(3'b000), .status());
    DW_fp_div #(SIG_W,EXP_W,1) shared_div_inst (.a(shared_div_a), .b(shared_div_b), .z(shared_div_z), .rnd(3'b000), .status());

    // -------------------------
    // Normalization FSM (multi-cycle, per-element)
    // Steps per element: 1) compute denom = max - min (once per image)  2) for each element: sub = elem - min -> div = sub / denom -> store
    // We'll sequence: STATE_PRE, STATE_DENOM_SUB, WAIT_DENOM, STATE_NORMALIZE_SUB, WAIT_SUB, STATE_NORMALIZE_DIV, WAIT_DIV, NEXT_ELEMENT
    // -------------------------

    localparam NORM_S_PRE      = 4'd0,
               NORM_S_DEN_SUB = 4'd1,
               NORM_S_DEN_WAIT= 4'd2,
               NORM_S_ELEM_SUB= 4'd3,
               NORM_S_ELEM_WAIT=4'd4,
               NORM_S_ELEM_DIV= 4'd5,
               NORM_S_ELEM_DIV_WAIT=4'd6,
               NORM_S_DONE    = 4'd7;

    reg [3:0] norm_s;
    reg [1:0] norm_img_idx; // 0 or 1
    reg [1:0] norm_elem_idx; // 0..3 within image
    reg [DATA_W-1:0] denom_reg; // max - min

    // tmp regs for comparator usage (we keep original comparator for max/min selection)
    reg [DATA_W-1:0] tmp_max01, tmp_min01, tmp_max23, tmp_min23;
    reg [DATA_W-1:0] min_val, max_val;

    // comparator wires (reused)
    reg [DATA_W-1:0] cmp_a, cmp_b;
    wire cmp_gt_local, cmp_eq_local, cmp_unordered_local;
    DW_fp_cmp #(SIG_W, EXP_W) norm_cmp (.a(cmp_a), .b(cmp_b), .agtb(cmp_gt_local), .aeqb(cmp_eq_local), .altb(), .unordered(cmp_unordered_local));

    // normalized storage
    reg [DATA_W-1:0] normalized [0:7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            norm_s <= NORM_S_PRE;
            norm_img_idx <= 0;
            norm_elem_idx <= 0;
            tmp_max01 <= {DATA_W{1'b0}}; tmp_min01 <= {DATA_W{1'b0}};
            tmp_max23 <= {DATA_W{1'b0}}; tmp_min23 <= {DATA_W{1'b0}};
            min_val <= {DATA_W{1'b0}}; max_val <= {DATA_W{1'b0}};
            denom_reg <= {DATA_W{1'b0}};
            norm_done <= 1'b0;
        end else if (state == ST_NORM) begin
            case (norm_s)
                NORM_S_PRE: begin
                    // start computing max/min for this image
                    // compare flatten[0] vs flatten[1]
                    cmp_a <= flatten[norm_img_idx*4 + 0];
                    cmp_b <= flatten[norm_img_idx*4 + 1];
                    norm_s <= NORM_S_DEN_SUB; // use next state to latch results via comparator output
                end
                NORM_S_DEN_SUB: begin
                    // latch based on comparator
                    if (cmp_gt_local) begin tmp_max01 <= cmp_a; tmp_min01 <= cmp_b; end
                    else begin tmp_max01 <= cmp_b; tmp_min01 <= cmp_a; end
                    // compare 2 vs 3
                    cmp_a <= flatten[norm_img_idx*4 + 2];
                    cmp_b <= flatten[norm_img_idx*4 + 3];
                    norm_s <= NORM_S_DEN_WAIT;
                end
                NORM_S_DEN_WAIT: begin
                    if (cmp_gt_local) begin tmp_max23 <= cmp_a; tmp_min23 <= cmp_b; end
                    else begin tmp_max23 <= cmp_b; tmp_min23 <= cmp_a; end
                    // final max/min
                    if (tmp_max01 > tmp_max23) max_val <= tmp_max01; else max_val <= tmp_max23;
                    if (tmp_min01 < tmp_min23) min_val <= tmp_min01; else min_val <= tmp_min23;
                    // now compute denom = max - min using shared_sub
                    shared_sub_a <= max_val;
                    shared_sub_b <= min_val;
                    norm_s <= NORM_S_ELEM_SUB; // wait one cycle to capture denom
                end
                NORM_S_ELEM_SUB: begin
                    denom_reg <= shared_sub_z; // denom ready
                    // if denom == 0 we will set normalized elements to 0
                    norm_elem_idx <= 0;
                    norm_s <= NORM_S_ELEM_WAIT;
                end
                NORM_S_ELEM_WAIT: begin
                    // start element subtraction: elem - min
                    shared_sub_a <= flatten[norm_img_idx*4 + norm_elem_idx];
                    shared_sub_b <= min_val;
                    norm_s <= NORM_S_ELEM_DIV;
                end
                NORM_S_ELEM_DIV: begin
                    // capture subtraction result then setup division
                    reg [DATA_W-1:0] sub_res;
                    sub_res <= shared_sub_z;
                    // if denom_reg == 0 -> normalized = 0
                    if (denom_reg == {DATA_W{1'b0}}) begin
                        normalized[norm_img_idx*4 + norm_elem_idx] <= {DATA_W{1'b0}};
                        // advance
                        if (norm_elem_idx == 2'd3) begin
                            if (norm_img_idx == 1) begin
                                norm_s <= NORM_S_DONE;
                            end else begin
                                norm_img_idx <= 1;
                                norm_s <= NORM_S_PRE;
                            end
                        end else begin
                            norm_elem_idx <= norm_elem_idx + 1;
                            norm_s <= NORM_S_ELEM_WAIT;
                        end
                    end else begin
                        shared_div_a <= shared_sub_z; // sub_res
                        shared_div_b <= denom_reg;
                        norm_s <= NORM_S_ELEM_DIV_WAIT;
                    end
                end
                NORM_S_ELEM_DIV_WAIT: begin
                    // capture division result and write into normalized
                    normalized[norm_img_idx*4 + norm_elem_idx] <= shared_div_z;
                    // advance element
                    if (norm_elem_idx == 2'd3) begin
                        if (norm_img_idx == 1) begin
                            norm_s <= NORM_S_DONE;
                        end else begin
                            norm_img_idx <= 1;
                            norm_s <= NORM_S_PRE;
                        end
                    end else begin
                        norm_elem_idx <= norm_elem_idx + 1;
                        norm_s <= NORM_S_ELEM_WAIT;
                    end
                end
                NORM_S_DONE: begin
                    norm_done <= 1'b1;
                    norm_s <= NORM_S_DONE;
                end
                default: norm_s <= NORM_S_PRE;
            endcase
        end else begin
            // reset when not in ST_NORM
            norm_s <= NORM_S_PRE;
            norm_img_idx <= 0;
            norm_elem_idx <= 0;
            norm_done <= 1'b0;
        end
    end

    // -------------------------
    // Activation FSM (per-element over 8 elements) sequencing shared units
    // Steps per element (sigmoid): exp(x) -> inv_exp = 1/exp -> denom = 1 + inv_exp -> out = 1/denom
    // Steps per element (tanh): exp(x) -> inv_exp = 1/exp -> num = exp - inv_exp -> den = exp + inv_exp -> out = num/den
    // We'll sequence safely using shared_div and shared_sub only when needed, with explicit WAIT states.
    // -------------------------

    localparam ACTV_S_IDLE      = 4'd0,
               ACTV_S_EXP      = 4'd1,
               ACTV_S_EXP_WAIT = 4'd2,
               ACTV_S_INV_DIV  = 4'd3,
               ACTV_S_INV_WAIT = 4'd4,
               ACTV_S_FINAL_PRE= 4'd5,
               ACTV_S_FINAL_DIV= 4'd6,
               ACTV_S_FINAL_WAIT=4'd7,
               ACTV_S_DONE     = 4'd8;

    reg [3:0] actv_s;
    reg [3:0] actv_idx;
    reg [DATA_W-1:0] exp_x_reg;
    reg [DATA_W-1:0] inv_exp_reg;
    reg [DATA_W-1:0] actv_tmp1;
    reg [DATA_W-1:0] actv_tmp2;

    // instantiate exp (combinational) - as before
    wire [DATA_W-1:0] exp_x;
    DW_fp_exp #(SIG_W,EXP_W) exp_inst (.a(actv_tmp1), .z(exp_x), .status());

    // helper add instance for denom in sigmoid or denom in tanh (local adds)
    wire [DATA_W-1:0] local_add_out;
    reg  [DATA_W-1:0] local_add_a, local_add_b;
    DW_fp_add #(SIG_W,EXP_W,1) local_add_inst (.a(local_add_a), .b(local_add_b), .z(local_add_out), .rnd(3'b000), .status());

    reg actv_done_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            actv_s <= ACTV_S_IDLE;
            actv_idx <= 0;
            actv_done <= 1'b0;
            actv_tmp1 <= {DATA_W{1'b0}};
            exp_x_reg <= {DATA_W{1'b0}};
            inv_exp_reg <= {DATA_W{1'b0}};
        end else if (state == ST_ACTV) begin
            case (actv_s)
                ACTV_S_IDLE: begin
                    actv_idx <= 0;
                    actv_s <= ACTV_S_EXP;
                    actv_tmp1 <= normalized[0]; // feed first element
                end
                ACTV_S_EXP: begin
                    // start exp on actv_tmp1
                    // exp_inst is combinational -> capture next cycle
                    actv_s <= ACTV_S_EXP_WAIT;
                end
                ACTV_S_EXP_WAIT: begin
                    exp_x_reg <= exp_x; // capture exp(x)
                    // compute inv_exp = 1/exp_x using shared_div
                    shared_div_a <= 32'h3f800000; // 1.0
                    shared_div_b <= exp_x;        // combinational exp_x (captured previous cycle)
                    actv_s <= ACTV_S_INV_DIV;
                end
                ACTV_S_INV_DIV: begin
                    inv_exp_reg <= shared_div_z; // 1/exp_x
                    if (opt_reg[1] == 1'b0) begin
                        // sigmoid: denom = 1 + inv_exp -> final = 1 / denom
                        local_add_a <= 32'h3f800000;
                        local_add_b <= shared_div_z; // inv_exp
                        actv_s <= ACTV_S_FINAL_PRE;
                    end else begin
                        // tanh: num = exp - inv_exp -> use shared_sub for num
                        shared_sub_a <= exp_x_reg;
                        shared_sub_b <= inv_exp_reg;
                        actv_s <= ACTV_S_FINAL_PRE;
                    end
                end
                ACTV_S_FINAL_PRE: begin
                    if (opt_reg[1] == 1'b0) begin
                        // sigmoid path: now compute denom via local_add_out (combinational) and then final div
                        // local_add_out valid this cycle
                        shared_div_a <= 32'h3f800000; // 1.0
                        shared_div_b <= local_add_out; // denom
                        actv_s <= ACTV_S_FINAL_DIV;
                    end else begin
                        // tanh path: we captured numerator via shared_sub_z? Wait: shared_sub was assigned previous, take result
                        actv_tmp1 <= shared_sub_z; // numerator
                        // compute denom = exp + inv_exp (local add)
                        local_add_a <= exp_x_reg;
                        local_add_b <= inv_exp_reg;
                        actv_s <= ACTV_S_FINAL_DIV;
                    end
                end
                ACTV_S_FINAL_DIV: begin
                    if (opt_reg[1] == 1'b0) begin
                        // sigmoid final result in shared_div_z
                        flatten[actv_idx] <= shared_div_z;
                    end else begin
                        // tanh: divide numerator (actv_tmp1) by denom (local_add_out)
                        shared_div_a <= actv_tmp1;
                        shared_div_b <= local_add_out;
                        // capture next cycle
                        flatten[actv_idx] <= shared_div_z;
                    end
                    // advance to next element
                    if (actv_idx == 7) begin
                        actv_s <= ACTV_S_DONE;
                    end else begin
                        actv_idx <= actv_idx + 1;
                        // setup next element input
                        actv_tmp1 <= normalized[actv_idx+1];
                        actv_s <= ACTV_S_EXP;
                    end
                end
                ACTV_S_DONE: begin
                    actv_done <= 1'b1;
                    actv_s <= ACTV_S_DONE;
                end
                default: actv_s <= ACTV_S_IDLE;
            endcase
        end else begin
            actv_s <= ACTV_S_IDLE;
            actv_done <= 1'b0;
        end
    end

// -------------------------
// L1 distance FSM (shared sub, dedicated acc adder)
// -------------------------
reg [1:0]        l1_stage;
reg [2:0]        l1_idx;
reg [DATA_W-1:0] l1_acc;
reg              l1_busy;

reg [DATA_W-1:0] sub_in_a, sub_in_b;
wire [DATA_W-1:0] sub_out;

DW_fp_sub #(SIG_W, EXP_W, 1) shared_sub (
    .a(sub_in_a),
    .b(sub_in_b),
    .rnd(3'b000),
    .z(sub_out),
    .status()
);

wire [DATA_W-1:0] acc_sum;
DW_fp_add #(SIG_W, EXP_W, 1) acc_adder (
    .a(l1_acc),
    .b(l1_abs),
    .rnd(3'b000),
    .z(acc_sum),
    .status()
);

reg [DATA_W-1:0] l1_abs;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        l1_stage <= 0;
        l1_idx   <= 0;
        l1_acc   <= 0;
        l1_busy  <= 0;
        out_valid <= 0;
        out      <= 0;
    end else if (state == ST_OUT) begin
        if (!l1_busy) begin
            l1_busy  <= 1;
            l1_stage <= 0;
            l1_idx   <= 0;
            l1_acc   <= 0;
            out_valid <= 0;
        end else begin
            case (l1_stage)
                2'd0: begin
                    // 送入 shared_sub
                    sub_in_a <= flatten[l1_idx];
                    sub_in_b <= flatten[l1_idx+4];
                    l1_stage <= 2'd1;
                end
                2'd1: begin
                    // 絕對值
                    if (sub_out[DATA_W-1])
                        l1_abs <= {1'b0, (~sub_out[DATA_W-2:0])} + 1'b1;
                    else
                        l1_abs <= sub_out;
                    l1_stage <= 2'd2;
                end
                2'd2: begin
                    // 累加
                    l1_acc <= acc_sum;
                    if (l1_idx == 3) begin
                        out_valid <= 1;
                        out <= acc_sum;
                        l1_busy <= 0;
                    end else begin
                        l1_idx   <= l1_idx + 1;
                        l1_stage <= 0;
                    end
                end
            endcase
        end
    end else begin
        out_valid <= 0;
    end
end

endmodule
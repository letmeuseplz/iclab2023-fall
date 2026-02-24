//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2023 Fall
//   Lab04 Exercise		: Siamese Neural Network 
//   Author     		: 郭芮州
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : SNN.v
//   Module Name : SNN
//   Release version : V1.0 (Release Date: 2026-02)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################
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
    localparam NUM_ELEM_PER_IMG = 4;


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

    // -------------------------
    // Inputs reception
    // -------------------------
    reg [6:0] recv_count; // 0..95 global count of Img inputs received
  
    reg [6:0] ker_ptr;
    reg [1:0] wt_ptr;
  
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
    reg idx_hist[0:7];
    reg img_hist[0:7];
    assign gflag_all = (cnt_img0 == 48)& (cnt_img1 == 48);
    reg cnt_img0,cnt_img1;
    reg [1:0] ch_hist [0:PIPE_LAT-1];
    integer m;

`timescale 1ns/1ps

// ============================================================
// HT_TOP : Lab06 Huffman Top Design (FINAL DEMO-PASS VERSION)
// - Strict Verilog-2001 compliant (NO SystemVerilog syntax)
// - Deterministic FSM
// - Cycle-accurate DFS stack
// ============================================================
module HT_TOP #(
    parameter IP_WIDTH = 8,          // A,B,C,E,I,L,O,V
    parameter W_W      = 5,
    parameter ID_W     = 4,
    parameter MAX_NODE = 16
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            in_valid,
    input  wire [W_W-1:0]  in_weight,
    input  wire            out_mode,
    output reg             out_valid,
    output reg             out_code
);

// ============================================================
// FSM state encoding
// ============================================================
localparam S_IDLE      = 4'd0;
localparam S_IN        = 4'd1;
localparam S_SORT      = 4'd2;
localparam S_PICK      = 4'd3;
localparam S_UPDATE    = 4'd4;
localparam S_DFS_INIT  = 4'd5;
localparam S_DFS_RUN   = 4'd6;
localparam S_PREP_OUT  = 4'd7;
localparam S_OUT       = 4'd8;

reg [3:0] state, next_state;

// ============================================================
// Node storage
// ============================================================
reg [W_W-1:0]  node_w [0:MAX_NODE-1];
reg            node_v [0:MAX_NODE-1];
reg [ID_W-1:0] node_l [0:MAX_NODE-1];
reg [ID_W-1:0] node_r [0:MAX_NODE-1];

reg [ID_W-1:0] next_node;
reg [ID_W-1:0] active_cnt;

// ============================================================
// SORT IP interface
// ============================================================
reg  [IP_WIDTH*ID_W-1:0] si_char;
reg  [IP_WIDTH*W_W-1:0]  si_weight;
wire [IP_WIDTH*ID_W-1:0] so_char;

SORT_IP #(.IP_WIDTH(IP_WIDTH)) u_sort (
    .IN_character (si_char),
    .IN_weight    (si_weight),
    .OUT_character(so_char)
);

// ============================================================
// SORT input packing (Verilog-2001 compliant)
// ============================================================
integer i;
always @(*) begin
    for (i = 0; i < IP_WIDTH; i = i + 1) begin
        si_char[
            (IP_WIDTH-i)*ID_W-1 :
            (IP_WIDTH-1-i)*ID_W
        ] = i[ID_W-1:0];

        si_weight[
            (IP_WIDTH-i)*W_W-1 :
            (IP_WIDTH-1-i)*W_W
        ] = node_v[i] ? node_w[i] : {W_W{1'b1}};
    end
end

// ============================================================
// FSM next-state logic
// ============================================================
always @(*) begin
    next_state = state;
    case (state)
        S_IDLE     : if (in_valid)        next_state = S_IN;
        S_IN       : if (!in_valid)       next_state = S_SORT;
        S_SORT     :                      next_state = S_PICK;
        S_PICK     :                      next_state = S_UPDATE;
        S_UPDATE   : if (active_cnt > 1)  next_state = S_SORT;
                     else                 next_state = S_DFS_INIT;
        S_DFS_INIT :                      next_state = S_DFS_RUN;
        S_DFS_RUN  : if (sp == 0)          next_state = S_PREP_OUT;
        S_PREP_OUT :                      next_state = S_OUT;
        S_OUT      : if (out_done)         next_state = S_IDLE;
        default    :                      next_state = S_IDLE;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else        state <= next_state;
end

// ============================================================
// Input stage
// ============================================================
reg [3:0] in_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_cnt <= 0;
        for (i = 0; i < MAX_NODE; i = i + 1) begin
            node_v[i] <= 1'b0;
            node_w[i] <= {W_W{1'b0}};
        end
    end
    else if (state == S_IN && in_valid) begin
        node_w[in_cnt] <= in_weight;
        node_v[in_cnt] <= 1'b1;
        in_cnt <= in_cnt + 1'b1;
    end
    else if (state == S_IDLE) begin
        in_cnt     <= 0;
        next_node  <= IP_WIDTH;
        active_cnt <= IP_WIDTH;
    end
end

// ============================================================
// Pick smallest two nodes (Verilog-2001 slice)
// ============================================================
reg [ID_W-1:0] p0, p1;
always @(posedge clk) begin
    if (state == S_PICK) begin
        p0 <= so_char[
                IP_WIDTH*ID_W-1 :
                IP_WIDTH*ID_W-ID_W
              ];
        p1 <= so_char[
                IP_WIDTH*ID_W-ID_W-1 : 
                IP_WIDTH*ID_W-2*ID_W
              ];
    end
end
always @(posedge clk) begin
    if (state == S_UPDATE) begin
        // deactivate merged nodes
        node_v[p0] <= 1'b0;
        node_v[p1] <= 1'b0;

        // activate new node
        node_v[next_node] <= 1'b1;
        node_w[next_node] <= node_w[p0] + node_w[p1];

        // ------------------------------------------------
        // left / right decision (weight first, then ID)
        // ------------------------------------------------
        if (node_w[p0] < node_w[p1]) begin
            node_l[next_node] <= p0;
            node_r[next_node] <= p1;
        end
        else if (node_w[p0] > node_w[p1]) begin
            node_l[next_node] <= p1;
            node_r[next_node] <= p0;
        end
        else begin
            // tie-break: smaller ID on left
            if (p0 < p1) begin
                node_l[next_node] <= p0;
                node_r[next_node] <= p1;
            end
            else begin
                node_l[next_node] <= p1;
                node_r[next_node] <= p0;
            end
        end

        next_node  <= next_node + 1'b1;
        active_cnt <= active_cnt - 1'b1;
    end
end


// ============================================================
// DFS stack (cycle-accurate)
// ============================================================
reg [ID_W-1:0] stack_node [0:MAX_NODE-1];
reg [7:0]      stack_code [0:MAX_NODE-1];
reg [3:0]      sp;

reg [7:0] code_table [0:IP_WIDTH-1];
reg [3:0] code_len   [0:IP_WIDTH-1];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sp <= 0;
    end
    else if (state == S_DFS_INIT) begin
        sp <= 1;
        stack_node[0] <= next_node - 1'b1;
        stack_code[0] <= 8'b0;
    end
    else if (state == S_DFS_RUN && sp != 0) begin
        sp <= sp - 1'b1;
        if (stack_node[sp-1] < IP_WIDTH) begin
            code_table[stack_node[sp-1]] <= stack_code[sp-1];
            code_len  [stack_node[sp-1]] <= sp - 1'b1;
        end
        else begin
            stack_node[sp]   <= node_l[stack_node[sp-1]];
            stack_code[sp]   <= {stack_code[sp-1], 1'b0};
            stack_node[sp+1] <= node_r[stack_node[sp-1]];
            stack_code[sp+1] <= {stack_code[sp-1], 1'b1};
            sp <= sp + 2'b10;
        end
    end
end

// ============================================================
// Output preparation (ILOVE / ICLAB)
// ============================================================
reg [31:0] out_buf;
reg [5:0]  out_len;
reg [5:0]  out_idx;
reg        out_done;

localparam A = 0, B = 1, C = 2, E = 3, I = 4, L = 5, O = 6, V = 7;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_buf <= 32'b0;
        out_len <= 6'b0;
    end
    else if (state == S_PREP_OUT) begin
        out_buf <= 32'b0;
        out_len <= 6'b0;
        if (!out_mode) begin
            out_buf <= { code_table[I], code_table[L], code_table[O], code_table[V], code_table[E] };
            out_len <= code_len[I] + code_len[L] + code_len[O] + code_len[V] + code_len[E];
        end
        else begin
            out_buf <= { code_table[I], code_table[C], code_table[L], code_table[A], code_table[B] };
            out_len <= code_len[I] + code_len[C] + code_len[L] + code_len[A] + code_len[B];
        end
    end
end

// ============================================================
// Serial output stage
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_valid <= 1'b0;
        out_code  <= 1'b0;
        out_idx   <= 6'b0;
        out_done  <= 1'b0;
    end
    else if (state == S_OUT) begin
        out_valid <= 1'b1;
        out_code  <= out_buf[out_len-1-out_idx];
        out_idx   <= out_idx + 1'b1;
        if (out_idx == out_len-1) begin
            out_done  <= 1'b1;
            out_valid <= 1'b0;
        end
    end
    else begin
        out_valid <= 1'b0;
        out_idx   <= 6'b0;
        out_done  <= 1'b0;
    end
end

endmodule

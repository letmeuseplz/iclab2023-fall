`timescale 1ns/1ps
// ============================================================================
// Huffman Tree Top Module (merged + corrected DFS)
// ============================================================================
module HT_TOP #(
    parameter IP_WIDTH = 8,
    parameter W_W      = 7,
    parameter ID_W     = 4,
    parameter MAX_NODE = 15
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            in_valid,
    input  wire [2:0]  in_weight,
    input  wire            out_mode,
    output reg             out_valid,
    output reg           out_code
);

// ============================================================================
// FSM
// ============================================================================
localparam S_IDLE     = 4'd0,
           S_IN       = 4'd1,
           S_SORT     = 4'd2,
           S_PICK     = 4'd3,
           S_UPDATE   = 4'd4,
           S_DFS_INIT = 4'd5,
           S_DFS_RUN  = 4'd6,
           S_PREP_OUT = 4'd7,
           S_OUT      = 4'd8;

reg [3:0] state, next_state;

// ============================================================================
// Huffman nodes
// ============================================================================
reg [W_W:0]  node_w     [0:MAX_NODE-1];
reg            node_valid [0:MAX_NODE-1];
reg [ID_W-1:0] node_l     [0:MAX_NODE-1];
reg [ID_W-1:0] node_r     [0:MAX_NODE-1];

reg [ID_W-1:0] next_node;
reg [ID_W-1:0] active_cnt;

wire dfs_done;
assign dfs_done = (state == S_DFS_RUN) &&
                  dfs_pop &&
                  dfs_leaf &&
                  (sp == 1);

// ============================================================================
// SORT IP interface
// ============================================================================
reg  [MAX_NODE*ID_W-1:0] si_char;
reg  [MAX_NODE*W_W-1:0]  si_weight;
wire [MAX_NODE*ID_W-1:0] so_char;

SORT_IP #(
    .IP_WIDTH (MAX_NODE),
    .WEIGHT_W (W_W)
) u_sort (
    .IN_character (si_char),
    .IN_weight    (si_weight),
    .OUT_character(so_char)
);


integer i;
always @(*) begin
    for (i = 0; i < MAX_NODE; i = i + 1) begin
        si_char[(MAX_NODE-1-i)*ID_W +: ID_W] = i[ID_W-1:0];
        if (i < next_node && node_valid[i])
            si_weight[(MAX_NODE-1-i)*W_W +: W_W] = node_w[i];
        else
            si_weight[(MAX_NODE-1-i)*W_W +: W_W] = {W_W{1'b1}};
    end
end

// ============================================================================
// FSM next state
// ============================================================================
always @(*) begin
    next_state = state;
    case (state)
        S_IDLE     : if (in_valid)       next_state = S_IN;
        S_IN       : if (!in_valid)      next_state = S_SORT;
        S_SORT     :                     next_state = S_PICK;
        S_PICK     :                     next_state = S_UPDATE;
        S_UPDATE   : if (active_cnt > 1) next_state = S_SORT;
                     else                next_state = S_DFS_INIT;
        S_DFS_INIT :                     next_state = S_DFS_RUN;
        S_DFS_RUN  : if (dfs_done)         next_state = S_PREP_OUT;
        S_PREP_OUT :                     next_state = S_OUT;
        S_OUT      : if (out_done)        next_state = S_IDLE;
    endcase
end

always @(posedge clk or negedge rst_n)
    if (!rst_n) state <= S_IDLE;
    else        state <= next_state;
// ============================================================================
// Input
// ============================================================================
reg [3:0] in_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_cnt <= 0;
        next_node <= 0;
        active_cnt <= 0;
        for (i = 0; i < MAX_NODE; i = i + 1) begin
            node_valid[i] <= 0;
            node_w[i] <= 0;
            node_l[i] <= {ID_W{1'b0}};
            node_r[i] <= {ID_W{1'b0}};
        end
    end
    else if (in_valid) begin
        node_w[in_cnt] <= in_weight;
        node_valid[in_cnt] <= 1'b1;
        in_cnt <= in_cnt + 1'b1;
    end
    else if (state == S_IDLE) begin
        for (i = 0; i < MAX_NODE; i = i + 1) begin
            node_valid[i] <= 0;
            node_w[i] <= 0;
            node_l[i] <= {ID_W{1'b0}};
            node_r[i] <= {ID_W{1'b0}};
        end
        in_cnt <= 0;
        next_node <= IP_WIDTH;
        active_cnt <= IP_WIDTH;
    end
end

// ============================================================================
// Pick smallest two
// ============================================================================
reg [ID_W-1:0] p0, p1;
always @(posedge clk)
    if (state == S_PICK) begin
        p0 <= so_char[ID_W-1:0];
        p1 <= so_char[2*ID_W-1:ID_W];
    
    end

wire p0_is_left =
    (node_w[p0] > node_w[p1]) ||
    ((node_w[p0] == node_w[p1]) && (p0 < p1));

// ============================================================================
// Merge
// ============================================================================
always @(posedge clk)
    if (state == S_UPDATE) begin
        node_valid[p0] <= 1'b0;
        node_valid[p1] <= 1'b0;

        node_valid[next_node] <= 1'b1;
        node_w[next_node] <= node_w[p0] + node_w[p1];

        if (p0_is_left) begin
            node_l[next_node] <= p0;
            node_r[next_node] <= p1;
        end else begin
            node_l[next_node] <= p1;
            node_r[next_node] <= p0;
        end
        if(next_node < MAX_NODE) begin
            next_node <= next_node + 1'b1;
        end
        active_cnt <= active_cnt - 1'b1;
    end


// ============================================================
// DFS stack
// ============================================================
reg [ID_W-1:0] stack_node  [0:MAX_NODE-1];
reg [7:0]      stack_code  [0:MAX_NODE-1];
reg [3:0]      stack_depth [0:MAX_NODE-1];
reg [3:0]      sp;

reg [7:0] code_table [0:IP_WIDTH-1];
reg [3:0] code_len   [0:IP_WIDTH-1];

// ---------- DFS comb ----------
reg [3:0]      sp_next;
reg            dfs_pop;
reg            dfs_push;
reg            dfs_leaf;

reg [ID_W-1:0] cur_node;
reg [7:0]      cur_code;
reg [3:0]      cur_depth;

always @(*) begin
    // defaults
    dfs_pop  = 1'b0;
    dfs_push = 1'b0;
    dfs_leaf = 1'b0;

    sp_next  = sp;

    cur_node  = {ID_W{1'b0}};
    cur_code  = 8'd0;
    cur_depth = 4'd0;

    if (state == S_DFS_RUN && sp != 0) begin
        // pop
        dfs_pop  = 1'b1;
        cur_node  = stack_node[sp-1];
        cur_code  = stack_code[sp-1];
        cur_depth = stack_depth[sp-1];

        if (cur_node < IP_WIDTH) begin
            // leaf node
            dfs_leaf = 1'b1;
            sp_next  = sp - 1;          // pop only
        end
        else begin
            // internal node
            dfs_push = 1'b1;
            sp_next  = sp - 1 + 2;      // pop + push two
        end
    end
end

// ---------- DFS seq ----------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sp <= 0;
    end
    else if (state == S_DFS_INIT) begin
        // push root
        sp <= 1;
        stack_node[0]  <= next_node - 1;
        stack_code[0]  <= 8'd0;
        stack_depth[0] <= 4'd0;
    end
    else if (state == S_IDLE) begin
        sp <= 0;
    end 
    else if (state == S_DFS_RUN && dfs_pop) begin
        // update stack pointer
        sp <= sp_next;

        if (dfs_leaf) begin
            // record Huffman code
            code_table[cur_node] <= cur_code;
            code_len  [cur_node] <= cur_depth;
        end
        else if (dfs_push) begin
            // push right child first (so left is processed first)
            stack_node[sp-1]  <= node_r[cur_node];
            stack_code[sp-1]  <= (cur_code << 1) | 1'b1;
            stack_depth[sp-1] <= cur_depth + 1;

            stack_node[sp]    <= node_l[cur_node];
            stack_code[sp]    <= (cur_code << 1);
            stack_depth[sp]   <= cur_depth + 1;
        end
    end
end


// ============================================================================
// Output
// ============================================================================
reg out_done;
reg out_active;   
reg start_valid;
localparam IDX_A=0, IDX_B=1, IDX_C=2, IDX_E=3,
           IDX_I=4, IDX_L=5, IDX_O=6, IDX_V=7;

reg [2:0] out_char_idx;   // 0~4
reg [3:0] out_bit_idx;

reg [3:0] cur_len;
reg [7:0] cur_code1;

wire [2:0] char_sel [0:4];

assign char_sel[0] = IDX_I;
assign char_sel[1] = out_mode ? IDX_C : IDX_L;
assign char_sel[2] = out_mode ? IDX_L : IDX_O;
assign char_sel[3] = out_mode ? IDX_A : IDX_V;
assign char_sel[4] = out_mode ? IDX_B : IDX_E;

wire last_bit  = (out_bit_idx  == cur_len - 1);
wire last_char = (out_char_idx == 3'd4);


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_valid    <= 1'b0;
        out_active   <= 1'b0;
        out_code     <= 1'b0;
        out_done     <= 1'b0;
        out_char_idx <= 3'd0;
        out_bit_idx  <= 4'd0;
        cur_len      <= 4'd0;
        cur_code1    <= 8'd0;
        start_valid    <= 1'b0;
    end
    // --------------------------------------------------
    // Prepare output
    // --------------------------------------------------
    else if (state == S_PREP_OUT) begin
        out_char_idx <= 3'd0;
        out_bit_idx  <= 4'd0;
        cur_code1    <= code_table[char_sel[0]];
        cur_len      <= code_len  [char_sel[0]];
        out_active   <= 1'b1;   
        start_valid    <= 1'b1;
        out_done     <= 1'b0;
    end
    // --------------------------------------------------
    // Output streaming
    // --------------------------------------------------
    else if (state == S_OUT && out_active) begin
        
        out_code <= cur_code1[cur_len - 1 - out_bit_idx];
        if (start_valid)begin
            out_valid <= 1;
            end
        if (last_bit) begin
            out_bit_idx <= 4'd0;

            if (!last_char) begin
    
                out_char_idx <= out_char_idx + 1'b1;
                cur_code1    <= code_table[char_sel[out_char_idx + 1'b1]];
                cur_len      <= code_len  [char_sel[out_char_idx + 1'b1]];
            end
            else begin
  
                out_active <= 1'b0;  
                out_done   <= 1'b1;
            end
        end
        else begin
            out_bit_idx <= out_bit_idx + 1'b1;
        end
    end
    // --------------------------------------------------
    // Default / idle
    // --------------------------------------------------
    else begin
        out_valid <= out_active; // <<< ??????????
        out_done  <= 1'b0;
        out_code <= 1'b0;
        start_valid    <= 1'b0;
            end
end      

endmodule    





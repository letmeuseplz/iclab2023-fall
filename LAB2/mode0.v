// Mode0_slope_FSM_full.v
module Mode0 (
    input  wire        clk,
    input  wire        rst_n,      // async low active
    input  wire        in_valid,
    input  wire [1:0]  mode,
    input  wire signed [7:0] xi,
    input  wire signed [7:0] yi,
    output reg         out_valid,
    output reg signed [7:0] xo,
    output reg signed [7:0] yo
);

//================== State ==================//
localparam IDLE    = 2'b00;
localparam PREPARE = 2'b01;
localparam OUTPUT  = 2'b10;
localparam DONE    = 2'b11;

reg [1:0] state, next_state;

//================== Registers ==================//
// input points
reg signed [7:0] x_ul, y_u;
reg signed [7:0] x_ur;
reg signed [7:0] x_dl, y_d;
reg signed [7:0] x_dr;

// slope & accumulator
reg signed [16:0] slopeL, slopeR;  // DX*Y 累積量
reg signed [16:0] counterL, counterR; // 累積器

// current row output
reg signed [7:0] cur_y;
reg signed [7:0] row_x_start, row_x_end;
reg signed [7:0] out_x;

// input counter
reg [2:0] in_cnt;

//================== Combinational wires ==================//
wire input_done = (in_cnt == 4);
wire row_done   = (out_x == row_x_end);
wire all_done   = (row_done && (cur_y == y_u));
wire signed [7:0] next_y = cur_y + 1;

// 計算下一列的累積值整數部分偏移
wire signed [16:0] counterL_next = counterL + slopeL;
wire signed [16:0] counterR_next = counterR + slopeR;

// floor 整數偏移 (負數向下取整)
wire signed [8:0] int_offsetL = (counterL_next >= 0) ? 
                                (counterL_next / (y_u - y_d)) : 
                                ((counterL_next - (y_u - y_d) + 1) / (y_u - y_d));

wire signed [8:0] int_offsetR = (counterR_next >= 0) ? 
                                (counterR_next / (y_u - y_d)) : 
                                ((counterR_next - (y_u - y_d) + 1) / (y_u - y_d));

// 下一列邊界
wire signed [7:0] row_x_start_next = x_dl + int_offsetL;
wire signed [7:0] row_x_end_next   = x_dr + int_offsetR;

//================== FSM ==================//
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

always @* begin
    case (state)
        IDLE:    next_state = input_done ? PREPARE : IDLE;
        PREPARE: next_state = OUTPUT;
        OUTPUT:  next_state = all_done ? DONE : OUTPUT;
        DONE:    next_state = IDLE;
        default: next_state = IDLE;
    endcase
end

//================== Datapath ==================//
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // reset all
        in_cnt <= 0;
        out_valid <= 0;
        xo <= 0; yo <= 0;

        x_ul<=0; x_ur<=0; x_dl<=0; x_dr<=0; y_u<=0; y_d<=0;
        slopeL<=0; slopeR<=0;
        counterL<=0; counterR<=0;
        row_x_start<=0; row_x_end<=0; out_x<=0; cur_y<=0;
    end else begin
        case (state)
            IDLE: begin
                out_valid <= 0;
                xo <= 0; yo <= 0;
                if (mode==2'b00 && in_valid) begin
                    case (in_cnt)
                        3'd0: begin x_ul <= xi; y_u <= yi; end
                        3'd1: x_ur <= xi;
                        3'd2: begin x_dl <= xi; y_d <= yi; end
                        3'd3: x_dr <= xi;
                    endcase
                    in_cnt <= in_cnt + 1;
                end
            end

            PREPARE: begin
                // 初始化第一列 row = y_d
                cur_y <= y_d;

                // slope = DX 每列累積量
                slopeL <= x_ul - x_dl;
                slopeR <= x_ur - x_dr;

                counterL <=  0;
                counterR <= 0;

                row_x_start <= x_dl;
                row_x_end   <= x_dr;
                out_x       <= x_dl;
            end

            OUTPUT: begin
                out_valid <= 1;
                xo <= out_x;
                yo <= cur_y;


   
                if (row_done) begin
                    if (!all_done) begin
                        // 下一列累積

                        counterL <= counterL_next;
                        counterR <= counterR_next;
                        row_x_start <= row_x_start_next;
                        row_x_end   <= row_x_end_next;
                        // 進入下一列
                        cur_y <= next_y;
                        out_x <= row_x_start_next;
                    end
                end else begin
                    out_x <= out_x + 1;
                end
            end

            DONE: begin
                out_valid <= 0;
                xo <= 0; yo <= 0;
                in_cnt <= 0;
            end
        endcase
    end
end

endmodule

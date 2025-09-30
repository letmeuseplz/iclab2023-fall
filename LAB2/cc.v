module CC(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [1:0]  mode,
    input  wire signed [7:0] xi,
    input  wire signed [7:0] yi,
    output reg         out_valid,
    output reg signed [7:0] xo,
    output reg signed [7:0] yo
);

// -----------------------------
// Mode0 instance
// -----------------------------
wire        m0_out_valid;
wire signed [7:0] m0_xo, m0_yo;

Mode0 u_mode0 (
    .clk      (clk),
    .rst_n    (rst_n),
    .in_valid (in_valid),
    .mode     (mode),
    .xi       (xi),
    .yi       (yi),
    .out_valid(m0_out_valid),
    .xo       (m0_xo),
    .yo       (m0_yo)
);

// ===================================================
// Input buffer
// ===================================================
reg signed [7:0] x [0:3];
reg signed [7:0] y [0:3];
reg [2:0] cnt;
reg [1:0] cur_mode;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt <= 0;
        x[0]<=0; x[1]<=0; x[2]<=0; x[3]<=0;
        y[0]<=0; y[1]<=0; y[2]<=0; y[3]<=0;
    end else if(in_valid) begin
        x[cnt] <= xi;
        y[cnt] <= yi;
        cnt <= cnt+1;
    end else begin
        cnt <= 0;
    end
end

// latch mode at first data
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) cur_mode <= 2'b00;
    else if(in_valid && cnt==0) cur_mode <= mode;
end

// ===================================================
// 共用乘法 pipeline
// ===================================================
reg signed [15:0] diff1, diff2, diff3, diff4;
reg signed [31:0] mul0, mul1;
wire signed [31:0] sum = mul0 + mul1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mul0 <= 0; mul1 <= 0;
    end else begin
        mul0 <= diff1 * diff2;
        mul1 <= diff3 * diff4;
    end
end

// ===================================================
// Pipeline counter (從第2筆資料進來後啟動)
// ===================================================
reg [2:0] pipe_cnt;
reg in_valid_d;


always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        pipe_cnt <= 0;
    else if(in_valid) begin
        if(cnt==1)                // 第2筆進來，啟動 pipe
            pipe_cnt <= 3'd1;
        else if(pipe_cnt != 0)    // 之後每次有新資料進來才推進
            pipe_cnt <= pipe_cnt + 1;
    end else if(pipe_cnt != 0 && pipe_cnt < 7) begin
        // 輸入結束後，pipeline 還要把尾巴推完
        pipe_cnt <= pipe_cnt + 1;
    end else if(pipe_cnt == 7)
        pipe_cnt <= 0;
end

// ===================================================
// Mode1 / Mode2 pipeline (同一個 always block)
// ===================================================
reg [15:0] rsquare, r2;
reg [15:0] cross_val;
reg [31:0] cross2;
reg [1:0]  m1_result;
reg        m1_done;

reg [16:0] m2_acc;
reg [15:0] m2_area;
reg        m2_done;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        diff1<=0; diff2<=0; diff3<=0; diff4<=0;
        rsquare <= 0; r2 <= 0; cross_val <= 0; cross2 <= 0;
        m1_result <= 2'b00; m1_done <= 0;
        m2_acc <= 0; m2_area <= 0; m2_done <= 0;
    end else begin
        m1_done <= 0;
        m2_done <= 0;

        case(cur_mode)
        // ===================================================
        // Mode1 pipeline
        // ===================================================
        2'b01: case(pipe_cnt)
            3'd1: begin
                diff1 <= x[1]-x[0]; diff2 <= x[1]-x[0];
                diff3 <= y[1]-y[0]; diff4 <= y[1]-y[0];
            end
            3'd2: begin
                
                diff1 <= x[2]-x[0]; diff2 <= -(y[1]-y[0]);
                diff3 <= y[2]-y[0]; diff4 <=  (x[1]-x[0]);
            end
            3'd3: begin
                rsquare <= sum;
                
                diff1 <= x[3]-x[2]; diff2 <= x[3]-x[2];
                diff3 <= y[3]-y[2]; diff4 <= y[3]-y[2];
            end
            3'd4: begin

                diff1 <= sum; diff2 <= sum;
                diff3 <= 0; diff4 <= 0;
            end
            3'd5: begin

                diff1 <= rsquare; diff2 <= sum;
                diff3 <= 0; diff4 <= 0;
            end
            3'd6: begin
                cross2 <= sum;

            end
            3'd7: begin
                if (cross2 > sum)      m1_result <= 2'b00;
                else if (cross2==sum)  m1_result <= 2'b10;
                else                   m1_result <= 2'b01;
                m1_done <= 1'b1;
            end
        endcase

        // ===================================================
        // Mode2 pipeline (shoelace area)
        // ===================================================
        2'b10: case(pipe_cnt)
            3'd1: begin
                diff1 <= x[0]; diff2 <= y[1];
                diff3 <= -y[0]; diff4 <= x[1];
            end
            3'd2: begin
   
                diff1 <= x[1]; diff2 <= y[2];
                diff3 <= -y[1]; diff4 <= x[2];
            end
            3'd3: begin
                m2_acc <=  sum;
                diff1 <= x[2]; diff2 <= y[3];
                diff3 <= -y[2]; diff4 <= x[3];
            end
            3'd4: begin
                m2_acc <= m2_acc + sum;
                diff1 <= x[3]; diff2 <= y[0];
                diff3 <= -y[3]; diff4 <= x[0];
            end
            3'd5: begin
                m2_acc <= m2_acc + sum;

            end
            3'd6: begin
                m2_acc <= m2_acc + sum;

            end
            3'd7: begin

                if (m2_acc[16]==1'b0)
                    m2_area <= m2_acc >> 1;
                else
                    m2_area <= (~m2_acc+1'b1) >> 1;
                m2_done <= 1'b1;
            end
        endcase
        endcase
    end
end

// ===================================================
// Output mux
// ===================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        out_valid <= 1'b0;
        xo <= 8'sd0;
        yo <= 8'sd0;
    end else begin
        if(m0_out_valid) begin
            out_valid <= 1'b1; xo <= m0_xo; yo <= m0_yo;
        end else if(m1_done) begin
            out_valid <= 1'b1; xo <= 8'sd0; yo <= m1_result;
        end else if(m2_done) begin
            out_valid <= 1'b1; xo <= m2_area[15:8]; yo <= m2_area[7:0];
        end else begin
            out_valid <= 1'b0;
        end
    end
end

endmodule

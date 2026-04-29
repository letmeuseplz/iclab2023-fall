module TMIP (
    input clk,
    input rst_n,
    input in_valid,
    input in_valid2,
    input [7:0] image,
    input [7:0] template,
    input [1:0] image_size,
    input [2:0] action,
    output reg out_valid,
    output reg [19:0] out_value
);

    // ==========================================
    // Parameters & State Definition
    // ==========================================
    localparam ST_IDLE    = 3'd0,
               ST_IN_IMG  = 3'd1,
               ST_WAIT    = 3'd2,
               ST_IN_ACT  = 3'd3,
               ST_GRAY    = 3'd4,
               ST_PROCESS = 3'd5,
               ST_OUT     = 3'd6;

    reg [2:0] state, nstate;

    reg [1:0] img_size_reg;
    reg [4:0] dim;         
    reg [7:0] max_pixel;   
    reg [7:0] tpl [0:8];   
    reg [2:0] acts [0:7];  
    reg [3:0] act_total;
    reg [3:0] act_idx;
    reg       pingpong;    

    reg [7:0] recv_count;
    reg [1:0] rgb_cnt;
    reg [15:0] rgb_tmp;    
    reg [8:0] process_cnt; 
    reg [2:0] set_cnt;     
    reg [3:0] tpl_cnt;

    reg [19:0] wdata_proc;
    reg [7:0]  waddr_proc;

    // ==========================================
    // SRAM Interface
    // ==========================================
    reg         we_img, we_a, we_b;
    reg  [7:0]  addr_img, addr_a, addr_b;
    reg  [23:0] din_img;
    reg  [19:0] din_a, din_b;
    wire [23:0] dout_img;
    wire [19:0] dout_a, dout_b;

    wire re_img = ~we_img; 

    sram_256x24_wrapper SRAM_IMG (
        .clk(clk), .we(we_img), .re(re_img),
        .waddr(addr_img), .wdata(din_img), .raddr(addr_img), .rdata(dout_img)
    );

    wire        wr_en   = we_a | we_b;  
    wire [8:0]  wr_addr = (we_a) ? {1'b0, addr_a} : {1'b1, addr_b};
    wire [19:0] wr_data = (we_a) ? din_a : din_b;
    wire [8:0]  rd_addr = (pingpong == 0) ? {1'b0, addr_a} : {1'b1, addr_b};
    wire [19:0] rd_data_20;

    // ★ 關鍵修復：CENA 固定為 0 (全時開啟讀取)，不再漏掉第 0 顆 Pixel
    sram_512_20 SRAM_PINGPONG (
        .QA(rd_data_20), .CLKA(clk), .CENA(1'b0), .WENA(1'b1), .AA(rd_addr), .DA(20'd0), .EMAA(3'b000),
        .QB(), .CLKB(clk), .CENB(~wr_en), .WENB(~wr_en), .AB(wr_addr), .DB(wr_data), .EMAB(3'b000)
    );

    assign dout_a = rd_data_20[19:0];
    assign dout_b = rd_data_20[19:0];
    wire [19:0] src_data = (pingpong == 0) ? dout_a : dout_b;

    // ==========================================
    // Pipeline Delay & 座標產生器
    // ==========================================
    wire is_act3 = (acts[act_idx] == 3'd3);
    wire is_act4 = (acts[act_idx] == 3'd4);
    wire is_act5 = (acts[act_idx] == 3'd5);
    wire is_act6 = (acts[act_idx] == 3'd6);
    wire is_act7 = (acts[act_idx] == 3'd7);

    wire [4:0] delay = (is_act6 || is_act7) ? (dim + 5'd3) : 5'd2;
    wire signed [9:0] eval_cnt_signed = $signed({1'b0, process_cnt}) - $signed({5'b0, delay});
    wire [8:0] eval_cnt = eval_cnt_signed[8:0];
    wire eval_valid = (eval_cnt_signed >= 0) && (eval_cnt <= max_pixel);

    wire [7:0] cx = eval_cnt & (dim - 8'd1);
    wire [7:0] cy = (dim == 5'd16) ? (eval_cnt >> 4) : 
                    (dim == 5'd8)  ? (eval_cnt >> 3) : (eval_cnt >> 2);

    // ==========================================
    // FSM Control
    // ==========================================
    always @(*) begin
        nstate = state;
        case (state)
            ST_IDLE:    if (in_valid) nstate = ST_IN_IMG;
            ST_IN_IMG:  if (!in_valid) nstate = ST_IN_ACT;
            ST_WAIT:    if (in_valid2) nstate = ST_IN_ACT;
            ST_IN_ACT:  if (!in_valid2 && act_total > 0) nstate = ST_GRAY;
            ST_GRAY:    if (process_cnt == max_pixel + 1) nstate = (act_total == 1) ? ST_OUT : ST_PROCESS;
            ST_PROCESS: if (process_cnt == max_pixel + delay) nstate = (act_idx == act_total - 1) ? ST_OUT : ST_PROCESS;
            ST_OUT:     if (process_cnt == max_pixel + 1) nstate = (set_cnt == 7) ? ST_IDLE : ST_WAIT;
            default:    nstate = ST_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= ST_IDLE;
        else        state <= nstate;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            recv_count <= 0; rgb_cnt <= 0; act_total <= 0; act_idx <= 1;
            process_cnt <= 0; pingpong <= 0; set_cnt <= 0; rgb_tmp <= 0;
            dim <= 0; max_pixel <= 0; img_size_reg <= 0; tpl_cnt <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    recv_count <= 0; rgb_cnt <= 0; set_cnt <= 0; process_cnt <= 0; tpl_cnt <= 0;act_total <= 0;
                    if (in_valid) begin
                        img_size_reg <= image_size;
                        if (rgb_cnt == 0) rgb_tmp[15:8] <= image;
                        rgb_cnt <= rgb_cnt + 1;
                        tpl[0] <= template;
                        tpl_cnt <= 1;
                    end
                end
                ST_IN_IMG: begin
                    if (in_valid) begin
                        if (rgb_cnt == 0) rgb_tmp[15:8] <= image;
                        else if (rgb_cnt == 1) rgb_tmp[7:0] <= image;
                        
                        if (rgb_cnt < 2) rgb_cnt <= rgb_cnt + 1;
                        else begin rgb_cnt <= 0; recv_count <= recv_count + 1; end
                        
                        if (tpl_cnt < 9) begin
                            tpl[tpl_cnt] <= template;
                            tpl_cnt <= tpl_cnt + 1;
                        end
                    end else recv_count <= 0;
                end
                ST_WAIT: begin
                    if (in_valid2) begin act_total <= 1; acts[0] <= action; end
                end
                ST_IN_ACT: begin
                    pingpong <= 0; process_cnt <= 0; act_idx <= 1;
                    dim <= (img_size_reg == 0) ? 4 : (img_size_reg == 1) ? 8 : 16;
                    max_pixel <= (img_size_reg == 0) ? 15 : (img_size_reg == 1) ? 63 : 255;
                    if (in_valid2) begin acts[act_total] <= action; act_total <= act_total + 1; end
                end
                ST_GRAY: if (process_cnt == max_pixel + 1) process_cnt <= 0; else process_cnt <= process_cnt + 1;
                ST_PROCESS: begin
                    if (process_cnt == max_pixel + delay) begin
                        process_cnt <= 0; act_idx <= act_idx + 1; pingpong <= ~pingpong;
                        if (is_act3 && dim > 4) begin dim <= dim >> 1; max_pixel <= max_pixel >> 2; end
                    end else process_cnt <= process_cnt + 1;
                end
                ST_OUT: if (process_cnt == max_pixel + 1) begin process_cnt <= 0; set_cnt <= set_cnt + 1; end else process_cnt <= process_cnt + 1;
            endcase
        end
    end

    // ==========================================
    // ★ Ring Line Buffer & 3x3 Sliding Window
    // ==========================================
    reg [19:0] win [0:8];       
    reg [19:0] lb0 [0:15];      
    reg [19:0] lb1 [0:15];      

    wire [8:0] in_cnt = process_cnt - 1;
    wire [7:0] in_x   = in_cnt & (dim - 8'd1);

    integer s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(s=0; s<9; s=s+1) win[s] <= 0;
            for(s=0; s<16; s=s+1) begin lb0[s] <= 0; lb1[s] <= 0; end
        // ★ MUX 清空：每次吃新測資前，把上一張圖的毒藥洗乾淨
        end else if (state == ST_IN_ACT) begin
            for(s=0; s<9; s=s+1) win[s] <= 0;
            for(s=0; s<16; s=s+1) begin lb0[s] <= 0; lb1[s] <= 0; end
        end else if (state == ST_PROCESS) begin
            if (process_cnt > 0) begin
                win[0] <= win[1]; win[1] <= win[2];
                win[3] <= win[4]; win[4] <= win[5];
                win[6] <= win[7]; win[7] <= win[8];

                win[2] <= lb1[in_x];
                win[5] <= lb0[in_x];
                win[8] <= (process_cnt <= max_pixel + 1) ? src_data : 20'd0;

                if (process_cnt <= max_pixel + 1) begin
                    lb1[in_x] <= lb0[in_x];
                    lb0[in_x] <= src_data;
                end
            end
        end
    end

    // ==========================================
    // ALU: ACT 0, 1, 2 (灰階轉換)
    // ==========================================
    wire [7:0] R = dout_img[23:16]; 
    wire [7:0] G = dout_img[15:8]; 
    wire [7:0] B = dout_img[7:0];
    
    wire [7:0] max_rg   = (R >= G) ? R : G;
    wire [7:0] gray_max = (max_rg >= B) ? max_rg : B;
    
    wire [9:0] sum_rgb  = {2'b0, R} + {2'b0, G} + {2'b0, B};
    wire [7:0] gray_avg = (sum_rgb * 683) >> 11; // 對齊 Python 的 //3

    wire [7:0] gray_wgt = (R >> 2) + (G >> 1) + (B >> 2); // 保持原樣，對齊 Python 的分別除法
    
    wire [7:0] gray_out = (acts[0] == 3'd0) ? gray_max : 
                          (acts[0] == 3'd1) ? gray_avg : gray_wgt;

    // ==========================================
    // ALU: Max Pool & 3x3 Extraction
    // ==========================================
    wire [19:0] mp_max01 = (win[8] > win[7]) ? win[8] : win[7];
    wire [19:0] mp_max23 = (win[5] > win[4]) ? win[5] : win[4];
    wire [19:0] mp_max   = (mp_max01 > mp_max23) ? mp_max01 : mp_max23;

    wire is_top = (cy == 0); wire is_bottom = (cy == dim - 1);
    wire is_left = (cx == 0); wire is_right = (cx == dim - 1);

    wire [19:0] raw_ul = win[0]; wire [19:0] raw_u = win[1]; wire [19:0] raw_ur = win[2];
    wire [19:0] raw_l  = win[3]; wire [19:0] raw_c = win[4]; wire [19:0] raw_r  = win[5];
    wire [19:0] raw_dl = win[6]; wire [19:0] raw_d = win[7]; wire [19:0] raw_dr = win[8];

    wire [19:0] pad_ul = is_act7 ? ((is_top | is_left) ? 0 : raw_ul) : ((is_top & is_left) ? raw_c : is_top ? raw_l : is_left ? raw_u : raw_ul);
    wire [19:0] pad_u  = is_act7 ? (is_top ? 0 : raw_u) : (is_top ? raw_c : raw_u);
    wire [19:0] pad_ur = is_act7 ? ((is_top | is_right) ? 0 : raw_ur) : ((is_top & is_right) ? raw_c : is_top ? raw_r : is_right ? raw_u : raw_ur);
    wire [19:0] pad_l  = is_act7 ? (is_left ? 0 : raw_l) : (is_left ? raw_c : raw_l);
    wire [19:0] pad_c  = raw_c; 
    wire [19:0] pad_r  = is_act7 ? (is_right ? 0 : raw_r) : (is_right ? raw_c : raw_r);
    wire [19:0] pad_dl = is_act7 ? ((is_bottom | is_left) ? 0 : raw_dl) : ((is_bottom & is_left) ? raw_c : is_bottom ? raw_l : is_left ? raw_d : raw_dl);
    wire [19:0] pad_d  = is_act7 ? (is_bottom ? 0 : raw_d) : (is_bottom ? raw_c : raw_d);
    wire [19:0] pad_dr = is_act7 ? ((is_bottom | is_right) ? 0 : raw_dr) : ((is_bottom & is_right) ? raw_c : is_bottom ? raw_r : is_right ? raw_d : raw_dr);

    wire [19:0] w_px [0:8];
    assign w_px[0]=pad_ul; assign w_px[1]=pad_u; assign w_px[2]=pad_ur;
    assign w_px[3]=pad_l;  assign w_px[4]=pad_c; assign w_px[5]=pad_r;
    assign w_px[6]=pad_dl; assign w_px[7]=pad_d; assign w_px[8]=pad_dr;

    wire [19:0] filter_median;
    MEDIAN9 u_med9 (
        .p0(w_px[0]), .p1(w_px[1]), .p2(w_px[2]),
        .p3(w_px[3]), .p4(w_px[4]), .p5(w_px[5]),
        .p6(w_px[6]), .p7(w_px[7]), .p8(w_px[8]),
        .median_val(filter_median)
    );

    wire [19:0] mac_out = w_px[0]*tpl[0] + w_px[1]*tpl[1] + w_px[2]*tpl[2] +
                          w_px[3]*tpl[3] + w_px[4]*tpl[4] + w_px[5]*tpl[5] +
                          w_px[6]*tpl[6] + w_px[7]*tpl[7] + w_px[8]*tpl[8];

    // ==========================================
    // Muxing Write Target 
    // ==========================================
    always @(*) begin
        wdata_proc = 0; 
        waddr_proc = 0; 

        if (is_act3) begin 
            // ★ 修復 Set 4 爆炸的元兇：4x4 影像不准 Pooling
            wdata_proc = (dim > 4) ? mp_max : win[8]; 
            waddr_proc = (dim > 4) ? ((cy >> 1) * (dim >> 1) + (cx >> 1)) : eval_cnt; 
        end
        else if (is_act4) begin wdata_proc = {12'd0, ~win[8][7:0]}; waddr_proc = eval_cnt; end
        else if (is_act5) begin wdata_proc = win[8]; waddr_proc = cy * dim + (dim - 1 - cx); end
        else if (is_act6) begin wdata_proc = filter_median; waddr_proc = eval_cnt; end
        else if (is_act7) begin wdata_proc = mac_out; waddr_proc = eval_cnt; end
    end

    // ==========================================
    // SRAM Access Control
    // ==========================================
    always @(*) begin
        we_img = 0; addr_img = 0; din_img = 0; we_a = 0; addr_a = 0; din_a = 0; we_b = 0; addr_b = 0; din_b = 0;
        
        case (state)
            ST_IN_IMG: begin
                if (in_valid && rgb_cnt == 2) begin
                    we_img = 1; addr_img = recv_count; din_img = {rgb_tmp, image}; 
                end
            end
            ST_GRAY: begin
                addr_img = process_cnt; 
                we_a = (process_cnt > 0 && process_cnt <= max_pixel + 1);
                addr_a = process_cnt - 1; din_a = {12'd0, gray_out}; 
            end
            ST_PROCESS: begin
                if (process_cnt <= max_pixel) begin
                    if (pingpong == 0) addr_a = process_cnt; else addr_b = process_cnt;
                end
                
                if (eval_valid) begin
                    // ★ 放寬寫入條件：如果 dim <= 4 且遇到 Act3，每一點都要寫入 SRAM 保留原圖
                    if (!is_act3 || dim <= 4 || (cx[0] == 1 && cy[0] == 1)) begin
                        if (pingpong == 0) begin we_b = 1; addr_b = waddr_proc; din_b = wdata_proc; end 
                        else begin we_a = 1; addr_a = waddr_proc; din_a = wdata_proc; end
                    end
                end
            end
            ST_OUT: begin
                if (pingpong == 1) addr_b = process_cnt; else addr_a = process_cnt;
            end
        endcase
    end

    // ==========================================
    // Output Logic
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0; out_value <= 0;
        end else if (state == ST_OUT) begin
            if (process_cnt > 0 && process_cnt <= max_pixel + 1) begin
                out_valid <= 1; out_value <= (pingpong == 1) ? dout_b : dout_a;
            end else begin
                out_valid <= 0; out_value <= 0;
            end
        end else begin
            out_valid <= 0; out_value <= 0;
        end
    end

endmodule

// ==========================================
// SRAM Wrapper (保持不變，讀寫完美分離)
// ==========================================
module sram_256x24_wrapper (
    input  wire        clk,
    input  wire        we,  
    input  wire        re,  
    input  wire [7:0]  waddr, 
    input  wire [23:0] wdata,
    input  wire [7:0]  raddr, 
    output wire [23:0] rdata
);
    wire we_lower = we & (~waddr[7]); 
    wire we_upper = we & ( waddr[7]); 
    wire re_lower = re & (~raddr[7]); 
    wire re_upper = re & ( raddr[7]); 
    wire [23:0] rdata_lower, rdata_upper;

    sram_25624 RF_LOWER (.QA(rdata_lower), .CLKA(clk), .CENA(~re_lower), .AA(raddr[6:0]), .EMAA(3'b000), .CLKB(clk), .CENB(~we_lower), .AB(waddr[6:0]), .DB(wdata), .EMAB(3'b000));
    sram_25624 RF_UPPER (.QA(rdata_upper), .CLKA(clk), .CENA(~re_upper), .AA(raddr[6:0]), .EMAA(3'b000), .CLKB(clk), .CENB(~we_upper), .AB(waddr[6:0]), .DB(wdata), .EMAB(3'b000));

    reg raddr_msb_d1;
    always @(posedge clk) raddr_msb_d1 <= raddr[7];
    assign rdata = raddr_msb_d1 ? rdata_upper : rdata_lower;
endmodule
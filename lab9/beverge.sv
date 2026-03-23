module BEV(
    input clk, rst_n,
    input sel_action_valid, type_valid, size_valid, date_valid, box_no_valid, box_sup_valid,
    input [11:0] D,
    output logic out_valid, complete,
    output logic [1:0] err_msg,
   
    output logic [7:0]  C_addr,
    output logic        C_r_wb, C_in_valid,
    output logic [63:0] C_data_w,
    input               C_out_valid,
    input        [63:0] C_data_r
);

// ============================================================================

// ============================================================================
typedef enum logic [2:0] {
    ST_IDLE       = 3'd0,
    ST_GET        = 3'd1, 
    ST_READ_REQ   = 3'd2, 
    ST_READ_WAIT  = 3'd3, 
    ST_CALC       = 3'd4, 
    ST_WRITE_REQ  = 3'd5,
    ST_WRITE_WAIT = 3'd6, 
    ST_OUT        = 3'd7  
} state_t;

state_t state, next_state;


logic [63:0] dram_data_reg;
logic [1:0]  err_reg;
logic        comp_reg;
logic [63:0] wdata_reg;


// ============================================================================
// (Register Declarations)
// ============================================================================
logic [1:0]  action_reg; 
logic [2:0]  type_reg;   
logic [1:0]  size_reg;   
logic [3:0]  month_reg;  
logic [4:0]  day_reg;    
logic [7:0]  box_no_reg;


logic [11:0] sup_bt, sup_gt, sup_m, sup_p; 
logic [1:0]  sup_cnt;   
// ============================================================================
// (Input Unpacking & Gathering)
// ============================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
       
        action_reg <= 2'd0;
        type_reg   <= 3'd0;
        size_reg   <= 2'd0;
        month_reg  <= 4'd0;
        day_reg    <= 5'd0;
        box_no_reg <= 8'd0;
        sup_bt <= 12'd0; sup_gt <= 12'd0; sup_m <= 12'd0; sup_p <= 12'd0;
        sup_cnt <= 2'd0;
    end else begin
        case (state)
          
            ST_IDLE: begin
                sup_cnt <= 2'd0; 
                
                if (sel_action_valid) begin
                   
                    action_reg <= D[1:0]; 
                end
            end
            
    
            ST_GET: begin
                

                if (type_valid) begin
    
                    type_reg <= D[2:0];
                end
 
                if (size_valid) begin
  
                    size_reg <= D[1:0];
                end

                if (date_valid) begin
                 
                    month_reg <= D[8:5]; 
                    day_reg   <= D[4:0]; 
                end
                
   
                if (box_no_valid) begin
           
                    box_no_reg <= D[7:0];
                end

                if (box_sup_valid) begin
                    if (sup_cnt < 2'd3) begin
                        sup_cnt <= sup_cnt + 1'b1;
                    end
                    
                 
                    case (sup_cnt)
                        2'd0: sup_bt <= D[11:0]; 
                        2'd1: sup_gt <= D[11:0]; 
                        2'd2: sup_m  <= D[11:0]; 
                        2'd3: sup_p  <= D[11:0]; 
                    endcase
                end
                
            end
    
        endcase
    end
end

// ============================================================================
logic [11:0] d_bt, d_gt, d_m, d_p;
logic [7:0]  d_exp_m, d_exp_d;
assign {d_bt, d_gt, d_exp_m, d_m, d_p, d_exp_d} = dram_data_reg;


logic is_exp;

assign is_exp = (month_reg > d_exp_m) || 
                ((month_reg == d_exp_m) && (day_reg > d_exp_d));


logic [9:0] vol;

assign vol = (size_reg == 2'b00) ? 10'd960 : 
             (size_reg == 2'b01) ? 10'd720 : 10'd480;


logic [9:0] req_bt, req_gt, req_m, req_p;   //配方
always_comb begin
    
    req_bt = 0; req_gt = 0; req_m = 0; req_p = 0;
    
    
    case (type_reg)
        3'd0: req_bt = vol;                                           // total 960, 720, 480 按比例
        3'd1: begin req_bt = (vol>>2)*3; req_m = (vol>>2);   end   
        3'd3: req_gt = vol;                                        
        3'd4: begin req_gt = (vol>>1);   req_m = (vol>>1);   end   
        3'd5: req_p  = vol;                                        
        3'd6: begin req_bt = (vol>>1);   req_p = (vol>>1);   end   
        3'd7: begin req_bt = (vol>>1); req_m = (vol>>2); req_p = (vol>>2); end 
    endcase
end

// d=00 檢困存
logic signed [12:0] rem_bt, rem_gt, rem_m, rem_p;
assign rem_bt = {1'b0, d_bt} - {3'b0, req_bt};
assign rem_gt = {1'b0, d_gt} - {3'b0, req_gt};
assign rem_m  = {1'b0, d_m}  - {3'b0, req_m};
assign rem_p  = {1'b0, d_p}  - {3'b0, req_p};

logic is_short;

assign is_short = rem_bt[12] | rem_gt[12] | rem_m[12] | rem_p[12];

// --- 庫存增加 (Supply) ---
// 13-bit 可以容納超過 4095 的值，用來判斷是否溢位
logic [12:0] add_bt, add_gt, add_m, add_p;
assign add_bt = {1'b0, d_bt} + {1'b0, sup_bt};
assign add_gt = {1'b0, d_gt} + {1'b0, sup_gt};
assign add_m  = {1'b0, d_m}  + {1'b0, sup_m};
assign add_p  = {1'b0, d_p}  + {1'b0, sup_p};



logic is_of;
assign is_of = add_bt[12] | add_gt[12] | add_m[12] | add_p[12];




// ============================================================================
// 6. 核心結算 (結算 ST_CALC 資料)
// ============================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dram_data_reg <= 64'd0;
        err_reg       <= 2'b00; 
        comp_reg      <= 1'b0; 
        wdata_reg     <= 64'd0;
    end else begin
        
        
        if (state == ST_READ_WAIT && C_out_valid) begin
            dram_data_reg <= C_data_r;
        end
        
       
        if (state == ST_CALC) begin
            case (action_reg)
                
                // ------------------------------------
                // Make Drink (製作飲料)
                // ------------------------------------
                2'b00: begin 
                    if (is_exp) begin 
                        err_reg  <= 2'b01; // No_Exp
                        comp_reg <= 1'b0; 
                    end
                    else if (is_short) begin 
                        err_reg  <= 2'b10; // No_Ing
                        comp_reg <= 1'b0; 
                    end
                    else begin
                        err_reg  <= 2'b00; // No_Err
                        comp_reg <= 1'b1;
                  
                        wdata_reg <= {rem_bt[11:0], rem_gt[11:0], d_exp_m, 
                                      rem_m[11:0], rem_p[11:0], d_exp_d};
                    end
                end
                
                // ------------------------------------
                // Supply (補貨)
                // ------------------------------------
                2'b01: begin 
                        err_reg  <= is_of ? 2'b11 : 2'b00; 
                        comp_reg <= !is_of;                
                        
                       
                        wdata_reg <= {
                            add_bt[12] ? 12'd4095 : add_bt[11:0], 
                            add_gt[12] ? 12'd4095 : add_gt[11:0],
                            {4'b0, month_reg}, 
                            add_m[12]  ? 12'd4095 : add_m[11:0],
                            add_p[12]  ? 12'd4095 : add_p[11:0], 
                            {3'b0, day_reg}
                        };
                    end
                
                // ------------------------------------
                // Check Date (檢查日期)
                // ------------------------------------
                2'b10: begin 
                    err_reg  <= is_exp ? 2'b01 : 2'b00; // 判斷過期 No_Exp
                    comp_reg <= !is_exp;
                end
                
                default: begin
                    err_reg  <= 2'b00;
                    comp_reg <= 1'b0;
                end
            endcase
        end
    end
end

endmodule
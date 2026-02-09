`timescale 1ns/1ps


module prng (
    // Clock & Reset
    input               clk1,
    input               clk2,
    input               clk3,
    input               rst_n,
    // Input signals
    input               in_valid,
    input      [31:0]   seed,
    // Output signals
    output wire         out_valid,
    output wire [31:0]  rand_num
);

    // =====================================================
    // Internal Wires
    // =====================================================

    // CLK_1 to Handshake
    wire [31:0] hs_data_src;
    wire        hs_valid_src;
    wire        hs_done_src;  

    // Handshake to CLK_2
    wire [31:0] seed_data_dest;
    wire        seed_fire_dest; 

    // CLK_2 to FIFO
    wire        wr_en;
    wire [31:0] fifo_wr_data;
    wire        fifo_full;

    // FIFO to CLK_3
    wire        fifo_rd_en;
    wire [31:0] fifo_rd_data;
    wire        fifo_empty;

    // =====================================================
    // Module Instantiations
    // =====================================================

    // --- Module 1: ?? Seed from pattern (CLK1) ---
    CLK_1_MODULE u_clk1_mod (
        .clk1     (clk1),
        .rst_n    (rst_n),
        .in_valid (in_valid),
        .seed     (seed),
        

        .hs_valid (hs_valid_src), 
        .hs_data  (hs_data_src),
        .hs_done_src  (hs_done_src)   
    );

    handshake_sync #(.W(32)) u_handshake (
 
        .sclk      (clk1),
        .srst_n    (rst_n),
        .src_valid (hs_valid_src), 
        .src_data  (hs_data_src),  
        .hs_done_src  (hs_done_src),  

        // Destination Domain (CLK2)
        .dclk      (clk2),
        .drst_n    (rst_n),
        .dst_fire  (seed_fire_dest),
        .dst_data  (seed_data_dest) 
    );

   
    CLK_2_MODULE u_clk2_mod (
        .clk2         (clk2),
        .rst_n        (rst_n),
        
     
        .seed_fire    (seed_fire_dest),
        .seed_data    (seed_data_dest),
        
     
        .fifo_full    (fifo_full),
        .wr_en        (wr_en),
        .fifo_wr_data (fifo_wr_data)
    );


    async_fifo #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) u_fifo (
        // Write Domain (CLK2)
        .wr_clk   (clk2),
        .wr_rst_n (rst_n),
        .wr_en    (wr_en),
        .wr_data  (fifo_wr_data),
        .full     (fifo_full),

        // Read Domain (CLK3)
        .rd_clk   (clk3),
        .rd_rst_n (rst_n),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .empty    (fifo_empty)
    );

   
    CLK_3_MODULE u_clk3_mod (
        .clk3         (clk3),
        .rst_n        (rst_n),
        

        .fifo_empty   (fifo_empty),
        .fifo_rd_data (fifo_rd_data),
        .fifo_rd_en   (fifo_rd_en),
        
      
        .out_valid    (out_valid),
        .rand_num     (rand_num)
    );

endmodule


module CLK_1_MODULE (
    input              clk1,
    input              rst_n,
    input              in_valid,
    input       [31:0] seed,

    // to handshake_syn
    output reg         hs_valid,
    output reg  [31:0] hs_data,
    input              hs_done_src
);

    reg busy;

    always @(posedge clk1 or negedge rst_n) begin
        if (!rst_n) begin
            hs_valid <= 1'b0;
            hs_data  <= 32'd0;
            busy     <= 1'b0;
        end else begin
            
            if (in_valid && !busy) begin
                hs_valid <= 1'b1;
                hs_data  <= seed;
                busy     <= 1'b1;
            end
            
            else if (busy && hs_done_src) begin
                hs_valid <= 1'b0;
                busy     <= 1'b0;
            end
        end
    end

endmodule


module CLK_2_MODULE (
    input              clk2,
    input              rst_n,

    // from handshake_sync
    input              seed_fire, 
    input       [31:0] seed_data,

    // to FIFO_syn
    input              fifo_full,
    output reg         wr_en,
    output reg  [31:0] fifo_wr_data
);

    localparam WAIT_SEED = 1'b0;
    localparam GEN       = 1'b1;

    reg        state;
    reg [31:0] rand_reg;
    reg [7:0]  gen_cnt;

    // Xorshift Algorithm Logic
    wire [31:0] x1, x2, x3;
    assign x1 = rand_reg ^ (rand_reg << 13);
    assign x2 = x1       ^ (x1 >> 17);
    assign x3 = x2       ^ (x2 << 5);

    always @(posedge clk2 or negedge rst_n) begin
        if (!rst_n) begin
            state        <= WAIT_SEED;
            rand_reg     <= 32'd0;
            gen_cnt      <= 8'd0;
            wr_en        <= 1'b0;
            fifo_wr_data <= 32'd0;
        end else begin


            case (state)
                WAIT_SEED: begin
                    if (seed_fire) begin
                        wr_en <= 1'b0; 
                        rand_reg <= seed_data;
                        gen_cnt  <= 8'd0;
                        state    <= GEN;
                    end
                end

                GEN: begin
                    if (!fifo_full) begin
                        rand_reg     <= x3;
                        fifo_wr_data <= x3;
                        wr_en        <= 1'b1;
                        
                        if (gen_cnt == 8'd255) begin
                            state   <= WAIT_SEED;
                            gen_cnt <= 8'd0;
                        end else begin
                            gen_cnt <= gen_cnt + 1'b1;
                            state   <= GEN;
                        end
                    end
                end
            endcase
        end
    end
endmodule

module CLK_3_MODULE (
    input               clk3,
    input               rst_n,

    // FIFO Interface
    input               fifo_empty,
    input      [31:0]   fifo_rd_data,
    output reg          fifo_rd_en,

    // To Output
    output reg          out_valid,
    output reg [31:0]   rand_num
);


    localparam S_IDLE = 2'd0;
    localparam S_READ = 2'd1; 
    localparam S_WAIT = 2'd2; 
    localparam S_OUT  = 2'd3; 
    localparam S_DONE = 3'd4; 

    reg [2:0] state, next_state; 
    reg [8:0] out_cnt; 

    // -------------------------
    // State Register
    // -------------------------
    always @(posedge clk3 or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // -------------------------
    // Next-State Logic
    // -------------------------
    always @(*) begin
        case (state)
            S_IDLE: begin
                if (!fifo_empty) next_state = S_READ;
                else             next_state = S_IDLE;
            end

            S_READ: begin
                
                next_state = S_WAIT;
            end

            S_WAIT: begin
                
                next_state = S_OUT;
            end

            S_OUT: begin
                
                if (out_cnt == 9'd255) begin
                    next_state = S_DONE;
                end 
              
                else if (!fifo_empty) begin
                    next_state = S_READ; 
                end 
        
                else begin
                    next_state = S_IDLE; 
                end
            end

            S_DONE: begin
                next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // -------------------------
    // Output / Datapath
    // -------------------------
    always @(posedge clk3 or negedge rst_n) begin
        if (!rst_n) begin
            fifo_rd_en <= 1'b0;
            out_valid  <= 1'b0;
            rand_num   <= 32'd0;
            out_cnt    <= 9'd0;
        end else begin
   
            fifo_rd_en <= 1'b0;
            out_valid  <= 1'b0; 
            rand_num  <= 1'b0;
            

            case (state)
                S_IDLE: begin
            
                end

                S_READ: begin
                    fifo_rd_en <= 1'b1; 
                end

                S_WAIT: begin
                    fifo_rd_en <= 1'b0; 
                   
                end

                S_OUT: begin
              
                    out_valid <= 1'b1;
                    rand_num  <= fifo_rd_data;
                    out_cnt   <= out_cnt + 1'b1;
                end

                S_DONE: begin
                    out_cnt <= 9'd0;
                end
            endcase
        end
    end

endmodule


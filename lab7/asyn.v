
module async_fifo #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 8
)(
    
    input  wire                   wr_clk,
    input  wire                   wr_rst_n, 
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    output wire                   full,


    input  wire                   rd_clk,
    input  wire                   rd_rst_n, 
    input  wire                   rd_en,
    output reg  [DATA_WIDTH-1:0]  rd_data,
    output wire                   empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // ------------------------------------------------------------
    // Memory   w/r??‰è©²?ƒ½è¦æ˜¯å¯¦é??2?²åˆ¶ä½ç½®
    // ------------------------------------------------------------
    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];

    
    // ------------------------------------------------------------
    // Write pointer (binary & gray)
    // ------------------------------------------------------------
    reg  [ADDR_WIDTH:0] wr_ptr_bin;
    wire [ADDR_WIDTH:0] wr_ptr_bin_next;
    wire [ADDR_WIDTH:0] wr_ptr_gray;
    wire [ADDR_WIDTH:0] wr_ptr_gray_next;
    // ------------------------------------------------------------
    // Read pointer (binary & gray)
    // ------------------------------------------------------------
    reg  [ADDR_WIDTH:0] rd_ptr_bin;
    wire [ADDR_WIDTH:0] rd_ptr_bin_next;
    wire [ADDR_WIDTH:0] rd_ptr_gray;
    wire [ADDR_WIDTH:0] rd_ptr_gray_next;
    always @(posedge wr_clk) begin
        if (wr_en && !full)
            fifo_mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // ------------------------------------------------------------
    // Read data (registered)
    // ------------------------------------------------------------
    always @(posedge rd_clk) begin
        if (rd_en && !empty)
            rd_data <= fifo_mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    end


    assign wr_ptr_bin_next  = wr_ptr_bin + (wr_en && !full);
    // gray code conversion
    assign wr_ptr_gray      = wr_ptr_bin ^ (wr_ptr_bin >> 1);
    assign wr_ptr_gray_next = wr_ptr_bin_next ^ (wr_ptr_bin_next >> 1);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)
            wr_ptr_bin <= 0;
        else
            wr_ptr_bin <= wr_ptr_bin_next;
    end



    assign rd_ptr_bin_next  = rd_ptr_bin + (rd_en && !empty);
    // gray code conversion
    assign rd_ptr_gray      = rd_ptr_bin ^ (rd_ptr_bin >> 1);
    assign rd_ptr_gray_next = rd_ptr_bin_next ^ (rd_ptr_bin_next >> 1);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            rd_ptr_bin <= 0;
        else
            rd_ptr_bin <= rd_ptr_bin_next;
    end

    // ------------------------------------------------------------
    // Pointer Synchronizers 
    // ------------------------------------------------------------
    wire [ADDR_WIDTH:0] rd_ptr_gray_sync; 
    wire [ADDR_WIDTH:0] wr_ptr_gray_sync; 

    NDFF_BUS_syn #(
        .WIDTH(ADDR_WIDTH + 1)
    ) u_sync_rd2wr (
        .D     (rd_ptr_gray),      
        .Q     (rd_ptr_gray_sync), 
        .clk   (wr_clk),           
        .rst_n (wr_rst_n)          
    );


    NDFF_BUS_syn #(
        .WIDTH(ADDR_WIDTH + 1)
    ) u_sync_wr2rd (
        .D     (wr_ptr_gray),      
        .Q     (wr_ptr_gray_sync), 
        .clk   (rd_clk),           
        .rst_n (rd_rst_n)          
    );

    // ------------------------------------------------------------
    // Full / Empty Logic
    // ------------------------------------------------------------
    
    assign full = (wr_ptr_gray_next == 
                  {~rd_ptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1], 
                    rd_ptr_gray_sync[ADDR_WIDTH-2:0]});

    assign empty = (rd_ptr_gray_next == wr_ptr_gray_sync);

endmodule
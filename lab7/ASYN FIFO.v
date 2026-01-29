
module async_fifo #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 8
)(
    // Write domain
    input  wire                   wr_clk,
    input  wire                   wr_rst_n, // [已修正] 補上缺少的 Reset
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    output wire                   full,

    // Read domain
    input  wire                   rd_clk,
    input  wire                   rd_rst_n, // [已修正] 補上缺少的 Reset
    input  wire                   rd_en,
    output reg  [DATA_WIDTH-1:0]  rd_data,
    output wire                   empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // ------------------------------------------------------------
    // Memory
    // ------------------------------------------------------------
    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];

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

    // ------------------------------------------------------------
    // Write pointer (binary & gray)
    // ------------------------------------------------------------
    reg  [ADDR_WIDTH:0] wr_ptr_bin;
    wire [ADDR_WIDTH:0] wr_ptr_bin_next;
    wire [ADDR_WIDTH:0] wr_ptr_gray;
    wire [ADDR_WIDTH:0] wr_ptr_gray_next;

    assign wr_ptr_bin_next  = wr_ptr_bin + (wr_en && !full);
    assign wr_ptr_gray      = wr_ptr_bin ^ (wr_ptr_bin >> 1);
    assign wr_ptr_gray_next = wr_ptr_bin_next ^ (wr_ptr_bin_next >> 1);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)
            wr_ptr_bin <= 0;
        else
            wr_ptr_bin <= wr_ptr_bin_next;
    end

    // ------------------------------------------------------------
    // Read pointer (binary & gray)
    // ------------------------------------------------------------
    reg  [ADDR_WIDTH:0] rd_ptr_bin;
    wire [ADDR_WIDTH:0] rd_ptr_bin_next;
    wire [ADDR_WIDTH:0] rd_ptr_gray;
    wire [ADDR_WIDTH:0] rd_ptr_gray_next;

    assign rd_ptr_bin_next  = rd_ptr_bin + (rd_en && !empty);
    assign rd_ptr_gray      = rd_ptr_bin ^ (rd_ptr_bin >> 1);
    assign rd_ptr_gray_next = rd_ptr_bin_next ^ (rd_ptr_bin_next >> 1);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            rd_ptr_bin <= 0;
        else
            rd_ptr_bin <= rd_ptr_bin_next;
    end

    // ------------------------------------------------------------
    // Pointer Synchronizers (使用 NDFF_BUS_syn)
    // ------------------------------------------------------------
    wire [ADDR_WIDTH:0] rd_ptr_gray_sync; // 已同步到 Write Domain 的 Read Pointer
    wire [ADDR_WIDTH:0] wr_ptr_gray_sync; // 已同步到 Read Domain 的 Write Pointer

    // 1. 將 Read Pointer (Gray) 同步到 Write Domain
    // 使用提供的多位元同步器 
    NDFF_BUS_syn #(
        .WIDTH(ADDR_WIDTH + 1)
    ) u_sync_rd2wr (
        .D     (rd_ptr_gray),      // 來源：Read Domain 的 Gray 指標
        .Q     (rd_ptr_gray_sync), // 輸出：同步後的指標
        .clk   (wr_clk),           // 目的時脈：Write Clock
        .rst_n (wr_rst_n)          // 目的重置：Write Reset
    );

    // 2. 將 Write Pointer (Gray) 同步到 Read Domain
    // 使用提供的多位元同步器 
    NDFF_BUS_syn #(
        .WIDTH(ADDR_WIDTH + 1)
    ) u_sync_wr2rd (
        .D     (wr_ptr_gray),      // 來源：Write Domain 的 Gray 指標
        .Q     (wr_ptr_gray_sync), // 輸出：同步後的指標
        .clk   (rd_clk),           // 目的時脈：Read Clock
        .rst_n (rd_rst_n)          // 目的重置：Read Reset
    );

    // ------------------------------------------------------------
    // Full / Empty Logic
    // ------------------------------------------------------------
    
    // Full 判斷：在 Write Domain
    // 條件：Gray Code 的前兩位不同 (MSB!=, 2nd MSB!=)，其餘位相同
    // 這裡使用 wr_ptr_gray_next 是為了讓 Full 訊號提早反應 (Combinational output)，
    // 這樣在下一個 wr_clk edge 時 FIFO 就不會寫入溢出。
    assign full = (wr_ptr_gray_next == 
                  {~rd_ptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1], 
                    rd_ptr_gray_sync[ADDR_WIDTH-2:0]});

    // Empty 判斷：在 Read Domain
    // 條件：Gray Code 完全相同
    // 同樣使用 rd_ptr_gray_next 來做立即判斷
    assign empty = (rd_ptr_gray_next == wr_ptr_gray_sync);

endmodule
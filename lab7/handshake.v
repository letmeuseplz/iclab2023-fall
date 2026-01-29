module handshake_sync #(
    parameter W = 32
)(
    // source domain (clk1)
    input              sclk,
    input              srst_n,
    input              src_valid,
    input  [W-1:0]     src_data,
    output             src_done,

    // destination domain (clk2)
    input              dclk,
    input              drst_n,
    output reg         dst_fire,
    output reg [W-1:0] dst_data
);

    // --------------------------------------------------
    // Signal Declarations
    // --------------------------------------------------
    reg sreq;
    reg dack;
    
    // Outputs from NDFF synchronizers
    wire sreq_sync; // sreq synchronized to dclk domain
    wire dack_sync; // dack synchronized to sclk domain

    // --------------------------------------------------
    // NDFF Synchronizers
    // --------------------------------------------------
    
    // Synchronize sreq from Source(clk1) to Destination(clk2)
    NDFF_syn U_NDFF_REQ (
        .D(sreq), 
        .Q(sreq_sync), 
        .clk(dclk), 
        .rst_n(drst_n)
    );

    // Synchronize dack from Destination(clk2) to Source(clk1)
    NDFF_syn U_NDFF_ACK (
        .D(dack), 
        .Q(dack_sync), 
        .clk(sclk), 
        .rst_n(srst_n)
    );

    // --------------------------------------------------
    // Source FSM (clk1)
    // --------------------------------------------------
    reg src_busy;

    always @(posedge sclk or negedge srst_n) begin
        if (!srst_n) begin
            sreq     <= 1'b0;
            src_busy <= 1'b0;
        end else begin
            // [修正重點] 必須確認 dack_sync 為低 (Idle) 才能發起新請求
            // 這是為了滿足 4-Phase Handshake 的安全性
            if (!src_busy && src_valid && !dack_sync) begin
                sreq     <= 1'b1;
                src_busy <= 1'b1;
            end
            else if (src_busy && dack_sync) begin // Wait for ACK to assert
                sreq     <= 1'b0; // De-assert Request
                src_busy <= 1'b0; // Transaction Done
            end
        end
    end

    // 當 busy 為高且收到 ACK 時，表示單次傳輸完成
    assign src_done = src_busy && dack_sync;

    // --------------------------------------------------
    // Destination FSM (clk2)
    // --------------------------------------------------
    reg sreq_prev;

    always @(posedge dclk or negedge drst_n) begin
        if (!drst_n) begin
            dst_fire  <= 1'b0;
            dack      <= 1'b0;
            dst_data  <= {W{1'b0}};
            sreq_prev <= 1'b0;
        end else begin
            dst_fire <= 1'b0; // Default pulse low
            
            // Rising edge detection on the synchronized request signal
            if (sreq_sync && !sreq_prev) begin
                dst_fire <= 1'b1;
                dst_data <= src_data; // Capture Data
                dack     <= 1'b1;     // Assert Acknowledge
            end
            else if (!sreq_sync) begin
                dack     <= 1'b0;     // Request dropped, drop Acknowledge
            end

            sreq_prev <= sreq_sync;
        end
    end

endmodule
module handshake_sync #(
    parameter W = 32
)(
    // source domain 
    input              sclk,
    input              srst_n,
    input              src_valid,
    input  [W-1:0]     src_data,
    output            hs_done_src, //�蝯� MODULE 1 ��� done 靽∟��

    // destination domain 
    input              dclk,
    input              drst_n,
    output reg         dst_fire,   //�蝯危ODULE 2��� Pulse
    output reg [W-1:0] dst_data
);

    // --------------------------------------------------
    // Signal Declarations
    // --------------------------------------------------
    reg sreq;
    reg dack;
    
    // Outputs from NDFF synchronizers
    wire sreq_sync; 
    wire dack_sync; 

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

            if (!src_busy && src_valid && !dack_sync) begin
                sreq     <= 1'b1;
                src_busy <= 1'b1;
            end
            else if (src_busy && dack_sync) begin 
                sreq     <= 1'b0; 
                src_busy <= 1'b0; 
            end
        end
    end

   
    assign hs_done_src = src_busy && dack_sync;

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
            dst_fire <= 1'b0;  
            
   
            if (sreq_sync && !sreq_prev) begin
                dst_fire <= 1'b1;
                dst_data <= src_data; 
                dack     <= 1'b1;     
            end
            else if (!sreq_sync) begin
                dack     <= 1'b0;
                dst_data <= dst_data;     
            end

            sreq_prev <= sreq_sync;
        end
    end

endmodule
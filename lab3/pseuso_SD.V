`timescale 1ns/1ps

module pseudo_SD (
    input        clk,



    input        MOSI,     // Master -> Slave
    output reg   MISO      // Slave -> Master
);

    // ------------------------------
    // 模擬 SD 記憶體 (64-bit block, 65536 entries)
    // ------------------------------
    reg [63:0] SD [0:65535];

    // Command 收集
    reg [47:0] cmd_shift;
    reg [5:0]  cmd_index;
    reg [31:0] addr;
    reg [6:0]  crc_recv, crc_calc;
    reg start_bit, tx_bit, end_bit;

    // CRC 暫存
    reg [15:0] crc16_val;

    // CRC16 init value (可改 16'h0000 / 16'hFFFF)
    parameter CRC16_INIT = 16'hFFFF;

    // ------------------------------
    // FAIL 顯示 task
    // ------------------------------
    task command_fail_task;
        input [127:0] msg;
        begin
            $display("************************************************************");
            $display("*                          FAIL!                            *");    
            $display("*                      SPEC SD FAIL                         *");
            $display("  Reason: %s", msg);
            $display("************************************************************");
            repeat(2) @(posedge clk);
            $finish;
        end
    endtask

    // ------------------------------
    // CRC7 function (x^7 + x^3 + 1, poly=0x09)
    // ------------------------------
    function [6:0] CRC7;
        input [39:0] data;   // 40 bits
        integer i;
        reg [6:0] crc;
        reg data_in, data_out;
        begin
            crc = 7'b0;
            for (i=39; i>=0; i=i-1) begin
                data_in  = data[i];
                data_out = crc[6];
                crc      = crc << 1;
                if (data_in ^ data_out)
                    crc = crc ^ 7'h09;
            end
            CRC7 = crc;
        end
    endfunction

    // ------------------------------
    // CRC16-CCITT function (poly=0x1021)
    // ------------------------------
    function [15:0] CRC16_CCITT;
        input [63:0] data;   // 64 bits block
        integer i;
        reg [15:0] crc;
        reg bit_in;
        begin
            crc = CRC16_INIT;
            for (i=63; i>=0; i=i-1) begin
                bit_in = data[i] ^ crc[15];
                crc    = {crc[14:0], 1'b0};
                if (bit_in)
                    crc = crc ^ 16'h1021;
            end
            CRC16_CCITT = crc;
        end
    endfunction

    // ------------------------------
    // 延遲任務 (模擬 bus idle, 整數倍 clk cycle)
    // ------------------------------
    task delay_task;
        input integer unit_cycles;
        integer i;
        begin
            for (i=0; i<unit_cycles; i=i+1) @(posedge clk);
        end
    endtask

    // ------------------------------
    // 收 Command (48 bits)
    // ------------------------------
    task recv_cmd;
        integer i;
        begin
            cmd_shift = 48'd0;
            for (i=0; i<48; i=i+1) begin
                @(posedge SCLK);
                cmd_shift = {cmd_shift[46:0], MOSI};
            end
        end
    endtask

    // ------------------------------
    // 傳送 Response (8 bits)
    // ------------------------------
    task send_response;
        input [7:0] resp;
        integer i;
        begin
            delay_task(8); // 模擬必須的延遲 (8 cycles)
            for (i=7; i>=0; i=i-1) begin
                @(posedge SCLK);
                MISO = resp[i];
            end
        end
    endtask

    // ------------------------------
    // 傳送 Data Block (Start token + Data + CRC16)
    // ------------------------------
    task send_data_block;
        input [63:0] data;
        integer i;
        reg [7:0] token;

        token = 8'hFE;
        begin
            delay_task(32); // 模擬必須的延遲 (32 cycles)

            // Start Token 0xFE

            for (i=7; i>=0; i=i-1) begin
                @(posedge SCLK);
                MISO = token[i];
            end

            // Data block (64 bits)
            for (i=63; i>=0; i=i-1) begin
                @(posedge SCLK);
                MISO = data[i];
            end

            // CRC16
            crc16_val = CRC16_CCITT(data);
            for (i=15; i>=0; i=i-1) begin
                @(posedge SCLK);
                MISO = crc16_val[i];
            end
        end
    endtask

    // ------------------------------
    // 接收 Data Block (write 用)
    // ------------------------------
    task recv_data_block;
        output [63:0] data;
        integer i;
        reg [7:0] token;
        reg [15:0] crc_recv, crc_calc;
        begin
            // Start Token
            token = 8'd0;
            for (i=7; i>=0; i=i-1) begin
                @(posedge SCLK);
                token[i] = MOSI;
            end
            if (token !== 8'hFE) command_fail_task("Data start token incorrect");

            // Data block
            data = 64'd0;
            for (i=63; i>=0; i=i-1) begin
                @(posedge SCLK);
                data[i] = MOSI;
            end

            // CRC16
            crc_recv = 16'd0;
            for (i=15; i>=0; i=i-1) begin
                @(posedge SCLK);
                crc_recv[i] = MOSI;
            end

            // CRC check
            crc_calc = CRC16_CCITT(data);
            if (crc_recv !== crc_calc)
                command_fail_task("CRC16 check failed (write)");
        end
    endtask

    // ------------------------------
    // 主流程：等 command 收滿後檢查
    // ------------------------------
    task handle_cmd;
        reg [63:0] data_buf;
        begin
            recv_cmd();

            // 拆 command 格式
            start_bit = cmd_shift[47];
            tx_bit    = cmd_shift[46];
            cmd_index = cmd_shift[45:40];
            addr      = cmd_shift[39:8];
            crc_recv  = cmd_shift[7:1];
            end_bit   = cmd_shift[0];

            // Spec check 1: 格式
            if (start_bit !== 1'b0 || tx_bit !== 1'b1 || end_bit !== 1'b1)
                command_fail_task("Command format incorrect (start/tx/end bit)");

            // Spec check 2: 地址範圍
            if (addr > 65535)
                command_fail_task("Address out of range (>65535)");

            // Spec check 3: CRC7
            crc_calc = CRC7(cmd_shift[47:8]);
            if (crc_recv !== crc_calc)
                command_fail_task("CRC7 check failed");

            // Spec check 4: 支援的 command
            if (cmd_index == 6'd17) begin
                // Read block
                send_response(8'h00);
                data_buf = SD[addr];
                send_data_block(data_buf);
            end
            else if (cmd_index == 6'd24) begin
                // Write block
                send_response(8'h00);
                recv_data_block(data_buf);
                SD[addr] = data_buf;
            end
            else begin
                command_fail_task("Unsupported command (only CMD17, CMD24 supported)");
            end
        end
    endtask

    // ------------------------------
    // 自動啟動流程
    // ------------------------------
    initial begin
        forever begin
            @(negedge CS_n);  // host 拉低片選，開始交易
            handle_cmd();
        end
    end

endmodule

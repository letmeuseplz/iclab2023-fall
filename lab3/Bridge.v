`timescale 1ns/1ps
module BRIDGE (
    input  wire        clk,
    input  wire        rst_n,

    // control
    input  wire        in_valid,
    input  wire        direction,     // 0 = DRAM -> SD (CMD24), 1 = SD -> DRAM (CMD17)
    input  wire [12:0] addr_dram,
    input  wire [15:0] addr_sd,

    output reg         out_valid,
    output reg  [7:0]  out_data,

    // pseudo_DRAM AXI-like
    output reg         AR_VALID,
    output reg  [12:0] AR_ADDR,
    input  wire        AR_READY,
    input  wire        R_VALID,
    input  wire [63:0] R_DATA,
    output reg         R_READY,

    output reg         AW_VALID,
    output reg  [12:0] AW_ADDR,
    input  wire        AW_READY,
    output reg         W_VALID,
    output reg  [63:0] W_DATA,
    input  wire        W_READY,
    input  wire        B_VALID,
    input  wire [1:0]  B_RESP,
    output reg         B_READY,

    // pseudo_SD SPI-like

    output reg         MOSI,
    input  wire        MISO
);

    // ====================================================
    // states
    // ====================================================
    localparam IDLE            = 6'd0,
               D0_DRAM_REQ     = 6'd1,
               D0_DRAM_WAIT    = 6'd2,
               D0_PREP_CMD24   = 6'd3,
               D0_SHIFT_CMD    = 6'd4,
               D0_WAIT_R1      = 6'd5,
               D0_WAIT_GAP     = 6'd6,
               D0_SEND_TOKEN   = 6'd7,
               D0_SEND_DATA    = 6'd8,
               D0_SEND_CRC16   = 6'd9,
               D0_DATA_RESP    = 6'd10,
               D0_BUSY_WAIT    = 6'd11,
               D1_PREP_CMD17   = 6'd12,
               D1_SHIFT_CMD    = 6'd13,
               D1_WAIT_R1      = 6'd14,
               D1_WAIT_TOKEN   = 6'd15,
               D1_RECV_DATA    = 6'd16,
               D1_RECV_CRC16   = 6'd17,
               D1_WR_AW        = 6'd18,  // address handshake
               D1_WR_W         = 6'd19,  // data handshake (and assert B_READY here as requested)
               D1_WR_B         = 6'd20,  // wait for B_VALID & handshake
               DONE            = 6'd21,
               OUT_DATA        = 6'd22;

    reg [5:0] state, next_state;

    // ====================================================
    // registers / next_*
    // ====================================================
    reg [7:0]  cmd0, cmd1, cmd2, cmd3, cmd4, cmd5;
    reg [2:0]  byte_cnt, next_byte_cnt;
    reg [2:0]  bit_in_byte, next_bit_in_byte;
    reg [7:0]  shift_byte, next_shift_byte;

    reg [63:0] data_buf, next_data_buf;
    reg [63:0] shift_data, next_shift_data;
    reg [63:0] recv_data, next_recv_data;
    reg [15:0] crc16_reg, next_crc16_reg;
    reg [15:0] crc16_check, next_crc16_check;
    reg [6:0]  crc7_val;

    reg [8:0]  bit_cnt, next_bit_cnt;
    reg [7:0]  r1_shift, next_r1_shift;
    reg [7:0]  token_shift, next_token_shift;
    reg [15:0] crc16_recv, next_crc16_recv;

    reg [63:0] result_data, next_result_data;
    reg [2:0]  out_cnt, next_out_cnt;

    // latch registers (if needed)
    reg [12:0] lat_aw_addr, next_lat_aw_addr;
    reg [63:0] lat_w_data,  next_lat_w_data;

    // next outputs
    reg        next_out_valid;
    reg [7:0]  next_out_data;
    reg        next_AR_VALID;
    reg [12:0] next_AR_ADDR;
    reg        next_R_READY;
    reg        next_AW_VALID;
    reg [12:0] next_AW_ADDR;
    reg        next_W_VALID;
    reg [63:0] next_W_DATA;
    reg        next_B_READY;
    reg        next_CS_n;
    reg        next_MOSI;

    // helper
    wire afinish = (bit_in_byte == 3'd0);

    // ====================================================
    // CRC functions (Verilog-2001-compatible)
    // ====================================================
    function [6:0] crc7_spi;
        input [39:0] data;
        integer i;
        reg [6:0] crc;
        reg bit;
        begin
            crc = 7'd0;
            for (i = 39; i >= 0; i = i - 1) begin
                bit = data[i] ^ crc[6];
                crc = {crc[5:0], 1'b0};
                if (bit) crc = crc ^ 7'h09;
            end
            crc7_spi = crc;
        end
    endfunction

    function [15:0] crc16_ccitt;
        input [63:0] data;
        integer i;
        reg [15:0] crc;
        reg d;
        begin
            crc = 16'h0000;
            for (i = 63; i >= 0; i = i - 1) begin
                d = data[i] ^ crc[15];
                crc = {crc[14:0], 1'b0};
                if (d) crc = crc ^ 16'h1021;
            end
            crc16_ccitt = crc;
        end
    endfunction

    // ====================================================
    // 1) state register (sequential)
    // ====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    // ====================================================
    // 2) next-state logic (combinational)
    // ====================================================
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (in_valid) begin
                    if (direction == 1'b0) next_state = D0_DRAM_REQ;
                    else                   next_state = D1_PREP_CMD17;
                end
            end

            // DRAM -> SD (CMD24)
            D0_DRAM_REQ:   if (AR_READY)     next_state = D0_DRAM_WAIT;
            D0_DRAM_WAIT:  if (R_VALID)      next_state = D0_PREP_CMD24;
            D0_PREP_CMD24:                   next_state = D0_SHIFT_CMD;
            D0_SHIFT_CMD:  if (byte_cnt==3'd5 && afinish) next_state = D0_WAIT_R1;
            D0_WAIT_R1:    if ({r1_shift[6:0], MISO} == 8'h00 && afinish) next_state = D0_WAIT_GAP;
            D0_WAIT_GAP:   if (afinish)      next_state = D0_SEND_TOKEN;
            D0_SEND_TOKEN: if (afinish)      next_state = D0_SEND_DATA;
            D0_SEND_DATA:  if (bit_cnt == 9'd63) next_state = D0_SEND_CRC16;
            D0_SEND_CRC16: if (bit_cnt == 9'd15) next_state = D0_DATA_RESP;
            D0_DATA_RESP:  if (afinish) begin
                               if ({r1_shift[6:0], MISO} == 8'b00000101) next_state = D0_BUSY_WAIT;
                               else                                      next_state = DONE;
                           end
            D0_BUSY_WAIT:  if ({r1_shift[6:0], MISO} == 8'hFF && afinish) next_state = DONE;

            // SD -> DRAM (CMD17)
            D1_PREP_CMD17: next_state = D1_SHIFT_CMD;
            D1_SHIFT_CMD:  if (byte_cnt==3'd5 && afinish) next_state = D1_WAIT_R1;
            D1_WAIT_R1:    if ({r1_shift[6:0], MISO} == 8'h00 && afinish) next_state = D1_WAIT_TOKEN;
            D1_WAIT_TOKEN: if ({token_shift[6:0], MISO} == 8'hFE && afinish) next_state = D1_RECV_DATA;
            D1_RECV_DATA:  if (bit_cnt == 9'd63) next_state = D1_RECV_CRC16;
            D1_RECV_CRC16: if (bit_cnt == 9'd15) begin
                               if (crc16_check == crc16_recv) next_state = D1_WR_AW;
                               else                           next_state = DONE;
                           end

            // AXI write splitted handshake
            D1_WR_AW:      if (AW_READY)     next_state = D1_WR_W;
            D1_WR_W:       if (W_READY)      next_state = D1_WR_B;
            // require both B_VALID & B_READY to be true to consider done (handshake)
            D1_WR_B:       if (B_VALID && B_READY) next_state = DONE;

            DONE:          next_state = OUT_DATA;
            OUT_DATA:      if (out_cnt == 3'd7) next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end

    // ====================================================
    // 3) outputs & next-register-values (combinational)
    //    set defaults and override per-state
    // ====================================================
    always @(*) begin
        // default next values
        next_out_valid   = 1'b0;
        next_out_data    = 8'd0;

        next_AR_VALID    = 1'b0;
        next_AR_ADDR     = 13'd0;
        next_R_READY     = 1'b0;

        next_AW_VALID    = 1'b0;
        next_AW_ADDR     = 13'd0;
        next_W_VALID     = 1'b0;
        next_W_DATA      = 64'd0;
        next_B_READY     = 1'b0;

        next_CS_n        = 1'b1;
        next_MOSI        = 1'b1;

        next_byte_cnt    = byte_cnt;
        next_bit_in_byte = bit_in_byte;
        next_shift_byte  = shift_byte;

        next_bit_cnt     = bit_cnt;
        next_shift_data  = shift_data;
        next_recv_data   = recv_data;

        next_r1_shift    = r1_shift;
        next_token_shift = token_shift;

        next_crc16_reg   = crc16_reg;
        next_crc16_check = crc16_check;
        next_crc16_recv  = crc16_recv;

        next_data_buf    = data_buf;
        next_result_data = result_data;
        next_out_cnt     = out_cnt;

        next_lat_aw_addr = lat_aw_addr;
        next_lat_w_data  = lat_w_data;

        // state-specific overrides
        case (state)
            IDLE: begin
                // nothing asserted by default; if host gives new pattern, assert AR_VALID for D0
                if (in_valid && direction == 1'b0) begin
                    next_AR_VALID = 1'b1;
                    next_AR_ADDR  = addr_dram;
                end
                next_CS_n = 1'b1;
                next_MOSI = 1'b1;
            end

            // ---------------- D0 (DRAM->SD) ----------------
            D0_DRAM_REQ: begin
                next_AR_VALID = 1'b1;
                next_AR_ADDR  = AR_ADDR; // keep current until AR_READY
                next_CS_n     = 1'b0;
            end

            D0_DRAM_WAIT: begin
                next_R_READY = 1'b1;
                next_CS_n    = 1'b0;
                if (R_VALID) begin
                    next_data_buf    = R_DATA;
                    next_shift_data  = R_DATA;
                    next_crc16_check = crc16_ccitt(R_DATA);
                end
            end

            D0_PREP_CMD24: begin
                next_CS_n = 1'b0;
                // CMD24: start+transmission + cmd + arg(32) + crc7 + endbit
                cmd0 = 8'h58; // 0x40 | 24 = 0x58
                // place addr_sd into upper 16 bits of 32-bit argument (per prior discussion)
                cmd1 = addr_sd[15:8];
                cmd2 = addr_sd[7:0];
                cmd3 = 8'h00;
                cmd4 = 8'h00;
                crc7_val = crc7_spi({cmd0, cmd1, cmd2, cmd3, cmd4});
                cmd5 = {crc7_val, 1'b1};
                next_shift_byte  = cmd0;
                next_byte_cnt    = 3'd0;
                next_bit_in_byte = 3'd7;
            end

            D0_SHIFT_CMD: begin
                next_CS_n = 1'b0;
                next_MOSI = shift_byte[bit_in_byte];
                if (bit_in_byte == 3'd0) begin
                    next_byte_cnt = byte_cnt + 3'd1;
                    case (byte_cnt)
                        3'd0: next_shift_byte = cmd1;
                        3'd1: next_shift_byte = cmd2;
                        3'd2: next_shift_byte = cmd3;
                        3'd3: next_shift_byte = cmd4;
                        3'd4: next_shift_byte = cmd5;
                        default: next_shift_byte = 8'hFF;
                    endcase
                    next_bit_in_byte = 3'd7;
                end else begin
                    next_bit_in_byte = bit_in_byte - 3'd1;
                end
            end

            D0_WAIT_R1: begin
                next_CS_n = 1'b0;
                next_r1_shift = {r1_shift[6:0], MISO};
                next_bit_in_byte = (bit_in_byte == 3'd0) ? 3'd7 : (bit_in_byte - 3'd1);
            end

            D0_WAIT_GAP: begin
                next_CS_n = 1'b0;
                if (bit_in_byte == 3'd0) begin
                    next_shift_byte   = 8'hFE;
                    next_bit_in_byte  = 3'd7;
                end else begin
                    next_bit_in_byte = bit_in_byte - 3'd1;
                end
            end

            D0_SEND_TOKEN: begin
                next_CS_n = 1'b0;
                next_MOSI = shift_byte[bit_in_byte];
                next_bit_in_byte = (bit_in_byte == 3'd0) ? 3'd7 : (bit_in_byte - 3'd1);
            end

            D0_SEND_DATA: begin
                next_CS_n      = 1'b0;
                next_MOSI      = shift_data[63];
                next_shift_data= {shift_data[62:0], 1'b0};
                next_bit_cnt   = bit_cnt + 9'd1;
            end

            D0_SEND_CRC16: begin
                next_CS_n        = 1'b0;
                next_MOSI        = crc16_check[15];
                next_crc16_check = {crc16_check[14:0], 1'b0};
                next_bit_cnt     = bit_cnt + 9'd1;
            end

            D0_DATA_RESP: begin
                next_CS_n     = 1'b0;
                next_r1_shift = {r1_shift[6:0], MISO};
                next_bit_in_byte = (bit_in_byte == 3'd0) ? 3'd7 : (bit_in_byte - 3'd1);
            end

            D0_BUSY_WAIT: begin
                next_CS_n     = 1'b0;
                next_r1_shift = {r1_shift[6:0], MISO};
                next_bit_in_byte = (bit_in_byte == 3'd0) ? 3'd7 : (bit_in_byte - 3'd1);
            end

            // ---------------- D1 (SD->DRAM) ----------------
            D1_PREP_CMD17: begin
                next_CS_n = 1'b0;
                cmd0 = 8'h51; // 0x40 | 17 = 0x51
                cmd1 = addr_sd[15:8];
                cmd2 = addr_sd[7:0];
                cmd3 = 8'h00;
                cmd4 = 8'h00;
                crc7_val = crc7_spi({cmd0, cmd1, cmd2, cmd3, cmd4});
                cmd5 = {crc7_val, 1'b1};
                next_shift_byte  = cmd0;
                next_byte_cnt    = 3'd0;
                next_bit_in_byte = 3'd7;
            end

            D1_SHIFT_CMD: begin
                next_CS_n = 1'b0;
                next_MOSI = shift_byte[bit_in_byte];
                if (bit_in_byte == 3'd0) begin
                    next_byte_cnt = byte_cnt + 3'd1;
                    case (byte_cnt)
                        3'd0: next_shift_byte = cmd1;
                        3'd1: next_shift_byte = cmd2;
                        3'd2: next_shift_byte = cmd3;
                        3'd3: next_shift_byte = cmd4;
                        3'd4: next_shift_byte = cmd5;
                        default: next_shift_byte = 8'hFF;
                    endcase
                    next_bit_in_byte = 3'd7;
                end else begin
                    next_bit_in_byte = bit_in_byte - 3'd1;
                end
            end

            D1_WAIT_R1: begin
                next_CS_n = 1'b0;
                next_r1_shift = {r1_shift[6:0], MISO};
                next_bit_in_byte = (bit_in_byte == 3'd0) ? 3'd7 : (bit_in_byte - 3'd1);
            end

            D1_WAIT_TOKEN: begin
                next_CS_n = 1'b0;
                next_token_shift = {token_shift[6:0], MISO};
                next_bit_in_byte = (bit_in_byte == 3'd0) ? 3'd7 : (bit_in_byte - 3'd1);
            end

            D1_RECV_DATA: begin
                next_CS_n = 1'b0;
                next_recv_data = {recv_data[62:0], MISO};
                next_bit_cnt = bit_cnt + 9'd1;
            end

            D1_RECV_CRC16: begin
                next_CS_n = 1'b0;
                next_crc16_recv = {crc16_recv[14:0], MISO};
                next_bit_cnt = bit_cnt + 9'd1;
                if (bit_cnt == 9'd15) begin
                    next_crc16_check = crc16_ccitt(recv_data);
                end
            end

            // ---------------- AXI write: AW ----------------
            D1_WR_AW: begin
                // latch sources to local regs (optional)
                next_lat_aw_addr = addr_dram;
                next_lat_w_data  = recv_data;
                // assert AW_VALID and present AW_ADDR immediately (addr must be stable while AW_VALID)
                next_AW_VALID = 1'b1;
                next_AW_ADDR  = addr_dram;
                // keep B_READY low here; user requested B_READY to be asserted in AW_READY's next state
            end

            // ---------------- AXI write: W ----------------
            D1_WR_W: begin
                // present write data and assert W_VALID
                next_W_VALID = 1'b1;
                next_W_DATA  = recv_data; // use lat_w_data if you prefer
                // per your request: assert B_READY here (this is the state after AW_READY)
                next_B_READY = 1'b1;
            end

            // ---------------- AXI write: B ----------------
            D1_WR_B: begin
                // keep B_READY asserted while waiting response
                next_B_READY = 1'b1;
                // do not change AW_VALID/W_VALID here; they should have been turned off after handshake by the interface
            end

            // ---------------- DONE / OUT ----------------
            DONE: begin
                next_result_data = (direction == 1'b0) ? data_buf : recv_data;
                next_out_cnt     = 3'd0;
            end

            OUT_DATA: begin
                next_out_valid = 1'b1;
                // Verilog-2001 style slicing (no -: part-select)
                case (out_cnt)
                    3'd0: next_out_data = result_data[63:56];
                    3'd1: next_out_data = result_data[55:48];
                    3'd2: next_out_data = result_data[47:40];
                    3'd3: next_out_data = result_data[39:32];
                    3'd4: next_out_data = result_data[31:24];
                    3'd5: next_out_data = result_data[23:16];
                    3'd6: next_out_data = result_data[15: 8];
                    3'd7: next_out_data = result_data[ 7: 0];
                    default: next_out_data = 8'h00;
                endcase
                next_out_cnt = out_cnt + 3'd1;
            end

            default: begin
                // keep defaults
            end
        endcase
    end

    // ====================================================
    // 4) sequential: update registers on clock edge
    // ====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reset all stateful regs
            state <= IDLE;

            out_valid <= 1'b0;
            out_data  <= 8'd0;

            AR_VALID <= 1'b0;
            AR_ADDR  <= 13'd0;
            R_READY  <= 1'b0;

            AW_VALID <= 1'b0;
            AW_ADDR  <= 13'd0;
            W_VALID  <= 1'b0;
            W_DATA   <= 64'd0;
            B_READY  <= 1'b0;

            CS_n <= 1'b1;
            MOSI <= 1'b1;

            byte_cnt    <= 3'd0;
            bit_in_byte <= 3'd7;
            shift_byte  <= 8'hFF;

            data_buf    <= 64'd0;
            shift_data  <= 64'd0;
            recv_data   <= 64'd0;

            crc16_reg   <= 16'd0;
            crc16_check <= 16'd0;
            crc16_recv  <= 16'd0;

            bit_cnt  <= 9'd0;
            r1_shift <= 8'hFF;
            token_shift <= 8'hFF;

            result_data <= 64'd0;
            out_cnt     <= 3'd0;

            lat_aw_addr <= 13'd0;
            lat_w_data  <= 64'd0;
        end else begin
            // update outputs / stateful regs from next_*
            out_valid <= next_out_valid;
            out_data  <= next_out_data;

            AR_VALID <= next_AR_VALID;
            AR_ADDR  <= next_AR_ADDR;
            R_READY  <= next_R_READY;

            AW_VALID <= next_AW_VALID;
            AW_ADDR  <= next_AW_ADDR;
            W_VALID  <= next_W_VALID;
            W_DATA   <= next_W_DATA;
            B_READY  <= next_B_READY;

            CS_n <= next_CS_n;
            MOSI <= next_MOSI;

            byte_cnt    <= next_byte_cnt;
            bit_in_byte <= next_bit_in_byte;
            shift_byte  <= next_shift_byte;

            data_buf    <= next_data_buf;
            shift_data  <= next_shift_data;
            recv_data   <= next_recv_data;

            crc16_reg   <= next_crc16_reg;
            crc16_check <= next_crc16_check;
            crc16_recv  <= next_crc16_recv;

            bit_cnt  <= next_bit_cnt;
            r1_shift <= next_r1_shift;
            token_shift <= next_token_shift;

            result_data <= next_result_data;
            out_cnt     <= next_out_cnt;

            lat_aw_addr <= next_lat_aw_addr;
            lat_w_data  <= next_lat_w_data;
        end
    end

endmodule

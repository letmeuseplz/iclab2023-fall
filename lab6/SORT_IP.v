// =============================================================
// COMP2: comparator
// larger weight first
// if weight equal, smaller char first
// =============================================================
module COMP2 #(
    parameter W_W = 7
)(
    input  [3:0]     A_char,
    input  [W_W-1:0] A_w,
    input  [3:0]     B_char,
    input  [W_W-1:0] B_w,

    output [3:0]     O0_char,
    output [W_W-1:0] O0_w,
    output [3:0]     O1_char,
    output [W_W-1:0] O1_w
);

    wire do_swap;

    assign do_swap = (A_w < B_w) ||
                     (A_w == B_w && A_char > B_char);

    assign O0_char = do_swap ? B_char : A_char;
    assign O0_w    = do_swap ? B_w    : A_w;

    assign O1_char = do_swap ? A_char : B_char;
    assign O1_w    = do_swap ? A_w    : B_w;

endmodule

// =============================================================
// SORT_IP : Odd-Even Sort Network (parameterized weight width)
// =============================================================
module SORT_IP #(
    parameter IP_WIDTH = 8,
    parameter WEIGHT_W = 7
)(
    input  [IP_WIDTH*4-1:0]        IN_character,
    input  [IP_WIDTH*WEIGHT_W-1:0] IN_weight,
    output [IP_WIDTH*4-1:0]        OUT_character
);

    // number of passes for odd-even sort
    localparam PASSES = IP_WIDTH;
    localparam STAGES = PASSES + 1;

    // stage storage
    wire [STAGES*IP_WIDTH*4-1:0]        S_CHAR;
    wire [STAGES*IP_WIDTH*WEIGHT_W-1:0] S_W;

    genvar s, i;

    // ----------------------------------------------------------
    // UNPACK input -> stage 0
    // ----------------------------------------------------------
    generate
        for (i = 0; i < IP_WIDTH; i = i + 1) begin : UNPACK
            assign S_CHAR[(i*4) +: 4] =
                   IN_character[((IP_WIDTH-1-i)*4) +: 4];

            assign S_W[(i*WEIGHT_W) +: WEIGHT_W] =
                   IN_weight[((IP_WIDTH-1-i)*WEIGHT_W) +: WEIGHT_W];
        end
    endgenerate

    // ----------------------------------------------------------
    // SORT stages
    // ----------------------------------------------------------
    generate
        for (s = 0; s < STAGES-1; s = s + 1) begin : STAGE_LOOP

            // ---------------- EVEN stage ----------------
            if ((s & 1) == 0) begin : EVEN_STAGE
                for (i = 0; i < IP_WIDTH; i = i + 2) begin : EVEN_PAIR
                    if (i+1 < IP_WIDTH) begin
                        COMP2 #(.W_W(WEIGHT_W)) u_cmp (
                            .A_char(S_CHAR[((s*IP_WIDTH+i)*4) +: 4]),
                            .A_w   (S_W   [((s*IP_WIDTH+i)*WEIGHT_W) +: WEIGHT_W]),
                            .B_char(S_CHAR[((s*IP_WIDTH+i+1)*4) +: 4]),
                            .B_w   (S_W   [((s*IP_WIDTH+i+1)*WEIGHT_W) +: WEIGHT_W]),

                            .O0_char(S_CHAR[(((s+1)*IP_WIDTH+i)*4) +: 4]),
                            .O0_w   (S_W   [(((s+1)*IP_WIDTH+i)*WEIGHT_W) +: WEIGHT_W]),
                            .O1_char(S_CHAR[(((s+1)*IP_WIDTH+i+1)*4) +: 4]),
                            .O1_w   (S_W   [(((s+1)*IP_WIDTH+i+1)*WEIGHT_W) +: WEIGHT_W])
                        );
                    end
                    else begin
                        assign S_CHAR[(((s+1)*IP_WIDTH+i)*4) +: 4] =
                               S_CHAR[((s*IP_WIDTH+i)*4) +: 4];
                        assign S_W[(((s+1)*IP_WIDTH+i)*WEIGHT_W) +: WEIGHT_W] =
                               S_W[((s*IP_WIDTH+i)*WEIGHT_W) +: WEIGHT_W];
                    end
                end
            end

            // ---------------- ODD stage ----------------
            else begin : ODD_STAGE
                // index 0 pass-through
                assign S_CHAR[(((s+1)*IP_WIDTH)*4) +: 4] =
                       S_CHAR[((s*IP_WIDTH)*4) +: 4];
                assign S_W[(((s+1)*IP_WIDTH)*WEIGHT_W) +: WEIGHT_W] =
                       S_W[((s*IP_WIDTH)*WEIGHT_W) +: WEIGHT_W];

                for (i = 1; i < IP_WIDTH; i = i + 2) begin : ODD_PAIR
                    if (i+1 < IP_WIDTH) begin
                        COMP2 #(.W_W(WEIGHT_W)) u_cmp_o (
                            .A_char(S_CHAR[((s*IP_WIDTH+i)*4) +: 4]),
                            .A_w   (S_W   [((s*IP_WIDTH+i)*WEIGHT_W) +: WEIGHT_W]),
                            .B_char(S_CHAR[((s*IP_WIDTH+i+1)*4) +: 4]),
                            .B_w   (S_W   [((s*IP_WIDTH+i+1)*WEIGHT_W) +: WEIGHT_W]),

                            .O0_char(S_CHAR[(((s+1)*IP_WIDTH+i)*4) +: 4]),
                            .O0_w   (S_W   [(((s+1)*IP_WIDTH+i)*WEIGHT_W) +: WEIGHT_W]),
                            .O1_char(S_CHAR[(((s+1)*IP_WIDTH+i+1)*4) +: 4]),
                            .O1_w   (S_W   [(((s+1)*IP_WIDTH+i+1)*WEIGHT_W) +: WEIGHT_W])
                        );
                    end
                    else begin
                        assign S_CHAR[(((s+1)*IP_WIDTH+i)*4) +: 4] =
                               S_CHAR[((s*IP_WIDTH+i)*4) +: 4];
                        assign S_W[(((s+1)*IP_WIDTH+i)*WEIGHT_W) +: WEIGHT_W] =
                               S_W[((s*IP_WIDTH+i)*WEIGHT_W) +: WEIGHT_W];
                    end
                end
            end
        end
    endgenerate

    // ----------------------------------------------------------
    // PACK final stage -> output
    // ----------------------------------------------------------
    generate
        for (i = 0; i < IP_WIDTH; i = i + 1) begin : PACK
            assign OUT_character[((IP_WIDTH-1-i)*4) +: 4] =
                   S_CHAR[(((STAGES-1)*IP_WIDTH+i)*4) +: 4];
        end
    endgenerate

endmodule

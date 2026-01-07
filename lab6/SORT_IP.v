// COMP2: comparator (keeps larger first; if weight equal compare char)
module COMP2 (
    input  [3:0] A_char,
    input  [4:0] A_w,
    input  [3:0] B_char,
    input  [4:0] B_w,

    output [3:0] O0_char,
    output [4:0] O0_w,
    output [3:0] O1_char,
    output [4:0] O1_w
);

    wire do_swap;

    assign do_swap = (A_w < B_w) ||
                     (A_w == B_w && A_char < B_char);

    assign O0_char = do_swap ? B_char : A_char;
    assign O0_w    = do_swap ? B_w    : A_w;

    assign O1_char = do_swap ? A_char : B_char;
    assign O1_w    = do_swap ? A_w    : B_w;

endmodule


module SORT_IP #(
    parameter IP_WIDTH = 8
)(
    input  [IP_WIDTH*4-1:0] IN_character,
    input  [IP_WIDTH*5-1:0] IN_weight,
    output [IP_WIDTH*4-1:0] OUT_character
);

    // number of passes needed by odd-even sort = IP_WIDTH
    localparam PASSES = IP_WIDTH;
    localparam STAGES = PASSES + 1; // stage 0..PASSES

    // flattened storage: each stage has IP_WIDTH entries
    // S_CHAR holds STAGES * IP_WIDTH entries of 4 bits each
    wire [STAGES*IP_WIDTH*4-1:0] S_CHAR;
    wire [STAGES*IP_WIDTH*5-1:0] S_W;

    genvar s, i;

    // ------------------------------------------------------------------
    // unpack inputs into stage 0 (indexing: stage 0 entry i)
    // store MSB first: IN_character[(IP_WIDTH-1-i)*4 +:4] -> S_CHAR[ (0*IP_WIDTH + i) ]
    // ------------------------------------------------------------------
    generate
        for (i = 0; i < IP_WIDTH; i = i + 1) begin : UNPACK
            assign S_CHAR[ ((0*IP_WIDTH + i)*4) +: 4 ] =
                   IN_character[ ((IP_WIDTH-1-i)*4) +: 4 ];

            assign S_W[    ((0*IP_WIDTH + i)*5) +: 5 ] =
                   IN_weight[   ((IP_WIDTH-1-i)*5) +: 5 ];
        end
    endgenerate

    // ------------------------------------------------------------------
    // For each pass s (0..PASSES-1), produce stage s+1 from stage s
    // For even s: compare pairs (0,1),(2,3),...
    // For odd  s: compare pairs (1,2),(3,4),...
    // For indices not part of a pair -> pass-through
    // ------------------------------------------------------------------
    generate
        for (s = 0; s < STAGES-1; s = s + 1) begin : STAGE_LOOP

            if ((s & 1) == 0) begin : EVEN_STAGE
                // even stage: pair (0,1),(2,3),...
                // iterate in steps of 2 for pairs
                for (i = 0; i < IP_WIDTH; i = i + 2) begin : PAIR_EVEN
                    if (i+1 < IP_WIDTH) begin
                        // comparator for (i, i+1)
                        COMP2 u_cmp (
                            .A_char( S_CHAR[ ((s*IP_WIDTH + i)*4)   +: 4 ] ),
                            .A_w   ( S_W[    ((s*IP_WIDTH + i)*5)   +: 5 ] ),
                            .B_char( S_CHAR[ ((s*IP_WIDTH + i+1)*4) +: 4 ] ),
                            .B_w   ( S_W[    ((s*IP_WIDTH + i+1)*5) +: 5 ] ),

                            .O0_char( S_CHAR[ (((s+1)*IP_WIDTH + i)*4)   +: 4 ] ),
                            .O0_w   ( S_W[    (((s+1)*IP_WIDTH + i)*5)   +: 5 ] ),
                            .O1_char( S_CHAR[ (((s+1)*IP_WIDTH + i+1)*4) +: 4 ] ),
                            .O1_w   ( S_W[    (((s+1)*IP_WIDTH + i+1)*5) +: 5 ] )
                        );
                    end else begin
                        // unpaired last index -> pass-through
                        assign S_CHAR[ (((s+1)*IP_WIDTH + i)*4) +: 4 ] =
                               S_CHAR[ ((s*IP_WIDTH + i)*4) +: 4 ];
                        assign S_W[    (((s+1)*IP_WIDTH + i)*5) +: 5 ] =
                               S_W[    ((s*IP_WIDTH + i)*5) +: 5 ];
                    end
                end
            end else begin : ODD_STAGE
                // odd stage: index 0 passes through, pairs start from 1: (1,2),(3,4),...
                // pass-through index 0
                if (IP_WIDTH > 0) begin
                    assign S_CHAR[ (((s+1)*IP_WIDTH + 0)*4) +: 4 ] =
                           S_CHAR[ ((s*IP_WIDTH + 0)*4) +: 4 ];
                    assign S_W[    (((s+1)*IP_WIDTH + 0)*5) +: 5 ] =
                           S_W[    ((s*IP_WIDTH + 0)*5) +: 5 ];
                end

                for (i = 1; i < IP_WIDTH; i = i + 2) begin : PAIR_ODD
                    if (i+1 < IP_WIDTH) begin
                        COMP2 u_cmp_o (
                            .A_char( S_CHAR[ ((s*IP_WIDTH + i)*4)   +: 4 ] ),
                            .A_w   ( S_W[    ((s*IP_WIDTH + i)*5)   +: 5 ] ),
                            .B_char( S_CHAR[ ((s*IP_WIDTH + i+1)*4) +: 4 ] ),
                            .B_w   ( S_W[    ((s*IP_WIDTH + i+1)*5) +: 5 ] ),

                            .O0_char( S_CHAR[ (((s+1)*IP_WIDTH + i)*4)   +: 4 ] ),
                            .O0_w   ( S_W[    (((s+1)*IP_WIDTH + i)*5)   +: 5 ] ),
                            .O1_char( S_CHAR[ (((s+1)*IP_WIDTH + i+1)*4) +: 4 ] ),
                            .O1_w   ( S_W[    (((s+1)*IP_WIDTH + i+1)*5) +: 5 ] )
                        );
                    end else begin
                        // unpaired last index -> pass-through
                        assign S_CHAR[ (((s+1)*IP_WIDTH + i)*4) +: 4 ] =
                               S_CHAR[ ((s*IP_WIDTH + i)*4) +: 4 ];
                        assign S_W[    (((s+1)*IP_WIDTH + i)*5) +: 5 ] =
                               S_W[    ((s*IP_WIDTH + i)*5) +: 5 ];
                    end
                end
            end

        end
    endgenerate

    // ------------------------------------------------------------------
    // pack final stage (stage STAGES-1) into OUT_character
    // ------------------------------------------------------------------
    generate
        for (i = 0; i < IP_WIDTH; i = i + 1) begin : PACK
            assign OUT_character[ ((IP_WIDTH-1-i)*4) +: 4 ] =
                   S_CHAR[ (((STAGES-1)*IP_WIDTH + i)*4) +: 4 ];
        end
    endgenerate

endmodule

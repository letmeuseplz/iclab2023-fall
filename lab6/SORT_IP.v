module SORT_IP #(parameter IP_WIDTH = 8)(
    input  [IP_WIDTH*4-1:0] IN_character,
    input  [IP_WIDTH*5-1:0] IN_weight,
    output [IP_WIDTH*4-1:0] OUT_character
);

// -----------------------------------------------
// Unpack input
// -----------------------------------------------
reg [3:0] char_arr   [0:IP_WIDTH-1];
reg [4:0] weight_arr [0:IP_WIDTH-1];

integer i,j;
IMG_BUF_SZ

// -----------------------------------------------
// Sorting (bubble sort) - descending
// weight larger → first
// if same weight → char larger → first
// -----------------------------------------------
reg [3:0] sorted_char   [0:IP_WIDTH-1];
reg [4:0] sorted_weight [0:IP_WIDTH-1];

reg [3:0] tmp_char;
reg [4:0] tmp_weight;

    always @(*) begin
        for(i = 0; i < IP_WIDTH; i = i + 1) begin
            char_arr[i]   = IN_character[ (IP_WIDTH-i)*4-1 : (IP_WIDTH-i-1)*4 ];
            weight_arr[i] = IN_weight  [ (IP_WIDTH-i)*5-1 : (IP_WIDTH-i-1)*5 ];
        end
    end


always @(*) begin
    // initialize
    for(i = 0; i < IP_WIDTH; i = i + 1) begin
        sorted_char[i]   = char_arr[i];
        sorted_weight[i] = weight_arr[i];
    end

    // bubble sort network
    for(i = 0; i < IP_WIDTH-1; i = i + 1) begin
        for(j = 0; j < IP_WIDTH-1-i; j = j + 1) begin

            // compare
            if( (sorted_weight[j] < sorted_weight[j+1]) ||
                ((sorted_weight[j] == sorted_weight[j+1]) &&
                 (sorted_char[j] < sorted_char[j+1])) ) 
            begin
                // swap
                tmp_char          = sorted_char[j];
                tmp_weight        = sorted_weight[j];

                sorted_char[j]    = sorted_char[j+1];
                sorted_weight[j]  = sorted_weight[j+1];

                sorted_char[j+1]  = tmp_char;
                sorted_weight[j+1]= tmp_weight;
            end
        end
    end
end

// -----------------------------------------------
// Pack output
// -----------------------------------------------
genvar k;
generate
    for(k = 0; k < IP_WIDTH; k = k + 1) begin : PACK
        assign OUT_character[(IP_WIDTH-i)*4-1 : (IP_WIDTH-i-1)*4] = sorted_char[k];
    end
endgenerate

endmodule

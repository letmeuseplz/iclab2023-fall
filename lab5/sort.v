// =========================================================
// MACRO: 3-Input Sorter & Median9 (維持原樣)
// =========================================================
module SORT3 (
    input  [19:0] d0, d1, d2,
    output [19:0] min_out, mid_out, max_out
);
    wire [19:0] l1_min = (d0 < d1) ? d0 : d1;
    wire [19:0] l1_max = (d0 < d1) ? d1 : d0;
    assign min_out = (l1_min < d2) ? l1_min : d2;
    wire [19:0] l2_max = (l1_min < d2) ? d2 : l1_min;
    assign mid_out = (l1_max < l2_max) ? l1_max : l2_max;
    assign max_out = (l1_max < l2_max) ? l2_max : l1_max;
endmodule

module MEDIAN9 (
    input  [19:0] p0, p1, p2, p3, p4, p5, p6, p7, p8,
    output [19:0] median_val
);
    wire [19:0] min0, mid0, max0;
    wire [19:0] min1, mid1, max1;
    wire [19:0] min2, mid2, max2;

    SORT3 r0 (.d0(p0), .d1(p1), .d2(p2), .min_out(min0), .mid_out(mid0), .max_out(max0));
    SORT3 r1 (.d0(p3), .d1(p4), .d2(p5), .min_out(min1), .mid_out(mid1), .max_out(max1));
    SORT3 r2 (.d0(p6), .d1(p7), .d2(p8), .min_out(min2), .mid_out(mid2), .max_out(max2));

    wire [19:0] max_min_01 = (min0 > min1) ? min0 : min1;
    wire [19:0] max_min    = (max_min_01 > min2) ? max_min_01 : min2;

    wire [19:0] min_max_01 = (max0 < max1) ? max0 : max1;
    wire [19:0] min_max    = (min_max_01 < max2) ? min_max_01 : max2;

    wire [19:0] med_mid, dummy1, dummy2;
    SORT3 c_mid (.d0(mid0), .d1(mid1), .d2(mid2), .min_out(dummy1), .mid_out(med_mid), .max_out(dummy2));

    wire [19:0] dummy3, dummy4;
    SORT3 final_sort (.d0(max_min), .d1(med_mid), .d2(min_max), .min_out(dummy3), .mid_out(median_val), .max_out(dummy4));
endmodule
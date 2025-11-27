`timescale 1ns/1ps

`define CYCLE_TIME 12 // cycle
`define PAT_NUM 17     // adjust to your number of patterns

module PATTERN(
    // Input Port (to pattern)
    clk,
    rst_n,
    in_valid,
    Img,
    Kernel,
    Weight,
    Opt,

    // Output Port (from DUT)
    out_valid,
    out
);

/* === IO direction (pattern drives DUT inputs) === */
output reg         clk, rst_n, in_valid;
output reg [31:0]  Img;
output reg [31:0]  Kernel;
output reg [31:0]  Weight;
output reg [1:0]   Opt;

input              out_valid;
input  [31:0]      out;

/* === clock === */
real CYCLE = `CYCLE_TIME;
always #(CYCLE/2.0) clk = ~clk;

/* === file handles & variables === */
integer f_img, f_ker, f_w, f_opt;
integer f_gold_out, f_gold_cnt;
integer i_pat, i;
integer latency;
integer total_latency;
integer timeout_limit;
integer patnum;
initial patnum = `PAT_NUM;

integer base_img, base_ker, base_w, base_gold;
integer idx;

integer img_total, ker_total, w_total, gold_total;

reg [31:0] mem_img  [0: (`PAT_NUM*96) - 1];  // PAT_NUM * 96 images per pattern
reg [31:0] mem_ker  [0: (`PAT_NUM*27) - 1];  // PAT_NUM * 27 kernels per pattern
reg [31:0] mem_w    [0: (`PAT_NUM*4)  - 1];  // PAT_NUM * 4 weights per pattern
reg [1:0]  mem_opt  [0: (`PAT_NUM) - 1];
reg [31:0] mem_gold_out [0: 10000];          // generous size for all golden outputs concatenated
integer    mem_gold_cnt [0: (`PAT_NUM)-1];   // how many out values expected for each pattern

/* Protect overlap: same style as your original PATTERN */
always @(*) begin
    if (in_valid && out_valid) begin
        $display("************************************************************");
        $display("                          FAIL!                             ");
        $display("*  The out_valid cannot overlap with in_valid   *");
        $display("************************************************************");
        $finish;
    end
end

/* === read mem files at start ===
   Expect files:
     - img.mem : hex words, total PAT_NUM*96 entries (each 32-bit hex)
     - ker.mem : hex words, total PAT_NUM*27 entries
     - w.mem   : hex words, total PAT_NUM*4 entries
     - opt.mem : hex words (2-bit values), PAT_NUM entries
     - golden_out.mem : hex words (32-bit expected out values) concatenated across patterns
     - golden_cnt.mem : decimal counts of expected outputs per pattern (PAT_NUM lines)
*/
initial begin
    // Attempt to load memories; will fail if missing
    $display("Load memory files ...");
    $readmemh("img.mem", mem_img);
    $readmemh("ker.mem", mem_ker);
    $readmemh("w.mem",   mem_w);
    $readmemh("opt.mem", mem_opt);
    $readmemh("golden_out.mem", mem_gold_out);
    // golden counts need decimal read with $fscanf below, but also can be stored via readmem if hex; we use a file open:
    f_gold_cnt = $fopen("golden_cnt.mem", "r");
    if (f_gold_cnt == 0) begin
        $display("************************************************************");
        $display(" FAIL! Cannot open golden_cnt.mem file");
        $display("************************************************************");
        $finish;
    end
    for (i = 0; i < patnum; i = i + 1) begin
        $fscanf(f_gold_cnt, "%d\n", mem_gold_cnt[i]);
    end
    $fclose(f_gold_cnt);

    // initialize
    reset_task();

    $display("------------------------------------------------------------");
    $display("            START SNN PATTERN RUN (TOTAL PATTERN = %0d)    ", patnum);
    $display("------------------------------------------------------------");

    total_latency = 0;
    base_img = 0; base_ker = 0; base_w = 0; base_gold = 0;

    // main loop over patterns
    for (i_pat = 0; i_pat < patnum; i_pat = i_pat + 1) begin
        // send inputs for pattern i_pat
        input_task(i_pat, base_img, base_ker, base_w, base_gold);
        wait_out_valid_task();
        check_ans_task(i_pat, base_gold);

        $display("\033[0;34mPASS PATTERN NO.%4d,\033[m \033[0;32mexecution cycle : %3d\033[m", i_pat, latency);

        // advance bases
        base_img  = base_img + 96;
        base_ker  = base_ker + 27;
        base_w    = base_w   + 4;
        base_gold = base_gold + mem_gold_cnt[i_pat];
    end

    YOU_PASS_task();
    #(`CYCLE_TIME * 100.0) $finish;
end

/* === reset task === */
task reset_task; begin
    rst_n = 1'b1;
    in_valid = 1'b0;
    Img = 32'bx;
    Kernel = 32'bx;
    Weight = 32'bx;
    Opt = 2'bx;
    force clk = 0;
    #CYCLE; rst_n = 0;
    #CYCLE; rst_n = 1;
    // check outputs are zero after reset (spec)
    if (out_valid !== 1'b0 || out !== 32'b0) begin
        $display("************************************************************");
        $display("                          FAIL!                             ");
        $display("*  Output signal should be 0 after initial RESET  at %8t   *",$time);
        $display("************************************************************");
        repeat(2) #CYCLE;
        $finish;
    end
    #CYCLE; release clk;
end endtask

/* === input_task ===
   For pattern i_pat we will:
    - at first in_valid cycle drive Opt = mem_opt[i_pat] (sent only on first in_valid cycle)
    - send 96 Img from mem_img[base_img ... base_img+95]
    - then send 27 Kernel
    - then send 4 Weight
    After finishing, drive in_valid = 0 and inputs = X
*/
task input_task;
input integer pat_index, img_base, ker_base, w_base, gold_base;
integer t, k;
integer idx_img, idx_ker, idx_w;
begin
    // random delay between patterns to mimic original style
    t = $urandom_range(1, 4);
    repeat(t) @(negedge clk);

    // begin sending: on first negedge we set in_valid high and present Opt (one cycle)
    in_valid = 1'b1;
    Opt = mem_opt[pat_index];

    // First cycle - provide first Img (we follow sending protocol: Opt is valid during first cycle of in_valid)
    idx_img = img_base;
    Img = mem_img[idx_img];
    Kernel = 32'bx;
    Weight = 32'bx;
    @(negedge clk);

    // Continue send remaining 95 Img (we already sent one)
    for (k = 1; k < 96; k = k + 1) begin
        idx_img = img_base + k;
        Img = mem_img[idx_img];
        Kernel = 32'bx;
        Weight = 32'bx;
        Opt = 2'bx; // Opt only valid on first cycle
        @(negedge clk);
    end

    // send 27 kernel cycles
    for (k = 0; k < 27; k = k + 1) begin
        idx_ker = ker_base + k;
        Img = 32'bx;
        Kernel = mem_ker[idx_ker];
        Weight = 32'bx;
        @(negedge clk);
    end

    // send 4 weight cycles
    for (k = 0; k < 4; k = k + 1) begin
        idx_w = w_base + k;
        Img = 32'bx;
        Kernel = 32'bx;
        Weight = mem_w[idx_w];
        @(negedge clk);
    end

    // finish input
    in_valid = 1'b0;
    Img = 32'bx; Kernel = 32'bx; Weight = 32'bx; Opt = 2'bx;
    @(negedge clk);
end
endtask

/* === wait_out_valid_task ===
   Wait for out_valid to become 1 (with timeout). Count latency in cycles (negedge steps).
   Use latency limit = 1000 (lab spec).
*/
task wait_out_valid_task; begin
    latency = 0;
    timeout_limit = 1000;
    while (out_valid !== 1'b1) begin
        latency = latency + 1;
        if (latency > timeout_limit) begin
            $display("********************************************************");
            $display("                          FAIL!                         ");
            $display("*  The execution latency are over %0d cycles  at %8t  *", timeout_limit, $time);
            $display("********************************************************");
            repeat(2) @(negedge clk);
            $finish;
        end
        @(negedge clk);
    end
    total_latency = total_latency + latency;
end endtask

/* === check_ans_task ===
   Compare each out (while out_valid is high) against mem_gold_out starting at base.
   mem_gold_cnt[pat_index] gives expected number of output words for this pattern.
   Currently uses exact 32-bit match. If you want floating-point tolerance compare,
   I can convert to real via $bitstoreal and compare with epsilon (e.g., 0.002 relative).
*/
task check_ans_task;
input integer pat_index, base_gold;
integer expect_cnt;
integer cnt;
integer gidx;
reg [31:0] expect;
begin
    expect_cnt = mem_gold_cnt[pat_index];
    cnt = 0;
    gidx = base_gold;
    while (out_valid === 1'b1) begin
        if (cnt >= expect_cnt) begin
            $display("----------------------------------------------------------------");
            $display("                         FAIL!                                   ");
            $display("   Received more outputs than golden expects for pattern %0d      ", pat_index);
            $display("----------------------------------------------------------------");
            repeat(5) @(negedge clk);
            $finish;
        end
        expect = mem_gold_out[gidx + cnt];
        if (out !== expect) begin
            $display("----------------------------------------------------------------");
            $display("                             FAIL!                               ");
            $display("   Pattern %0d: Golden out (hex) = %h, Your out (hex) = %h       ", pat_index, expect, out);
            $display("----------------------------------------------------------------");
            repeat(9) @(negedge clk);
            $finish;
        end
        cnt = cnt + 1;
        @(negedge clk);
    end

    if (cnt !== expect_cnt) begin
        $display("----------------------------------------------------------------");
        $display("                             FAIL!                               ");
        $display("   Pattern %0d: golden count = %0d, your count = %0d            ", pat_index, expect_cnt, cnt);
        $display("----------------------------------------------------------------");
        repeat(9) @(negedge clk);
        $finish;
    end
end
endtask

/* === YOU_PASS_task === */
task YOU_PASS_task; begin
    $display("----------------------------------------------------------------------------------------------------------------------");
    $display("                                                  Congratulations!                                                     ");
    $display("                                           You have passed all patterns!                                              ");
    $display("                                           Your execution cycles = %5d cycles                                        ", total_latency);
    $display("                                           Your clock period = %.1f ns                                              ", CYCLE);
    $display("                                           Total Latency (ns) = %.1f ns                                              ", total_latency * CYCLE);
    $display("----------------------------------------------------------------------------------------------------------------------");
    repeat(2) @(negedge clk);
    $finish;
end endtask

endmodule

// NOTE: Related files to prepare in working dir:
//   img.mem          : hex 32-bit words, total PAT_NUM * 96 lines
//   ker.mem          : hex 32-bit words, total PAT_NUM * 27 lines
//   w.mem            : hex 32-bit words, total PAT_NUM * 4 lines
//   opt.mem          : hex 2-bit values, PAT_NUM lines (e.g., 0,1,2,3 as hex)
//   golden_out.mem   : hex 32-bit words concatenated all patterns' expected out in order
//   golden_cnt.mem   : decimal lines, PAT_NUM lines where each line = expected output count for that pattern
//
// If you prefer different file layout (one file per pattern or ascii floats), tell me and我會幫你改。
//
// Reference PDF (uploaded): /mnt/data/Lab04_Exercise_v2.pdf

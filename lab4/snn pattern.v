`timescale 1ns/1ps
`define CYCLE_TIME 12
`define PAT_NUM    20   // 可依需要修改

module PATTERN(
    // ---- Inputs TO DUT ----
    output reg        clk,
    output reg        rst_n,
    output reg        in_valid,
    output reg [31:0] Img,
    output reg [31:0] Kernel,
    output reg [31:0] Weight,
    output reg [1:0]  Opt,

    // ---- Outputs FROM DUT ----
    input             out_valid,
    input      [31:0] out
);

// =========================================================
// CLOCK
// =========================================================
real CYCLE = `CYCLE_TIME;
always #(CYCLE/2.0) clk = ~clk;


// =========================================================
// MEMORY DECLARATIONS
// =========================================================
reg [31:0] mem_img  [0:(`PAT_NUM*96)-1];
reg [31:0] mem_ker  [0:(`PAT_NUM*27)-1];
reg [31:0] mem_w    [0:(`PAT_NUM*4)-1];
reg  [1:0] mem_opt  [0:`PAT_NUM-1];
reg [31:0] mem_gold_out [0:20000]; // 足夠大
integer    mem_gold_cnt [0:`PAT_NUM-1];


// =========================================================
// GENERAL VARIABLES
// =========================================================
integer pat_i;
integer latency, total_latency;
integer base_img, base_ker, base_w, base_gold;
integer delay_rand;
real golden_real, out_real, error_rate;


// =========================================================
// PROTECT: out_valid cannot overlap with in_valid
// =========================================================
always @(*) begin
    if(in_valid && out_valid) begin
        $display("************************************************************");
        $display("                           FAIL!                             ");
        $display("* out_valid cannot overlap with in_valid (spec #8)          *");
        $display("************************************************************");
        $finish;
    end
end


// =========================================================
// INITIAL
// =========================================================
initial begin
    // Load patterns
    $readmemh("img.mem"       , mem_img);
    $readmemh("ker.mem"       , mem_ker);
    $readmemh("w.mem"         , mem_w);
    $readmemh("opt.mem"       , mem_opt);
    $readmemh("golden_out.mem", mem_gold_out);

    integer fcnt, tmp;
    fcnt = $fopen("golden_cnt.mem", "r");
    if(fcnt == 0) begin
        $display("FAIL! Cannot open golden_cnt.mem");
        $finish;
    end
    for(tmp = 0; tmp < `PAT_NUM; tmp = tmp + 1)
        $fscanf(fcnt, "%d\n", mem_gold_cnt[tmp]);
    $fclose(fcnt);

    total_latency = 0;
    base_img  = 0;
    base_ker  = 0;
    base_w    = 0;
    base_gold = 0;

    reset_task;

    $display("-------------------------------------------------------------");
    $display("                START SNN PATTERNS (TOTAL = %0d)            ", `PAT_NUM);
    $display("-------------------------------------------------------------");

    // RUN ALL PATTERNS
    for(pat_i = 0; pat_i < `PAT_NUM; pat_i = pat_i + 1) begin
        send_inputs(pat_i, base_img, base_ker, base_w);
        wait_out_valid;
        check_output(pat_i, base_gold);

        total_latency += latency;

        base_img  += 96;
        base_ker  += 27;
        base_w    += 4;
        base_gold += mem_gold_cnt[pat_i];

        $display("\033[0;34mPASS PATTERN %0d,\033[m Latency = %0d cycles", pat_i, latency);
    end

    final_pass;
    #100 $finish;
end


// =========================================================
// RESET TASK (Spec #3 #4 #5)
// =========================================================
task reset_task; begin
    clk = 0;
    rst_n = 1;
    in_valid = 0;
    Img = 'bx;
    Kernel = 'bx;
    Weight = 'bx;
    Opt = 'bx;

    force clk = 0;
    #(CYCLE) rst_n = 0;   // assert reset
    #(CYCLE) rst_n = 1;   // release reset

    if(out_valid !== 0 || out !== 0) begin
        $display("************************************************************");
        $display("                           FAIL!                             ");
        $display("* Output not zero after reset release (spec #4)             *");
        $display("************************************************************");
        $finish;
    end

    #(CYCLE);
    release clk;
end endtask



// =========================================================
// SEND INPUTS TASK (Spec #1 #2 #3 #4 #5)
// - Opt only valid in first in_valid cycle
// - Img 96 cycles
// - Kernel 27 cycles
// - Weight 4 cycles
// - all changes on negedge clk
// =========================================================
task send_inputs;
input integer pat_idx;
input integer img_base, ker_base, w_base;
integer k;
begin
    delay_rand = $urandom_range(1,4);
    repeat(delay_rand) @(negedge clk);

    in_valid = 1;
    Opt = mem_opt[pat_idx];

    // ---- Send 96 IMG ----
    for(k=0; k<96; k=k+1) begin
        @(negedge clk);
        Img    = mem_img[img_base + k];
        Kernel = 'bx;
        Weight = 'bx;
        if(k > 0) Opt = 'bx; // Opt only legal at first cycle
    end

    // ---- Send 27 Kernel ----
    for(k=0; k<27; k=k+1) begin
        @(negedge clk);
        Img    = 'bx;
        Kernel = mem_ker[ker_base + k];
        Weight = 'bx;
    end

    // ---- Send 4 Weight ----
    for(k=0; k<4; k=k+1) begin
        @(negedge clk);
        Img    = 'bx;
        Kernel = 'bx;
        Weight = mem_w[w_base + k];
    end

    // ---- Finish ----
    @(negedge clk);
    in_valid = 0;
    Img = 'bx; Kernel = 'bx; Weight = 'bx; Opt = 'bx;
end endtask



// =========================================================
// WAIT OUTPUT (Spec #6 latency <= 1000)
// =========================================================
task wait_out_valid; begin
    latency = 0;

    while(out_valid !== 1) begin
        @(negedge clk);
        latency = latency + 1;
        if(latency > 1000) begin
            $display("************************************************************");
            $display("                           FAIL!                             ");
            $display("* Latency > 1000 cycles (spec #6)                           *");
            $display("************************************************************");
            $finish;
        end
    end
end endtask



// =========================================================
// CHECK OUTPUT (Spec: float error < 0.002)
// =========================================================
task check_output;
input integer pat_idx;
input integer base_gold;
integer cnt;
reg [31:0] gold_bin;
begin
    cnt = 0;

    while(out_valid === 1) begin
        gold_bin = mem_gold_out[base_gold + cnt];

        // FLOAT compare
        golden_real = $bitstoreal(gold_bin);
        out_real    = $bitstoreal(out);
        error_rate  = (golden_real - out_real);
        if(golden_real != 0) error_rate = error_rate / golden_real;
        if(error_rate < 0) error_rate = -error_rate;

        if(error_rate > 0.002) begin
            $display("----------------------------------------------------------------");
            $display("                             FAIL!                               ");
            $display(" Pattern %0d: Floating error exceeded 0.002                     ", pat_idx);
            $display(" Golden = %e  (hex=%h)", golden_real, gold_bin);
            $display("   Your = %e  (hex=%h)", out_real, out);
            $display(" Error = %e", error_rate);
            $display("----------------------------------------------------------------");
            $finish;
        end

        cnt = cnt + 1;
        @(negedge clk);
    end

    if(cnt !== mem_gold_cnt[pat_idx]) begin
        $display("************************************************************");
        $display("                           FAIL!                             ");
        $display("* Output count mismatch on pattern %0d                       *", pat_idx);
        $display(" Golden count = %0d", mem_gold_cnt[pat_idx]);
        $display(" Your   count = %0d", cnt);
        $display("************************************************************");
        $finish;
    end
end endtask



// =========================================================
// FINAL PASS
// =========================================================
task final_pass; begin
    $display("======================================================================");
    $display("                         CONGRATULATIONS!                             ");
    $display("                   All SNN patterns PASSED!!!                         ");
    $display(" Total execution cycles = %0d cycles", total_latency);
    $display(" Clock period = %0.1f ns", CYCLE);
    $display(" Total latency (ns) = %0.1f", total_latency * CYCLE);
    $display("======================================================================");
end endtask


endmodule

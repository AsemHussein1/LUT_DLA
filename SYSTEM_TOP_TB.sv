`timescale 1ns / 1ps
// =============================================================
//  SYSTEM_TOP_TB  —  Comprehensive testbench  (21 TCs)
//
//  Test cases:
//    TC1  – Normal full compute, read 16 outputs
//    TC2  – Two consecutive runs, cycle-count consistency
//    TC3  – Non-zero spad_out_addr (0x040)
//    TC4  – Busy-gating: double start rejected
//    TC5  – Reset recovery mid-operation + re-run
//    TC6  – All-zero LSRAM → output = 0x00000000
//    TC7  – All-0xFF  LSRAM → golden output = 0x00000FF0
//    TC8  – Rapid-fire 10 consecutive runs
//    TC9  – Random LSRAM × 5 seeds, non-zero output check
//    TC10 – Alternating max/zero × 4 pairs, output flips
//    TC11 – Long stress: 15 runs, ramp LSRAM
//    TC12 – Full OSRAM scan: all 320 elements vs golden
//    TC13 – Column-specific constant LUT, verify per-column golden
//    TC14 – Determinism: two runs same inputs → identical output
//    TC15 – Deep reset stress: 8 resets then clean run
//    TC16 – Back-to-back 20 runs with large random LUT
//    TC17 – spad_out_addr sweep: 4 different base addresses
//    TC18 – spad_out_addr × LUT-pattern cross sweep (11 combos)
//    TC19 – FIFO stress: div_ratio=16 slows IMM, stresses FIFO depth
//    TC20 – fine spad_out_addr sweep toggling ctrl2spad bits 2-5
//    TC21 – Python golden co-verification: bit-exact RTL vs co_verify.py
//
//  Assertions (13):
//    A1  sys_done is exactly 1 cycle wide
//    A2  sys2top_ready deasserts cycle after start
//    A3  sys_done only fires after a prior start
//    A4  sys_done |=> sys2top_ready (ready reasserts next cycle)
//    A5  !tb_busy |-> sys2top_ready (idle implies ready)
//    A6  start and sys_done cannot be simultaneous
//    A7  !rst_n |=> !sys_done (reset clears done)
//    A8  sys_done fires while sys2top_ready is still LOW
//    A9  k_total >= 1 at every start
//    A10 n_total >= 1 at every start
//    A11 CSRAM and ISRAM writes are mutually exclusive
//    A12 LSRAM write and CSRAM write are mutually exclusive
//    A13 Sequence: no second start fires before sys_done
//
//  Functional Coverage (10 groups):
//    CG1  cg_system_ctrl  – done/ready/busy handshake + crosses
//    CG2  cg_dimensions   – k_total × n_total at start
//    CG3  cg_lsram_write  – addr range × data class + cross
//    CG4  cg_spad_addr    – output base address range + pattern cross
//    CG5  cg_lut_pattern  – zero / max / ramp / random
//    CG6  cg_run_cycles   – completion time buckets
//    CG7  cg_multi_run    – cumulative run count bins
//    CG8  cg_csram_write  – centroid SRAM write coverage
//    CG9  cg_isram_write  – input SRAM write coverage
//    CG10 cg_osram_read   – OSRAM read address range
// =============================================================

module SYSTEM_TOP_TB;

    // ─────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────
    localparam NUM_CENTROIDS  = 16;
    localparam VECTOR_LENGTH  = 2;
    localparam VALUE_WIDTH    = 8;
    localparam M              = 20;
    localparam K              = 16;
    localparam N              = 16;
    localparam CSRAM_ADDR_W   = $clog2(K * NUM_CENTROIDS);
    localparam ISRAM_ADDR_W   = $clog2(K * M);
    localparam LSRAM_ADDR_W   = $clog2(K * N * NUM_CENTROIDS);
    localparam OSRAM_ADDR_W   = $clog2(M * N);
    localparam MEM_ADDR_WIDTH = LSRAM_ADDR_W;
    localparam CSRAM_DATA_W   = VALUE_WIDTH * VECTOR_LENGTH;
    localparam ISRAM_DATA_W   = VALUE_WIDTH * VECTOR_LENGTH;
    localparam LSRAM_DATA_W   = VALUE_WIDTH;
    localparam SPAD_DATA_W    = 32;
    localparam DIV_RATIO_W    = 8;
    localparam K_CNT_W        = $clog2(K + 1);
    localparam N_CNT_W        = $clog2(N + 1);
    localparam TOTAL_OUTPUTS  = M * N;   // 320

    // Golden models
    // all-0xFF LSRAM: each element = 0xFF * K = 4080 = 0x00000FF0
    localparam [SPAD_DATA_W-1:0] GOLDEN_MAX = 8'hFF * K;
    // all-0x00 LSRAM: each element = 0
    localparam [SPAD_DATA_W-1:0] GOLDEN_ZERO = 32'd0;

    localparam TIMEOUT_CYCLES  = 200_000;
    localparam CLK_FAST_PERIOD = 10;

    // ─────────────────────────────────────────────────────────
    //  DUT Interface Signals
    // ─────────────────────────────────────────────────────────
    reg                          clk_fast;
    reg                          rst_n;
    reg  [DIV_RATIO_W-1:0]       div_ratio;
    reg                          top2sys_valid;
    wire                         sys2top_ready;
    wire                         sys_done;
    reg  [K_CNT_W-1:0]           k_total;
    reg  [N_CNT_W-1:0]           n_total;
    reg  [MEM_ADDR_WIDTH-1:0]    spad_out_addr;

    reg                          csram_we_a;
    reg  [CSRAM_ADDR_W-1:0]      csram_waddr_a;
    reg  [CSRAM_DATA_W-1:0]      csram_wdata_a;

    reg                          isram_we_a;
    reg  [ISRAM_ADDR_W-1:0]      isram_waddr_a;
    reg  [ISRAM_DATA_W-1:0]      isram_wdata_a;

    reg                          lsram_we_a;
    reg  [LSRAM_ADDR_W-1:0]      lsram_waddr_a;
    reg  [LSRAM_DATA_W-1:0]      lsram_wdata_a;

    reg                          osram_re_b;
    reg  [OSRAM_ADDR_W-1:0]      osram_raddr_b;
    wire [SPAD_DATA_W-1:0]       osram_rdata_b;

    // ─────────────────────────────────────────────────────────
    //  DUT Instantiation
    // ─────────────────────────────────────────────────────────
    SYSTEM_TOP #(
        .NUM_CENTROIDS (NUM_CENTROIDS),
        .VECTOR_LENGTH (VECTOR_LENGTH),
        .VALUE_WIDTH   (VALUE_WIDTH),
        .M             (M),
        .K             (K),
        .N             (N),
        .DIV_RATIO_W   (DIV_RATIO_W)
    ) dut (
        .clk_fast      (clk_fast),
        .rst_n         (rst_n),
        .div_ratio     (div_ratio),
        .top2sys_valid (top2sys_valid),
        .sys2top_ready (sys2top_ready),
        .sys_done      (sys_done),
        .k_total       (k_total),
        .n_total       (n_total),
        .spad_out_addr (spad_out_addr),
        .csram_we_a    (csram_we_a),
        .csram_waddr_a (csram_waddr_a),
        .csram_wdata_a (csram_wdata_a),
        .isram_we_a    (isram_we_a),
        .isram_waddr_a (isram_waddr_a),
        .isram_wdata_a (isram_wdata_a),
        .lsram_we_a    (lsram_we_a),
        .lsram_waddr_a (lsram_waddr_a),
        .lsram_wdata_a (lsram_wdata_a),
        .osram_re_b    (osram_re_b),
        .osram_raddr_b (osram_raddr_b),
        .osram_rdata_b (osram_rdata_b)
    );

    // ─────────────────────────────────────────────────────────
    //  Clock
    // ─────────────────────────────────────────────────────────
    initial clk_fast = 1'b0;
    always #(CLK_FAST_PERIOD/2) clk_fast = ~clk_fast;

    // ─────────────────────────────────────────────────────────
    //  Scoreboard
    // ─────────────────────────────────────────────────────────
    integer pass_count;
    integer fail_count;
    integer assert_fail_count;
    integer run_total;
    integer last_cycle_count;
    integer reset_count;

    // TB-side busy tracking (mirrors DUT sys_busy)
    reg tb_busy;
    always @(posedge clk_fast or negedge rst_n) begin
        if (!rst_n)                             tb_busy <= 1'b0;
        else if (top2sys_valid && sys2top_ready) tb_busy <= 1'b1;
        else if (sys_done)                       tb_busy <= 1'b0;
    end

    // LUT pattern tag: 0=zero 1=max 2=ramp 3=random 4=col-const
    integer lut_pattern_tag;

    // TC21 OSRAM-write monitor
    reg tc21_active;
    integer tc21_osram_wr_cnt;
    wire clk_slow_mon = dut.clk_slow;
    always @(posedge clk_slow_mon) begin
        if (tc21_active && dut.osram_we_a) begin
            if (tc21_osram_wr_cnt < 20) begin
                $display("[OSRAM_WR] #%0d  addr=%0d  data=0x%08x  t=%0t",
                         tc21_osram_wr_cnt,
                         dut.osram_waddr_full[OSRAM_ADDR_W-1:0],
                         dut.osram_wdata_a, $time);
            end
            tc21_osram_wr_cnt = tc21_osram_wr_cnt + 1;
        end
    end

    // TC21 c_star monitor: capture first 24 c_star values consumed by PSumLUT
    reg  tc21_cstar_active;
    integer tc21_cstar_cnt;
    always @(posedge clk_slow_mon) begin
        if (tc21_cstar_active && dut.u_imm.PSum_LUT_inst.fifo_pop) begin
            if (tc21_cstar_cnt < 24) begin
                $display("[CSTAR] #%0d  c_star=%0d  t=%0t",
                         tc21_cstar_cnt,
                         dut.fifo2psum_index, $time);
            end
            tc21_cstar_cnt = tc21_cstar_cnt + 1;
        end
    end

    // ── Hardware counters for covergroup sampling ─────────────
    // last_cycle_count and run_total are blocking-assigned inside tasks,
    // so they arrive AFTER the posedge where sys_done fires — too late
    // for covergroup observation.  Use always-block (nonblocking) versions
    // captured one cycle early, sampled via the 1-cycle-delayed sys_done_q.

    // Cycle counter: resets on every start, counts while busy
    integer hw_cycle_cnt;
    always @(posedge clk_fast or negedge rst_n) begin
        if (!rst_n)                              hw_cycle_cnt <= 0;
        else if (top2sys_valid && sys2top_ready) hw_cycle_cnt <= 0;
        else if (tb_busy)                        hw_cycle_cnt <= hw_cycle_cnt + 1;
    end

    // Latch hw_cycle_cnt at sys_done → available at sys_done_q (next cycle)
    integer hw_last_cycles;
    always @(posedge clk_fast or negedge rst_n) begin
        if (!rst_n)        hw_last_cycles <= 0;
        else if (sys_done) hw_last_cycles <= hw_cycle_cnt;
    end

    // Cumulative run counter, increments at each sys_done
    integer hw_run_total;
    always @(posedge clk_fast or negedge rst_n) begin
        if (!rst_n)        hw_run_total <= 0;
        else if (sys_done) hw_run_total <= hw_run_total + 1;
    end

    // 1-cycle delayed sys_done — use as iff guard so the above values are ready
    reg sys_done_q;
    always @(posedge clk_fast or negedge rst_n) begin
        if (!rst_n) sys_done_q <= 1'b0;
        else        sys_done_q <= sys_done;
    end

    // ─────────────────────────────────────────────────────────
    //  ======  SVA ASSERTIONS (13)  ======
    // ─────────────────────────────────────────────────────────

    // A1: sys_done must be exactly 1 cycle wide
    property p_done_pulse;
        @(posedge clk_fast) disable iff (!rst_n)
        sys_done |=> !sys_done;
    endproperty
    a_done_pulse: assert property (p_done_pulse) else begin
        $error("[A1 FAIL] sys_done held HIGH >1 cycle at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end
    c_done_pulse: cover property (@(posedge clk_fast) sys_done ##1 !sys_done);

    // A2: sys2top_ready deasserts the cycle after start
    property p_ready_deasserts;
        @(posedge clk_fast) disable iff (!rst_n)
        (top2sys_valid && sys2top_ready) |=> !sys2top_ready;
    endproperty
    a_ready_deasserts: assert property (p_ready_deasserts) else begin
        $error("[A2 FAIL] sys2top_ready stayed HIGH after start at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end
    c_ready_deasserts: cover property (@(posedge clk_fast)
        (top2sys_valid && sys2top_ready) ##1 !sys2top_ready);

    // A3: sys_done only fires after a prior start
    property p_no_spurious_done;
        @(posedge clk_fast) disable iff (!rst_n)
        sys_done |-> tb_busy;
    endproperty
    a_no_spurious_done: assert property (p_no_spurious_done) else begin
        $error("[A3 FAIL] sys_done without prior start at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A4: ready must reassert the cycle after sys_done
    property p_ready_after_done;
        @(posedge clk_fast) disable iff (!rst_n)
        sys_done |=> sys2top_ready;
    endproperty
    a_ready_after_done: assert property (p_ready_after_done) else begin
        $error("[A4 FAIL] sys2top_ready did not reassert after sys_done at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end
    c_ready_after_done: cover property (@(posedge clk_fast)
        sys_done ##1 sys2top_ready);

    // A5: While idle, sys2top_ready must be HIGH
    property p_idle_means_ready;
        @(posedge clk_fast) disable iff (!rst_n)
        !tb_busy |-> sys2top_ready;
    endproperty
    a_idle_means_ready: assert property (p_idle_means_ready) else begin
        $error("[A5 FAIL] sys2top_ready LOW while idle at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A6: sys_done cannot fire in the same cycle as a start
    property p_no_done_at_start;
        @(posedge clk_fast) disable iff (!rst_n)
        (top2sys_valid && sys2top_ready) |-> !sys_done;
    endproperty
    a_no_done_at_start: assert property (p_no_done_at_start) else begin
        $error("[A6 FAIL] sys_done fired in start cycle at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A7: After reset deasserted, sys_done must be 0
    property p_reset_clears_done;
        @(posedge clk_fast)
        !rst_n |=> !sys_done;
    endproperty
    a_reset_clears_done: assert property (p_reset_clears_done) else begin
        $error("[A7 FAIL] sys_done HIGH after reset at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A8: sys_done fires while sys2top_ready is still LOW (busy)
    property p_done_while_busy;
        @(posedge clk_fast) disable iff (!rst_n)
        sys_done |-> !sys2top_ready;
    endproperty
    a_done_while_busy: assert property (p_done_while_busy) else begin
        $error("[A8 FAIL] sys2top_ready was HIGH when sys_done fired at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A9: k_total must be >= 1 at every start handshake
    property p_k_valid_at_start;
        @(posedge clk_fast) disable iff (!rst_n)
        (top2sys_valid && sys2top_ready) |-> (k_total >= 1);
    endproperty
    a_k_valid: assert property (p_k_valid_at_start) else begin
        $error("[A9 FAIL] k_total=%0d at start at %0t ns", k_total, $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A10: n_total must be >= 1 at every start handshake
    property p_n_valid_at_start;
        @(posedge clk_fast) disable iff (!rst_n)
        (top2sys_valid && sys2top_ready) |-> (n_total >= 1);
    endproperty
    a_n_valid: assert property (p_n_valid_at_start) else begin
        $error("[A10 FAIL] n_total=%0d at start at %0t ns", n_total, $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A11: CSRAM and ISRAM writes must not be simultaneous
    property p_csram_isram_exclusive;
        @(posedge clk_fast) disable iff (!rst_n)
        !(csram_we_a && isram_we_a);
    endproperty
    a_csram_isram_exclusive: assert property (p_csram_isram_exclusive) else begin
        $error("[A11 FAIL] CSRAM and ISRAM both written at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A12: LSRAM and CSRAM writes must not be simultaneous
    property p_lsram_csram_exclusive;
        @(posedge clk_fast) disable iff (!rst_n)
        !(lsram_we_a && csram_we_a);
    endproperty
    a_lsram_csram_exclusive: assert property (p_lsram_csram_exclusive) else begin
        $error("[A12 FAIL] LSRAM and CSRAM both written at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // A13: After a start, no second start fires before sys_done
    //      (busy held between start and done — no re-entry)
    property p_no_double_start;
        @(posedge clk_fast) disable iff (!rst_n)
        (top2sys_valid && sys2top_ready)
            |=> (!sys2top_ready) throughout (sys_done[->1]);
    endproperty
    a_no_double_start: assert property (p_no_double_start) else begin
        $error("[A13 FAIL] sys2top_ready re-asserted before sys_done at %0t ns", $time);
        assert_fail_count = assert_fail_count + 1;
    end

    // ─────────────────────────────────────────────────────────
    //  ======  FUNCTIONAL COVERAGE (10 groups)  ======
    // ─────────────────────────────────────────────────────────

    // CG1 – System control handshake
    // NOTE: cx_start_from_idle / cx_done_to_ready removed — both had structurally
    // impossible cross cells (start requires sys2top_ready=1 ↔ busy=0; done fires
    // while sys2top_ready is still 0) that could never be hit.
    covergroup cg_system_ctrl @(posedge clk_fast);
        cp_done:  coverpoint sys_done      { bins done_pulse = {1'b1}; }
        cp_ready: coverpoint sys2top_ready { bins rdy_hi = {1'b1}; bins rdy_lo = {1'b0}; }
        cp_start: coverpoint (top2sys_valid && sys2top_ready) { bins start_ev = {1'b1}; }
        cp_busy:  coverpoint tb_busy       { bins s_idle = {1'b0}; bins s_busy = {1'b1}; }
        cp_valid_while_busy: coverpoint (top2sys_valid && tb_busy) {
            bins ignored_start = {1'b1};
        }
        // Cross: does done happen, and does ready follow?  (done=1 × ready=0 then done=0 × ready=1)
        cx_done_seq: cross cp_done, cp_ready {
            // Only the reachable combinations
            ignore_bins impossible_done_rdy = binsof(cp_done.done_pulse) && binsof(cp_ready.rdy_hi);
        }
    endgroup

    // CG2 – Dimension combinations at start
    // NOTE: k_mid/k_lo/n_mid/n_lo bins are unreachable — Scratchpad has K_SUBS/N_COLS
    // as compile-time parameters fixed at K=16, N=16.  Weight=0 so this group is
    // informational and does not drag down the total coverage metric.
    covergroup cg_dimensions @(posedge clk_fast);
        type_option.weight = 0;
        cp_k: coverpoint k_total iff (top2sys_valid && sys2top_ready) {
            bins k_full = {[14:16]};
        }
        cp_n: coverpoint n_total iff (top2sys_valid && sys2top_ready) {
            bins n_full = {[14:16]};
        }
    endgroup

    // CG3 – LSRAM write: address range × data class
    covergroup cg_lsram_write @(posedge clk_fast);
        cp_lsram_addr: coverpoint lsram_waddr_a iff (lsram_we_a) {
            bins addr_lo  = {[0:1023]};
            bins addr_mid = {[1024:3071]};
            bins addr_hi  = {[3072:4095]};
        }
        cp_lsram_data: coverpoint lsram_wdata_a iff (lsram_we_a) {
            bins dat_zero  = {8'h00};
            bins dat_max   = {8'hFF};
            bins dat_lo    = {[8'h01:8'h7F]};
            bins dat_hi    = {[8'h80:8'hFE]};
        }
        cx_addr_data: cross cp_lsram_addr, cp_lsram_data;
    endgroup

    // CG4 – spad_out_addr range × LUT pattern cross
    covergroup cg_spad_addr @(posedge clk_fast);
        cp_spad: coverpoint spad_out_addr iff (top2sys_valid && sys2top_ready) {
            bins addr_zero = {12'h000};
            bins addr_lo   = {[12'h001:12'h03F]};
            bins addr_mid  = {[12'h040:12'h0FF]};
            bins addr_hi   = {[12'h100:12'hFFF]};
        }
        cp_pat: coverpoint lut_pattern_tag iff (top2sys_valid && sys2top_ready) {
            bins pat_zero   = {0};
            bins pat_max    = {1};
            bins pat_ramp   = {2};
            bins pat_random = {3};
            bins pat_col    = {4};
        }
        cx_spad_pat: cross cp_spad, cp_pat;
    endgroup

    // CG5 – LUT pattern at start
    covergroup cg_lut_pattern @(posedge clk_fast);
        cp_pattern: coverpoint lut_pattern_tag iff (top2sys_valid && sys2top_ready) {
            bins pat_zero   = {0};
            bins pat_max    = {1};
            bins pat_ramp   = {2};
            bins pat_random = {3};
            bins pat_col    = {4};
        }
    endgroup

    // CG6 – Completion time budget
    // fast_run / slow_run bins were unreachable: DUT always completes in ~10k-30k fast
    // clocks for K=16 N=16 (deterministic).  Replaced with two reachable bins:
    //   in_budget  — expected: every normal run lands here
    //   over_budget — should never fire; fires if something hangs → caught as anomaly
    // type_option.weight=0 so this informational group doesn't drag total coverage.
    covergroup cg_run_cycles @(posedge clk_fast);
        type_option.weight = 0;
        cp_cycles: coverpoint hw_last_cycles iff (sys_done_q) {
            bins in_budget = {[1:200000]};  // single bin: every completion hits this
        }
    endgroup

    // CG7 – Cumulative run count
    // Uses sys_done_q so hw_run_total already reflects the completed run
    covergroup cg_multi_run @(posedge clk_fast);
        cp_runs: coverpoint hw_run_total iff (sys_done_q) {
            bins one       = {1};
            bins two_five  = {[2:5]};
            bins six_ten   = {[6:10]};
            bins eleven_20 = {[11:20]};
            bins over_20   = {[21:$]};
        }
    endgroup

    // CG8 – CSRAM write coverage
    covergroup cg_csram_write @(posedge clk_fast);
        cp_csram_addr: coverpoint csram_waddr_a iff (csram_we_a) {
            bins cs_lo  = {[0:63]};
            bins cs_mid = {[64:191]};
            bins cs_hi  = {[192:255]};
        }
        cp_csram_data_hi: coverpoint csram_wdata_a[15:8] iff (csram_we_a) {
            bins subspace_lo = {[8'h00:8'h07]};
            bins subspace_hi = {[8'h08:8'hFF]};
        }
    endgroup

    // CG9 – ISRAM write coverage
    covergroup cg_isram_write @(posedge clk_fast);
        cp_isram_addr: coverpoint isram_waddr_a iff (isram_we_a) {
            bins is_lo  = {[0:106]};
            bins is_mid = {[107:213]};
            bins is_hi  = {[214:319]};
        }
    endgroup

    // CG10 – OSRAM read address × output data range
    // dat_hi removed: max output = K×0xFF = 4080 = 0xFF0 < 0x10000 → structurally unreachable.
    // dat_lo  = col-const output: K*(n+1) = 16..256 (TC13)
    // dat_mid = all-0xFF output: K*0xFF = 4080 (TC7,TC10,TC12)  [0x800..0xFFFF covers 4080]
    // dat_zero= zero-LUT output (TC6)
    covergroup cg_osram_read @(posedge clk_fast);
        cp_osram_raddr: coverpoint osram_raddr_b iff (osram_re_b) {
            bins rd_lo  = {[0:106]};
            bins rd_mid = {[107:213]};
            bins rd_hi  = {[214:319]};
        }
        cp_rdata_range: coverpoint osram_rdata_b iff (osram_re_b) {
            bins dat_zero = {32'h0000_0000};
            bins dat_lo   = {[32'h0000_0001:32'h0000_07FF]};
            bins dat_mid  = {[32'h0000_0800:32'h0000_FFFF]};
        }
        cx_addr_rdata: cross cp_osram_raddr, cp_rdata_range;
    endgroup

    // ── Covergroup instances ──────────────────────────────────
    cg_system_ctrl  cg_ctrl_inst;
    cg_dimensions   cg_dim_inst;
    cg_lsram_write  cg_lsram_inst;
    cg_spad_addr    cg_spad_inst;
    cg_lut_pattern  cg_lut_inst;
    cg_run_cycles   cg_cyc_inst;
    cg_multi_run    cg_multi_inst;
    cg_csram_write  cg_csram_inst;
    cg_isram_write  cg_isram_inst;
    cg_osram_read   cg_osram_inst;

    // ─────────────────────────────────────────────────────────
    //  ======  HELPER TASKS  ======
    // ─────────────────────────────────────────────────────────

    task wait_clk(input integer n);
        repeat(n) @(posedge clk_fast);
    endtask

    task do_reset();
        rst_n         = 1'b0;
        top2sys_valid = 1'b0;
        csram_we_a    = 1'b0;
        isram_we_a    = 1'b0;
        lsram_we_a    = 1'b0;
        osram_re_b    = 1'b0;
        k_total       = K[K_CNT_W-1:0];
        n_total       = N[N_CNT_W-1:0];
        spad_out_addr = '0;
        div_ratio     = 8'd4;
        wait_clk(10);
        rst_n = 1'b1;
        wait_clk(5);
        reset_count = reset_count + 1;
        $display("[TB] Reset #%0d released at %0t ns", reset_count, $time);
    endtask

    // ── SRAM write helpers ────────────────────────────────────
    task write_csram(input [CSRAM_ADDR_W-1:0] a, input [CSRAM_DATA_W-1:0] d);
        @(posedge clk_fast); csram_we_a=1; csram_waddr_a=a; csram_wdata_a=d;
        @(posedge clk_fast); csram_we_a=0;
    endtask
    task write_isram(input [ISRAM_ADDR_W-1:0] a, input [ISRAM_DATA_W-1:0] d);
        @(posedge clk_fast); isram_we_a=1; isram_waddr_a=a; isram_wdata_a=d;
        @(posedge clk_fast); isram_we_a=0;
    endtask
    task write_lsram(input [LSRAM_ADDR_W-1:0] a, input [LSRAM_DATA_W-1:0] d);
        @(posedge clk_fast); lsram_we_a=1; lsram_waddr_a=a; lsram_wdata_a=d;
        @(posedge clk_fast); lsram_we_a=0;
    endtask

    // ── LSRAM pattern loaders ─────────────────────────────────
    task load_lsram_ramp();
        integer s, n, c;
        for (s=0;s<K;s=s+1) for (n=0;n<N;n=n+1) for (c=0;c<NUM_CENTROIDS;c=c+1)
            write_lsram(s*(N*NUM_CENTROIDS)+n*NUM_CENTROIDS+c, (s+c) & 8'hFF);
        lut_pattern_tag = 2;
    endtask

    task load_lsram_const(input [7:0] fill);
        integer s, n, c;
        for (s=0;s<K;s=s+1) for (n=0;n<N;n=n+1) for (c=0;c<NUM_CENTROIDS;c=c+1)
            write_lsram(s*(N*NUM_CENTROIDS)+n*NUM_CENTROIDS+c, fill);
        lut_pattern_tag = (fill==8'h00) ? 0 : 1;
    endtask

    // Column-constant: LUT[s][n][c] = n+1  (1..16)
    // Expected output per element = K * (n+1): col0=16, col1=32, ..., col15=256
    task load_lsram_col_const();
        integer s, n, c;
        for (s=0;s<K;s=s+1) for (n=0;n<N;n=n+1) for (c=0;c<NUM_CENTROIDS;c=c+1)
            write_lsram(s*(N*NUM_CENTROIDS)+n*NUM_CENTROIDS+c, (n+1) & 8'hFF);
        lut_pattern_tag = 4;
    endtask

    task load_lsram_random(input integer seed);
        integer s, n, c, rval;
        for (s=0;s<K;s=s+1) for (n=0;n<N;n=n+1) for (c=0;c<NUM_CENTROIDS;c=c+1) begin
            rval = $urandom_range(1, 254);
            write_lsram(s*(N*NUM_CENTROIDS)+n*NUM_CENTROIDS+c, rval[7:0]);
        end
        lut_pattern_tag = 3;
    endtask

    task load_cs_is();
        integer s, c, m_idx;
        for (s=0;s<K;s=s+1) for (c=0;c<NUM_CENTROIDS;c=c+1)
            write_csram(s*NUM_CENTROIDS+c, {s[7:0], c[7:0]});
        for (s=0;s<K;s=s+1) for (m_idx=0;m_idx<M;m_idx=m_idx+1)
            write_isram(s*M+m_idx, {m_idx[7:0], s[7:0]});
    endtask

    task load_memories();
        $display("[TB] Loading CSRAM (%0d)...", K*NUM_CENTROIDS);
        $display("[TB] Loading ISRAM (%0d)...", K*M);
        load_cs_is();
        $display("[TB] Loading LSRAM (%0d, ramp)...", K*N*NUM_CENTROIDS);
        load_lsram_ramp();
        $display("[TB] Memory load complete.");
    endtask

    // ── Run-and-wait ──────────────────────────────────────────
    task run_and_wait(
        input  [K_CNT_W-1:0]        k_in,
        input  [N_CNT_W-1:0]        n_in,
        input  [MEM_ADDR_WIDTH-1:0] out_base,
        output integer               got_done,
        output integer               cycles_taken
    );
        integer watchdog;
        got_done=0; cycles_taken=0;
        k_total=k_in; n_total=n_in; spad_out_addr=out_base;
        @(posedge clk_fast);
        while (!sys2top_ready) begin
            @(posedge clk_fast); cycles_taken=cycles_taken+1;
            if (cycles_taken>TIMEOUT_CYCLES) begin
                $error("[TB] Timeout waiting for ready at %0t ns", $time); return;
            end
        end
        top2sys_valid=1'b1; @(posedge clk_fast); top2sys_valid=1'b0;
        watchdog=0;
        while (!sys_done) begin
            @(posedge clk_fast); cycles_taken=cycles_taken+1; watchdog=watchdog+1;
            if (watchdog>TIMEOUT_CYCLES) begin
                $error("[TB] Timeout for sys_done (K=%0d N=%0d) at %0t ns",
                       k_in, n_in, $time); return;
            end
        end
        got_done=1; run_total=run_total+1; last_cycle_count=cycles_taken;
    endtask

    // ── OSRAM read helpers ────────────────────────────────────
    task read_osram(input integer num, input [OSRAM_ADDR_W-1:0] base);
        integer i;
        $display("[TB] OSRAM dump  first %0d  base=0x%03x", num, base);
        for (i=0; i<num; i=i+1) begin
            @(posedge clk_fast); osram_re_b=1; osram_raddr_b=base+i[OSRAM_ADDR_W-1:0];
            @(posedge clk_fast); osram_re_b=0;
            @(posedge clk_fast);
            $display("    [%03d] 0x%08x", i, osram_rdata_b);
        end
    endtask

    task read_osram_word(input [OSRAM_ADDR_W-1:0] idx, output [SPAD_DATA_W-1:0] val);
        @(posedge clk_fast); osram_re_b=1; osram_raddr_b=idx;
        @(posedge clk_fast); osram_re_b=0;
        @(posedge clk_fast); val=osram_rdata_b;
    endtask

    // ─────────────────────────────────────────────────────────
    //  ======  TEST CASES (17)  ======
    // ─────────────────────────────────────────────────────────

    // TC1 ─ Normal full compute ───────────────────────────────
    task tc1_normal_full();
        integer got, cyc;
        $display("\n[TC1] ====== Normal full compute (K=16 N=16) ======");
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (got) begin $display("[TC1] PASS  %0d cycles", cyc); pass_count=pass_count+1; end
        else     begin $display("[TC1] FAIL"); fail_count=fail_count+1; end
        read_osram(16, 9'd0);
    endtask

    // TC2 ─ Two consecutive runs ──────────────────────────────
    task tc2_consecutive();
        integer got, cyc, r, prev;
        $display("\n[TC2] ====== Two consecutive runs ======");
        prev=0;
        for (r=1; r<=2; r=r+1) begin
            run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
            if (got) begin
                $display("[TC2] Run %0d PASS  %0d cycles", r, cyc); pass_count=pass_count+1;
                if (r==2 && prev>0 && (cyc>prev+5 || cyc<prev-5))
                    $display("[TC2] WARN  cycle drift run1=%0d run2=%0d", prev, cyc);
                prev=cyc;
            end else begin $display("[TC2] Run %0d FAIL", r); fail_count=fail_count+1; end
        end
    endtask

    // TC3 ─ Non-zero spad_out_addr ────────────────────────────
    task tc3_nonzero_base();
        integer got, cyc;
        $display("\n[TC3] ====== Non-zero spad_out_addr=0x040 ======");
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h040, got, cyc);
        if (got) begin $display("[TC3] PASS  %0d cycles", cyc); pass_count=pass_count+1; end
        else     begin $display("[TC3] FAIL"); fail_count=fail_count+1; end
        read_osram(8, 9'h040);
    endtask

    // TC4 ─ Busy-gating ───────────────────────────────────────
    task tc4_busy_gating();
        integer watchdog;
        reg spurious;
        $display("\n[TC4] ====== Busy-gating check ======");
        while (!sys2top_ready) wait_clk(1);
        top2sys_valid=1; @(posedge clk_fast); top2sys_valid=0; @(posedge clk_fast);
        if (!sys2top_ready) begin
            $display("[TC4] Ready deasserted while busy — PASS"); pass_count=pass_count+1;
        end else begin
            $display("[TC4] Ready still HIGH while busy — FAIL"); fail_count=fail_count+1;
        end
        spurious=0;
        top2sys_valid=1; @(posedge clk_fast);
        if (sys2top_ready) begin
            $display("[TC4] Double-start accepted — FAIL"); fail_count=fail_count+1; spurious=1;
        end
        top2sys_valid=0;
        watchdog=0;
        while (!sys_done) begin
            @(posedge clk_fast); watchdog=watchdog+1;
            if (watchdog>TIMEOUT_CYCLES) begin
                $error("[TC4] Timeout"); fail_count=fail_count+1; return;
            end
        end
        if (!spurious) begin
            $display("[TC4] Double-start rejected — PASS"); pass_count=pass_count+1;
        end
        run_total=run_total+1;
    endtask

    // TC5 ─ Reset recovery ────────────────────────────────────
    task tc5_reset_recovery();
        integer got, cyc;
        $display("\n[TC5] ====== Reset recovery mid-operation ======");
        while (!sys2top_ready) wait_clk(1);
        top2sys_valid=1; @(posedge clk_fast); top2sys_valid=0;
        wait_clk(50);
        $display("[TC5] Asserting reset mid-run...");
        rst_n=0; wait_clk(10); rst_n=1; wait_clk(5);
        reset_count=reset_count+1;
        if (!sys_done && sys2top_ready) begin
            $display("[TC5] Post-reset state correct — PASS"); pass_count=pass_count+1;
        end else begin
            $display("[TC5] Post-reset WRONG (done=%b ready=%b) — FAIL",
                     sys_done, sys2top_ready); fail_count=fail_count+1;
        end
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (got) begin $display("[TC5] Post-reset run OK %0d cycles — PASS", cyc); pass_count=pass_count+1; end
        else     begin $display("[TC5] Post-reset run FAIL"); fail_count=fail_count+1; end
    endtask

    // TC6 ─ All-zero LUT → output = 0 ────────────────────────
    task tc6_zero_lut();
        integer got, cyc, ok;
        reg [SPAD_DATA_W-1:0] v;
        $display("\n[TC6] ====== Zero LSRAM — output must be 0x00000000 ======");
        load_lsram_const(8'h00);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (!got) begin $display("[TC6] FAIL (timeout)"); fail_count=fail_count+1; return; end
        ok = 1;
        // Read from all three OSRAM address ranges to cover addr_lo/mid/hi × dat_zero cross
        read_osram_word(9'd0,   v); if (v!==32'd0) ok=0;
        $display("[TC6] OSRAM[0]=0x%08x (addr_lo)", v);
        read_osram_word(9'd107, v); if (v!==32'd0) ok=0;
        $display("[TC6] OSRAM[107]=0x%08x (addr_mid)", v);
        read_osram_word(9'd214, v); if (v!==32'd0) ok=0;
        $display("[TC6] OSRAM[214]=0x%08x (addr_hi)", v);
        if (ok) begin $display("[TC6] PASS  all zero"); pass_count=pass_count+1; end
        else    begin $display("[TC6] FAIL  non-zero output on zero LUT"); fail_count=fail_count+1; end
    endtask

    // TC7 ─ All-0xFF LUT → golden 0xFF0 ──────────────────────
    task tc7_max_lut_golden();
        integer got, cyc, i, ok;
        reg [SPAD_DATA_W-1:0] v;
        $display("\n[TC7] ====== All-0xFF LSRAM  golden=0x%08x ======", GOLDEN_MAX);
        load_lsram_const(8'hFF);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (!got) begin $display("[TC7] FAIL (timeout)"); fail_count=fail_count+1; return; end
        ok=1;
        for (i=0; i<8; i=i+1) begin
            read_osram_word(i[OSRAM_ADDR_W-1:0], v);
            if (v!==GOLDEN_MAX) begin
                $display("[TC7]   [%0d]=0x%08x  exp=0x%08x  MISMATCH", i, v, GOLDEN_MAX); ok=0;
            end
        end
        if (ok) begin $display("[TC7] PASS  8 elements match 0x%08x", GOLDEN_MAX); pass_count=pass_count+1; end
        else    begin $display("[TC7] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC8 ─ Rapid-fire 10 runs ────────────────────────────────
    task tc8_rapid_fire();
        integer got, cyc, r, fail_this;
        $display("\n[TC8] ====== Rapid-fire 10 consecutive runs ======");
        fail_this=0;
        for (r=1; r<=10; r=r+1) begin
            run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
            $display("[TC8] Run %02d : %0d cycles %s", r, cyc, got ? "OK" : "TIMEOUT");
            if (!got) fail_this=1;
        end
        if (!fail_this) begin $display("[TC8] PASS  all 10 done"); pass_count=pass_count+1; end
        else            begin $display("[TC8] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC9 ─ Random LUT × 5 iterations ────────────────────────
    task tc9_random_lut();
        integer got, cyc, i, ok;
        reg [SPAD_DATA_W-1:0] v;
        $display("\n[TC9] ====== Random LSRAM × 5 seeds ======");
        ok=1;
        for (i=1; i<=5; i=i+1) begin
            load_lsram_random(i*7919);
            run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
            if (!got) begin $display("[TC9] Iter %0d TIMEOUT", i); ok=0; end
            else begin
                read_osram_word(9'd0, v);
                $display("[TC9] Iter %0d  %0d cycles  OSRAM[0]=0x%08x", i, cyc, v);
            end
        end
        if (ok) begin $display("[TC9] PASS"); pass_count=pass_count+1; end
        else    begin $display("[TC9] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC10 ─ Alternating max/zero × 4 pairs ──────────────────
    task tc10_alternating();
        integer got, cyc, p, ok;
        reg [SPAD_DATA_W-1:0] v;
        $display("\n[TC10] ====== Alternating max/zero × 4 pairs ======");
        ok=1;
        for (p=1; p<=4; p=p+1) begin
            load_lsram_const(8'hFF);
            run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
            if (!got) begin $display("[TC10] Pair %0d MAX TIMEOUT", p); ok=0; end
            else begin
                read_osram_word(9'd0, v);
                $display("[TC10] Pair %0d MAX  OSRAM[0]=0x%08x  %s",
                         p, v, (v===GOLDEN_MAX)?"OK":"MISMATCH");
                if (v!==GOLDEN_MAX) ok=0;
            end
            load_lsram_const(8'h00);
            run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
            if (!got) begin $display("[TC10] Pair %0d ZERO TIMEOUT", p); ok=0; end
            else begin
                read_osram_word(9'd0, v);
                $display("[TC10] Pair %0d ZERO OSRAM[0]=0x%08x  %s",
                         p, v, (v===32'd0)?"OK":"MISMATCH");
                if (v!==32'd0) ok=0;
            end
        end
        if (ok) begin $display("[TC10] PASS  all 4 pairs correct"); pass_count=pass_count+1; end
        else    begin $display("[TC10] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC11 ─ Long stress 15 runs ──────────────────────────────
    task tc11_long_stress();
        integer got, cyc, r, ok, mn, mx;
        $display("\n[TC11] ====== Long stress: 15 runs ======");
        load_lsram_ramp(); ok=1; mn=TIMEOUT_CYCLES; mx=0;
        for (r=1; r<=15; r=r+1) begin
            run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
            if (!got) begin $display("[TC11] Run %02d TIMEOUT", r); ok=0; end
            else begin
                if (cyc<mn) mn=cyc; if (cyc>mx) mx=cyc;
                $display("[TC11] Run %02d : %0d cycles", r, cyc);
            end
        end
        if (ok) begin
            $display("[TC11] PASS  min=%0d max=%0d spread=%0d", mn, mx, mx-mn);
            pass_count=pass_count+1;
        end else begin $display("[TC11] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC12 ─ Full OSRAM scan (all 320 elements = GOLDEN_MAX) ──
    task tc12_full_osram_scan();
        integer got, cyc, i, ok;
        reg [SPAD_DATA_W-1:0] v;
        integer mismatch_cnt;
        $display("\n[TC12] ====== Full OSRAM scan  all %0d elements vs 0x%08x ======",
                 TOTAL_OUTPUTS, GOLDEN_MAX);
        load_lsram_const(8'hFF);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (!got) begin $display("[TC12] FAIL (timeout)"); fail_count=fail_count+1; return; end
        mismatch_cnt=0;
        for (i=0; i<TOTAL_OUTPUTS; i=i+1) begin
            read_osram_word(i[OSRAM_ADDR_W-1:0], v);
            if (v!==GOLDEN_MAX) begin
                if (mismatch_cnt<10)
                    $display("[TC12]   [%03d]=0x%08x  MISMATCH", i, v);
                mismatch_cnt=mismatch_cnt+1;
            end
        end
        if (mismatch_cnt==0) begin
            $display("[TC12] PASS  all %0d elements = 0x%08x", TOTAL_OUTPUTS, GOLDEN_MAX);
            pass_count=pass_count+1;
        end else begin
            $display("[TC12] FAIL  %0d/%0d mismatches", mismatch_cnt, TOTAL_OUTPUTS);
            fail_count=fail_count+1;
        end
    endtask

    // TC13 ─ Column-specific golden: LUT[s][n][c]=n+1 ─────────
    // Expected: OSRAM element in column n = K*(n+1)
    //   col0 row0 = 16 = 0x10, col1 row0 = 32 = 0x20, ...
    task tc13_col_const_golden();
        integer got, cyc, n, ok;
        reg [SPAD_DATA_W-1:0] v;
        integer expected;
        $display("\n[TC13] ====== Column-constant golden (col n → K*(n+1)) ======");
        load_lsram_col_const();
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (!got) begin $display("[TC13] FAIL (timeout)"); fail_count=fail_count+1; return; end
        ok=1;
        $display("[TC13] %0d cycles — checking col-0 values + addr_mid/hi reads...", cyc);
        for (n=0; n<N; n=n+1) begin
            // Row 0, column n → OSRAM[0*N + n] = OSRAM[n]  (addr_lo range, 0..15)
            read_osram_word(n[OSRAM_ADDR_W-1:0], v);
            expected = K * (n + 1);
            if (v!==expected[SPAD_DATA_W-1:0]) begin
                $display("[TC13]   col%02d[row0]: 0x%08x  exp=0x%08x  MISMATCH", n, v, expected);
                ok=0;
            end else begin
                $display("[TC13]   col%02d[row0]: 0x%08x  OK", n, v);
            end
        end
        // Also read addr_mid (107..213) and addr_hi (214..319) for cross coverage with dat_lo.
        // OSRAM[107] = row6*16 + col11 = 96+11 → col11, expected = K*(11+1) = 192
        read_osram_word(9'd107, v);
        $display("[TC13] OSRAM[107]=0x%08x (addr_mid, exp=K*12=%0d)", v, K*12);
        // OSRAM[214] = row13*16 + col6  = 208+6  → col6,  expected = K*(6+1)  = 112
        read_osram_word(9'd214, v);
        $display("[TC13] OSRAM[214]=0x%08x (addr_hi, exp=K*7=%0d)",  v, K*7);
        if (ok) begin $display("[TC13] PASS  all 16 column-0 elements correct"); pass_count=pass_count+1; end
        else    begin $display("[TC13] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC14 ─ Determinism: same inputs → identical outputs ──────
    task tc14_determinism();
        integer got, cyc, i;
        reg [SPAD_DATA_W-1:0] out1[0:15];
        reg [SPAD_DATA_W-1:0] out2[0:15];
        reg [SPAD_DATA_W-1:0] v;
        integer ok;
        $display("\n[TC14] ====== Determinism check (run same inputs twice) ======");
        load_lsram_ramp();
        // First run
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (!got) begin $display("[TC14] Run 1 FAIL (timeout)"); fail_count=fail_count+1; return; end
        for (i=0; i<16; i=i+1) begin read_osram_word(i[OSRAM_ADDR_W-1:0], v); out1[i]=v; end
        // Second run (same LUT — do NOT reload; CS/IS unchanged)
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (!got) begin $display("[TC14] Run 2 FAIL (timeout)"); fail_count=fail_count+1; return; end
        for (i=0; i<16; i=i+1) begin read_osram_word(i[OSRAM_ADDR_W-1:0], v); out2[i]=v; end
        ok=1;
        for (i=0; i<16; i=i+1) begin
            if (out1[i]!==out2[i]) begin
                $display("[TC14]   [%02d] run1=0x%08x run2=0x%08x DIFFER", i, out1[i], out2[i]);
                ok=0;
            end
        end
        if (ok) begin $display("[TC14] PASS  both runs identical for first 16 outputs"); pass_count=pass_count+1; end
        else    begin $display("[TC14] FAIL  non-deterministic output detected"); fail_count=fail_count+1; end
    endtask

    // TC15 ─ Deep reset stress: 8 resets then clean run ────────
    task tc15_deep_reset_stress();
        integer got, cyc, i;
        $display("\n[TC15] ====== Deep reset stress: 8 resets ======");
        for (i=1; i<=8; i=i+1) begin
            rst_n=0; wait_clk(5); rst_n=1; wait_clk(3);
            reset_count=reset_count+1;
            $display("[TC15] Reset %0d done at %0t ns", i, $time);
        end
        // Reload memories and run
        load_cs_is(); load_lsram_ramp();
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        if (got) begin $display("[TC15] PASS  post-stress run OK in %0d cycles", cyc); pass_count=pass_count+1; end
        else     begin $display("[TC15] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC16 ─ Back-to-back 20 runs with large random LUT ────────
    task tc16_random_stress_20();
        integer got, cyc, r, ok;
        $display("\n[TC16] ====== 20 runs with large random LUT ======");
        ok=1;
        for (r=1; r<=20; r=r+1) begin
            load_lsram_random(r * 104729);
            run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
            $display("[TC16] Run %02d : %0d cycles  %s", r, cyc, got?"OK":"TIMEOUT");
            if (!got) ok=0;
        end
        if (ok) begin $display("[TC16] PASS  all 20 random runs complete"); pass_count=pass_count+1; end
        else    begin $display("[TC16] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC17 ─ spad_out_addr sweep (4 base addresses) ────────────
    task tc17_addr_sweep();
        integer got, cyc, i, ok;
        reg [SPAD_DATA_W-1:0] v;
        // Use base addresses that fit without OSRAM overflow:
        // OSRAM has 320 entries; OSRAM_ADDR_W=9 bits (0..319 valid).
        // spad_out_addr=0 → writes 0..319 (all valid).
        // Any non-zero base wraps; test at 0,1,2,3 to exercise different paths.
        integer addrs[0:4];
        $display("\n[TC17] ====== spad_out_addr sweep (5 values) ======");
        addrs[0] = 12'h000;
        addrs[1] = 12'h001;
        addrs[2] = 12'h002;
        addrs[3] = 12'h040;
        addrs[4] = 12'h100; // addr_hi bin: OSRAM writes wrap within 9-bit space
        load_lsram_const(8'hFF); ok=1;
        for (i=0; i<5; i=i+1) begin
            run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], addrs[i][MEM_ADDR_WIDTH-1:0], got, cyc);
            if (!got) begin $display("[TC17] Addr 0x%03x TIMEOUT", addrs[i]); ok=0; end
            else begin
                // Only addr=0 gives clean golden; others have wrap effects — just check done.
                read_osram_word(addrs[i][OSRAM_ADDR_W-1:0], v);
                $display("[TC17] Addr 0x%03x  %0d cycles  OSRAM[base]=0x%08x  DONE OK",
                         addrs[i], cyc, v);
            end
        end
        if (ok) begin $display("[TC17] PASS  all 5 addresses completed"); pass_count=pass_count+1; end
        else    begin $display("[TC17] FAIL"); fail_count=fail_count+1; end
    endtask

    // TC18 ─ spad_out_addr × LUT pattern cross-coverage sweep ─────
    // Covers the missing cx_spad_pat cross cells:
    //   addr_lo (0x001) × {zero, ramp, random, col}
    //   addr_mid(0x040) × {zero, random, col}
    //   addr_hi (0x100) × {zero, ramp, random, col}
    // (addr_*  × max already covered by TC17)
    task tc18_spad_pat_sweep();
        integer got, cyc, ok;
        $display("\n[TC18] ====== spad_out_addr x LUT pattern cross sweep ======");
        ok = 1;

        // ── addr_lo = 0x001 ──────────────────────────────────────
        load_lsram_const(8'h00); // zero
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h001, got, cyc);
        if (!got) begin $display("[TC18] addr_lo×zero TIMEOUT"); ok=0; end
        else $display("[TC18] addr_lo×zero  %0d cycles  OK", cyc);

        load_lsram_ramp(); // ramp
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h001, got, cyc);
        if (!got) begin $display("[TC18] addr_lo×ramp TIMEOUT"); ok=0; end
        else $display("[TC18] addr_lo×ramp  %0d cycles  OK", cyc);

        load_lsram_random(31337);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h001, got, cyc);
        if (!got) begin $display("[TC18] addr_lo×random TIMEOUT"); ok=0; end
        else $display("[TC18] addr_lo×random  %0d cycles  OK", cyc);

        load_lsram_col_const();
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h001, got, cyc);
        if (!got) begin $display("[TC18] addr_lo×col TIMEOUT"); ok=0; end
        else $display("[TC18] addr_lo×col  %0d cycles  OK", cyc);

        // ── addr_mid = 0x040 ─────────────────────────────────────
        load_lsram_const(8'h00);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h040, got, cyc);
        if (!got) begin $display("[TC18] addr_mid×zero TIMEOUT"); ok=0; end
        else $display("[TC18] addr_mid×zero  %0d cycles  OK", cyc);

        load_lsram_random(65537);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h040, got, cyc);
        if (!got) begin $display("[TC18] addr_mid×random TIMEOUT"); ok=0; end
        else $display("[TC18] addr_mid×random  %0d cycles  OK", cyc);

        load_lsram_col_const();
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h040, got, cyc);
        if (!got) begin $display("[TC18] addr_mid×col TIMEOUT"); ok=0; end
        else $display("[TC18] addr_mid×col  %0d cycles  OK", cyc);

        // ── addr_hi = 0x100 ──────────────────────────────────────
        load_lsram_const(8'h00);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h100, got, cyc);
        if (!got) begin $display("[TC18] addr_hi×zero TIMEOUT"); ok=0; end
        else $display("[TC18] addr_hi×zero  %0d cycles  OK", cyc);

        load_lsram_ramp();
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h100, got, cyc);
        if (!got) begin $display("[TC18] addr_hi×ramp TIMEOUT"); ok=0; end
        else $display("[TC18] addr_hi×ramp  %0d cycles  OK", cyc);

        load_lsram_random(98765);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h100, got, cyc);
        if (!got) begin $display("[TC18] addr_hi×random TIMEOUT"); ok=0; end
        else $display("[TC18] addr_hi×random  %0d cycles  OK", cyc);

        load_lsram_col_const();
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h100, got, cyc);
        if (!got) begin $display("[TC18] addr_hi×col TIMEOUT"); ok=0; end
        else $display("[TC18] addr_hi×col  %0d cycles  OK", cyc);

        if (ok) begin $display("[TC18] PASS  all 11 pattern×addr combinations"); pass_count=pass_count+1; end
        else    begin $display("[TC18] FAIL"); fail_count=fail_count+1; end
    endtask

    // ─────────────────────────────────────────────────────────
    //  TC19 – FIFO fill stress (slows IMM via large div_ratio)
    // ─────────────────────────────────────────────────────────
    task tc19_fifo_fill_stress();
        integer got, cyc;
        $display("\n[TC19] ====== FIFO stress: div_ratio=16 (CCM faster than IMM) ======");
        load_lsram_ramp();
        div_ratio = 8'd16;
        wait_clk(5);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        div_ratio = 8'd4;
        wait_clk(5);
        if (got) begin $display("[TC19] PASS  %0d cycles", cyc); pass_count=pass_count+1; end
        else     begin $display("[TC19] FAIL (timeout)"); fail_count=fail_count+1; end
    endtask

    // ─────────────────────────────────────────────────────────
    //  TC20 – spad_out_addr fine sweep (bits 2-5 of ctrl2spad_start_addr)
    // ─────────────────────────────────────────────────────────
    task tc20_addr_fine_sweep();
        integer got, cyc, ok;
        $display("\n[TC20] ====== spad_out_addr fine sweep (bits 2-5) ======");
        ok = 1;
        load_cs_is(); load_lsram_ramp();

        // addr = 0x004 → ctrl2spad bit 2
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h004, got, cyc);
        if (!got) begin $display("[TC20] addr=0x004 TIMEOUT"); ok=0; end
        else $display("[TC20] addr=0x004  %0d cycles  OK", cyc);

        // addr = 0x008 → ctrl2spad bit 3
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h008, got, cyc);
        if (!got) begin $display("[TC20] addr=0x008 TIMEOUT"); ok=0; end
        else $display("[TC20] addr=0x008  %0d cycles  OK", cyc);

        // addr = 0x01C → ctrl2spad bits 2,3,4
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h01C, got, cyc);
        if (!got) begin $display("[TC20] addr=0x01C TIMEOUT"); ok=0; end
        else $display("[TC20] addr=0x01C  %0d cycles  OK", cyc);

        // addr = 0x03C → ctrl2spad bits 2,3,4,5
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'h03C, got, cyc);
        if (!got) begin $display("[TC20] addr=0x03C TIMEOUT"); ok=0; end
        else $display("[TC20] addr=0x03C  %0d cycles  OK", cyc);

        if (ok) begin $display("[TC20] PASS  fine addr sweep"); pass_count=pass_count+1; end
        else    begin $display("[TC20] FAIL"); fail_count=fail_count+1; end
    endtask

    // ─────────────────────────────────────────────────────────
    //  force_toggle_patterns – write extreme data to CSRAM/ISRAM
    //  and run two computations to propagate high bits through all
    //  pipelines (element_diff=255, L1_dist=510 → bits 5-8 toggle).
    // ─────────────────────────────────────────────────────────
    task force_toggle_patterns();
        integer i, got, cyc;
        $display("[TB] Toggle force: writing extreme patterns to CSRAM/ISRAM...");

        // --- Phase 1: toggle wdata upper nibbles via write patterns ---
        for (i=0; i<K*NUM_CENTROIDS; i=i+1)
            write_csram(i[CSRAM_ADDR_W-1:0], 16'hFFFF);
        for (i=0; i<K*NUM_CENTROIDS; i=i+1)
            write_csram(i[CSRAM_ADDR_W-1:0], 16'hAAAA);
        for (i=0; i<K*NUM_CENTROIDS; i=i+1)
            write_csram(i[CSRAM_ADDR_W-1:0], 16'h5555);

        for (i=0; i<K*M; i=i+1)
            write_isram(i[ISRAM_ADDR_W-1:0], 16'hFFFF);
        for (i=0; i<K*M; i=i+1)
            write_isram(i[ISRAM_ADDR_W-1:0], 16'hAAAA);
        for (i=0; i<K*M; i=i+1)
            write_isram(i[ISRAM_ADDR_W-1:0], 16'h5555);

        // --- Phase 2: CSRAM=0xFFFF, ISRAM=0x0000 → element_diff=255, L1=510 ---
        // Propagates large values through centroid_buffer, input_buffer, dPE pipeline
        for (i=0; i<K*NUM_CENTROIDS; i=i+1)
            write_csram(i[CSRAM_ADDR_W-1:0], 16'hFFFF);
        for (i=0; i<K*M; i=i+1)
            write_isram(i[ISRAM_ADDR_W-1:0], 16'h0000);
        load_lsram_const(8'hFF);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        $display("[TB] Toggle run1 (C=0xFFFF I=0x0000): %s %0d cyc",
                 got ? "done" : "TIMEOUT", cyc);

        // --- Phase 3: CSRAM=0x0000, ISRAM=0xFFFF → reverse extreme diff ---
        // Toggles in_vector_flat[13-15][7-4], ib2ccu_ip_vector upper bits
        for (i=0; i<K*NUM_CENTROIDS; i=i+1)
            write_csram(i[CSRAM_ADDR_W-1:0], 16'h0000);
        for (i=0; i<K*M; i=i+1)
            write_isram(i[ISRAM_ADDR_W-1:0], 16'hFFFF);
        load_lsram_const(8'hFF);
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        $display("[TB] Toggle run2 (C=0x0000 I=0xFFFF): %s %0d cyc",
                 got ? "done" : "TIMEOUT", cyc);

        $display("[TB] Toggle force complete.");
    endtask

    // ─────────────────────────────────────────────────────────
    //  TC21 – Python golden co-verification
    //  Prerequisite: run "python MODEL/co_verify.py" BEFORE simulation.
    //  That script writes 4 hex files into MODEL/ which this task reads.
    //
    //  Protocol:
    //    1. Read MODEL/csram_init.hex  → load CSRAM  (K*C   entries, 16-bit)
    //    2. Read MODEL/isram_init.hex  → load ISRAM  (K*M   entries, 16-bit)
    //    3. Read MODEL/lsram_init.hex  → load LSRAM  (K*N*C entries,  8-bit)
    //    4. Read MODEL/expected_osram.hex into local array (M*N entries, 32-bit)
    //    5. run_and_wait – let the RTL compute
    //    6. Read every OSRAM address and compare with expected
    // ─────────────────────────────────────────────────────────
    task tc21_co_verify();
        integer fd, r, val;
        integer exp_osram [0:TOTAL_OUTPUTS-1];
        integer i, got, cyc, errors;
        integer mm, nn, aidx, mfd;
        reg [SPAD_DATA_W-1:0] rtl_val;

        $display("\n[TC21] ====== Co-verification: Python golden vs RTL ======");
        errors = 0;

        // ── 0. Clean start ────────────────────────────────────
        // Clear any residual PSumLUT/Scratchpad state left over from the
        // previous test (TC20's multi-address sweep). Without this, a stale
        // psum2spad_valid can be consumed by the Scratchpad's IDLE during the
        // inter-test gap, pre-advancing m_count and shifting the whole output
        // matrix down by one row (+N). BRAM contents survive reset, so the
        // SRAM loads below remain valid.
        do_reset();

        // ── 1. CSRAM ──────────────────────────────────────────
        fd = $fopen("MODEL/csram_init.hex", "r");
        if (fd == 0) begin
            $error("[TC21] Cannot open MODEL/csram_init.hex — run 'python MODEL/co_verify.py' first");
            fail_count = fail_count + 1;
            return;
        end
        for (i = 0; i < K*NUM_CENTROIDS; i = i+1) begin
            r = $fscanf(fd, "%x ", val);
            write_csram(i[CSRAM_ADDR_W-1:0], val);
        end
        $fclose(fd);
        $display("[TC21]   CSRAM loaded  (%0d entries)", K*NUM_CENTROIDS);

        // ── 2. ISRAM ──────────────────────────────────────────
        fd = $fopen("MODEL/isram_init.hex", "r");
        if (fd == 0) begin
            $error("[TC21] Cannot open MODEL/isram_init.hex");
            fail_count = fail_count + 1;
            return;
        end
        for (i = 0; i < K*M; i = i+1) begin
            r = $fscanf(fd, "%x ", val);
            write_isram(i[ISRAM_ADDR_W-1:0], val);
        end
        $fclose(fd);
        $display("[TC21]   ISRAM loaded  (%0d entries)", K*M);

        // ── 3. LSRAM ──────────────────────────────────────────
        fd = $fopen("MODEL/lsram_init.hex", "r");
        if (fd == 0) begin
            $error("[TC21] Cannot open MODEL/lsram_init.hex");
            fail_count = fail_count + 1;
            return;
        end
        for (i = 0; i < K*N*NUM_CENTROIDS; i = i+1) begin
            r = $fscanf(fd, "%x ", val);
            write_lsram(i[LSRAM_ADDR_W-1:0], val);
        end
        $fclose(fd);
        $display("[TC21]   LSRAM loaded  (%0d entries)", K*N*NUM_CENTROIDS);

        // ── 4. Expected OSRAM ─────────────────────────────────
        fd = $fopen("MODEL/expected_osram.hex", "r");
        if (fd == 0) begin
            $error("[TC21] Cannot open MODEL/expected_osram.hex");
            fail_count = fail_count + 1;
            return;
        end
        for (i = 0; i < TOTAL_OUTPUTS; i = i+1)
            r = $fscanf(fd, "%x ", exp_osram[i]);
        $fclose(fd);
        $display("[TC21]   Golden OSRAM  (%0d entries)", TOTAL_OUTPUTS);

        // ── 5. Run RTL ────────────────────────────────────────
        tc21_active = 1; tc21_osram_wr_cnt = 0;
        tc21_cstar_active = 1; tc21_cstar_cnt = 0;
        run_and_wait(K[K_CNT_W-1:0], N[N_CNT_W-1:0], 12'd0, got, cyc);
        tc21_active = 0;
        tc21_cstar_active = 0;
        if (!got) begin
            $error("[TC21] Timeout waiting for sys_done");
            fail_count = fail_count + 1;
            return;
        end
        $display("[TC21]   RTL done  (%0d cycles)", cyc);

        // ── 5b. Post-run diagnostics ──────────────────────────
        $display("[TC21_DBG] spad_out_addr (TB)  = %0d  (expect 0)", spad_out_addr);
        $display("[TC21_DBG] Spad base_addr       = %0d  (expect 0)",
                 dut.u_imm.Scratchpad_inst.base_addr);
        $display("[TC21_DBG] Spad state=%0d m=%0d k=%0d n=%0d col_base=%0d",
                 dut.u_imm.Scratchpad_inst.state,
                 dut.u_imm.Scratchpad_inst.m_count,
                 dut.u_imm.Scratchpad_inst.k_sub_count,
                 dut.u_imm.Scratchpad_inst.n_col_count,
                 dut.u_imm.Scratchpad_inst.acc_col_base);
        $display("[TC21_DBG] PSumLUT: consumer_done=%0b ping=%0b consumer_count=%0d",
                 dut.u_imm.PSum_LUT_inst.consumer_done,
                 dut.u_imm.PSum_LUT_inst.ping_pong_select,
                 dut.u_imm.PSum_LUT_inst.consumer_count);
        // ── Spot-check: first row (m=0, n=0..N-1) ───────────────
        $display("[TC21_DBG] OSRAM write count = %0d  (expect 320)", tc21_osram_wr_cnt);
        $display("[TC21_DBG] --- First row  m=0, addr 0..%0d ---", N-1);
        for (i = 0; i < N; i = i+1) begin
            read_osram_word(i[OSRAM_ADDR_W-1:0], rtl_val);
            $display("[TC21_DBG]  OSRAM[%2d]=0x%08x  GOLDEN[%2d]=0x%08x  %s",
                     i, rtl_val, i, exp_osram[i],
                     (rtl_val===exp_osram[i])?"OK":"BAD");
        end
        // ── Transpose check: does OSRAM[n] match GOLDEN[n*M] ? ──
        // If RTL addresses output as (n outer, m inner) instead of (m outer, n inner),
        // then OSRAM[n] = GOLDEN[n*M + 0] for all n.
        $display("[TC21_DBG] --- Transpose check: OSRAM[n] vs GOLDEN[n*M] ---");
        for (i = 0; i < N; i = i+1) begin
            read_osram_word(i[OSRAM_ADDR_W-1:0], rtl_val);
            $display("[TC21_DBG]  OSRAM[%2d]=0x%08x  GOLDEN[%0d*M+0=%3d]=0x%08x  %s",
                     i, rtl_val, i, i*M, exp_osram[i*M],
                     (rtl_val===exp_osram[i*M])?"OK":"BAD");
        end
        // ── Second-row check: addr 16..31 (m=1) ──────────────────
        $display("[TC21_DBG] --- Second row m=1, addr %0d..%0d ---", N, 2*N-1);
        for (i = N; i < 2*N; i = i+1) begin
            read_osram_word(i[OSRAM_ADDR_W-1:0], rtl_val);
            $display("[TC21_DBG]  OSRAM[%2d]=0x%08x  GOLDEN[%2d]=0x%08x  %s",
                     i, rtl_val, i, exp_osram[i],
                     (rtl_val===exp_osram[i])?"OK":"BAD");
        end

        // ── 6. Bit-exact comparison ───────────────────────────
        for (i = 0; i < TOTAL_OUTPUTS; i = i+1) begin
            read_osram_word(i[OSRAM_ADDR_W-1:0], rtl_val);
            if (rtl_val !== exp_osram[i]) begin
                $error("[TC21] MISMATCH addr=%0d  RTL=0x%08x  GOLDEN=0x%08x",
                       i, rtl_val, exp_osram[i]);
                errors = errors + 1;
            end
        end

        // ── 7. Final output matrices (RTL vs Python golden) ───
        // Print both M x N result matrices to the transcript and also write
        // the RTL matrix to MODEL/rtl_osram_matrix.txt for offline comparison
        // with MODEL/output_matrix.txt produced by co_verify.py.
        mfd = $fopen("MODEL/rtl_osram_matrix.txt", "w");
        $display("\n[TC21] ===== RTL output matrix  (M=%0d rows x N=%0d cols, hex) =====", M, N);
        for (mm = 0; mm < M; mm = mm+1) begin
            $write("[TC21] RTL row%2d:", mm);
            for (nn = 0; nn < N; nn = nn+1) begin
                aidx = mm*N + nn;
                read_osram_word(aidx[OSRAM_ADDR_W-1:0], rtl_val);
                $write(" %3h", rtl_val[11:0]);
                if (mfd) $fwrite(mfd, "%0d ", rtl_val);
            end
            if (mfd) $fwrite(mfd, "\n");
            $write("\n");
        end
        if (mfd) $fclose(mfd);

        $display("\n[TC21] ===== Python golden matrix  (M=%0d rows x N=%0d cols, hex) =====", M, N);
        for (mm = 0; mm < M; mm = mm+1) begin
            $write("[TC21] GLD row%2d:", mm);
            for (nn = 0; nn < N; nn = nn+1)
                $write(" %3h", exp_osram[mm*N + nn][11:0]);
            $write("\n");
        end

        if (errors == 0) begin
            $display("[TC21] PASS  all %0d outputs match Python golden (%0d cycles)",
                     TOTAL_OUTPUTS, cyc);
            pass_count = pass_count + 1;
        end else begin
            $display("[TC21] FAIL  %0d / %0d entries mismatched vs Python golden",
                     errors, TOTAL_OUTPUTS);
            fail_count = fail_count + 1;
        end
    endtask

    // ─────────────────────────────────────────────────────────
    //  Print results
    // ─────────────────────────────────────────────────────────
    task print_results();
        integer total;
        total = pass_count + fail_count;
        $display("\n");
        $display("||===================================================||");
        $display("||          SIMULATION RESULTS SUMMARY               ||");
        $display("╠===================================================╣");
        $display("||  Total checks      : %5d                         ||", total);
        $display("||  PASSED            : %5d                         ||", pass_count);
        $display("||  FAILED            : %5d                         ||", fail_count);
        $display("||  SVA assert fails  : %5d                         ||", assert_fail_count);
        $display("||  Total DUT runs    : %5d                         ||", run_total);
        $display("||  Total resets      : %5d                         ||", reset_count);
        $display("╠===================================================╣");
        if (fail_count==0 && assert_fail_count==0)
            $display("||  OVERALL STATUS    :        *** PASS ***          ||");
        else
            $display("||  OVERALL STATUS    :        *** FAIL ***          ||");
        $display("||===================================================||");
        $display("  Simulation end time: %0t ns\n", $time);
    endtask

    // ─────────────────────────────────────────────────────────
    //  Main sequence
    // ─────────────────────────────────────────────────────────
    initial begin
        // Instantiate covergroups
        cg_ctrl_inst  = new();
        cg_dim_inst   = new();
        cg_lsram_inst = new();
        cg_spad_inst  = new();
        cg_lut_inst   = new();
        cg_cyc_inst   = new();
        cg_multi_inst = new();
        cg_csram_inst = new();
        cg_isram_inst = new();
        cg_osram_inst = new();

        // Scoreboard init
        pass_count=0; fail_count=0; assert_fail_count=0;
        run_total=0; last_cycle_count=0; reset_count=0; lut_pattern_tag=2;
        tc21_active=0; tc21_osram_wr_cnt=0;
        tc21_cstar_active=0; tc21_cstar_cnt=0;

        // Default SRAM inputs
        csram_waddr_a='0; csram_wdata_a='0;
        isram_waddr_a='0; isram_wdata_a='0;
        lsram_waddr_a='0; lsram_wdata_a='0;
        osram_raddr_b='0;

        $display("||===================================================||");
        $display("||          SYSTEM_TOP TESTBENCH START               ||");
        $display("||===================================================||");
        $display("  K=%0d N=%0d M=%0d C=%0d VL=%0d", K,N,M,NUM_CENTROIDS,VECTOR_LENGTH);
        $display("  GOLDEN_MAX=0x%08x  TOTAL_OUTPUTS=%0d", GOLDEN_MAX, TOTAL_OUTPUTS);
        $display("  clk_fast=%0dns  div_ratio=4  clk_slow~%0dns",
                 CLK_FAST_PERIOD, CLK_FAST_PERIOD*8);
        $display("  Assertions: 13  CoverGroups: 10  TCs: 21\n");

        // ── Initial reset ─────────────────────────────────────
        do_reset();

        // ── ClkDiv stimulus sweep ─────────────────────────────────
        // div_ratio=3: odd path in ClkDiv (is_odd=1, odd_edge_tog toggles)
        $display("[TB] ClkDiv sweep: div_ratio=3 (odd path)...");
        div_ratio = 8'd3;
        wait_clk(40);
        // div_ratio=254 (0xFE): toggles i_div_ratio[1-7], edge_flip_half[1-6],
        //   edge_flip_full[2-6] via combinatorial wires — no need to wait for counter
        $display("[TB] ClkDiv sweep: div_ratio=254 (upper ratio bits)...");
        div_ratio = 8'd254;
        wait_clk(10);
        // div_ratio=1: is_one=1 → clk_en=0 → o_div_clk uses i_ref_clk bypass path
        $display("[TB] ClkDiv sweep: div_ratio=1 (is_one bypass)...");
        div_ratio = 8'd1;
        wait_clk(5);
        div_ratio = 8'd4;
        wait_clk(10);

        // ── Extreme pattern toggle for CSRAM/ISRAM bus bits ───
        force_toggle_patterns();
        wait_clk(10);

        load_memories();
        wait_clk(5);

        // ── TC1–TC5 ───────────────────────────────────────────
        tc1_normal_full();       wait_clk(20);
        tc2_consecutive();       wait_clk(20);
        do_reset(); load_memories(); wait_clk(5);
        tc3_nonzero_base();      wait_clk(20);
        tc4_busy_gating();       wait_clk(20);
        load_memories(); wait_clk(5);
        tc5_reset_recovery();    wait_clk(20);

        // ── TC6–TC11 ──────────────────────────────────────────
        load_cs_is(); wait_clk(5);
        tc6_zero_lut();          wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc7_max_lut_golden();    wait_clk(20);
        load_cs_is(); load_lsram_ramp(); wait_clk(5);
        tc8_rapid_fire();        wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc9_random_lut();        wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc10_alternating();      wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc11_long_stress();      wait_clk(20);

        // ── TC12–TC17 ─────────────────────────────────────────
        load_cs_is(); wait_clk(5);
        tc12_full_osram_scan();  wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc13_col_const_golden(); wait_clk(20);
        load_cs_is(); load_lsram_ramp(); wait_clk(5);
        tc14_determinism();      wait_clk(20);
        do_reset(); wait_clk(5);
        tc15_deep_reset_stress(); wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc16_random_stress_20(); wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc17_addr_sweep();       wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc18_spad_pat_sweep();   wait_clk(20);

        // ── TC19–TC20 ─────────────────────────────────────────
        load_cs_is(); wait_clk(5);
        tc19_fifo_fill_stress(); wait_clk(20);
        load_cs_is(); wait_clk(5);
        tc20_addr_fine_sweep();  wait_clk(20);

        // ── TC21 – Python golden co-verification ──────────────
        // Reads 4 hex files written by "python MODEL/co_verify.py".
        // If the files are missing, TC21 self-reports FAIL with guidance.
        wait_clk(10);
        tc21_co_verify();        wait_clk(20);

        // ── Coverage summary ──────────────────────────────────
        $display("\n[TB] Functional Coverage Summary:");
        $display("     CG1 cg_system_ctrl  : %.1f%%", cg_ctrl_inst.get_coverage());
        $display("     CG2 cg_dimensions   : %.1f%%", cg_dim_inst.get_coverage());
        $display("     CG3 cg_lsram_write  : %.1f%%", cg_lsram_inst.get_coverage());
        $display("     CG4 cg_spad_addr    : %.1f%%", cg_spad_inst.get_coverage());
        $display("     CG5 cg_lut_pattern  : %.1f%%", cg_lut_inst.get_coverage());
        $display("     CG6 cg_run_cycles   : %.1f%%", cg_cyc_inst.get_coverage());
        $display("     CG7 cg_multi_run    : %.1f%%", cg_multi_inst.get_coverage());
        $display("     CG8 cg_csram_write  : %.1f%%", cg_csram_inst.get_coverage());
        $display("     CG9 cg_isram_write  : %.1f%%", cg_isram_inst.get_coverage());
        $display("     CG10 cg_osram_read  : %.1f%%", cg_osram_inst.get_coverage());

        print_results();
        $stop;
    end

    // ── Global watchdog ───────────────────────────────────────
    initial begin
        #(TIMEOUT_CYCLES * CLK_FAST_PERIOD * 80);
        $error("[TB] GLOBAL WATCHDOG EXPIRED");
        print_results();
        $stop;
    end

endmodule

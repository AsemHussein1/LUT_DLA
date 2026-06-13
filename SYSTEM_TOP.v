// =============================================================
//  SYSTEM_TOP — Full System Integration
//
//  Dual-clock architecture:
//    clk_fast : CCM (centroid_buffer, input_buffer, CCU), ccm_controller
//    clk_slow : IMM (PSumLUT, Scratchpad), IMM_CTRL
//               generated from clk_fast by ClkDiv
//
//  Data flow:
//    Host     ──write──► CSRAM / ISRAM / LSRAM
//    [clk_fast] ccm_controller → CCM → Async_FIFO
//    [clk_slow] IMM_CTRL → IMM/PSumLUT (reads LSRAM, pops FIFO) → Scratchpad
//    Scratchpad ──write──► OSRAM ──read──► Host
//
//  CDC crossings:
//    top2sys_valid  (fast → slow)  : cdc_pulse_sync → IMM_CTRL start
//    imm_done       (slow → fast)  : cdc_pulse_sync → sys_done output
//    FIFO indices   (fast → slow)  : Async_fifo (W_clk=fast, R_clk=slow)
//    LSRAM          (Port A = fast write, Port B = slow read) : TDP BRAM
//    OSRAM          (Port A = slow write, Port B = fast read) : TDP BRAM
//
//  Memory layout:
//    CSRAM : K × NUM_CENTROIDS entries, entry = VALUE_WIDTH × VECTOR_LENGTH bits
//    ISRAM : K × M entries,             entry = VALUE_WIDTH × VECTOR_LENGTH bits
//    LSRAM : K × N × NUM_CENTROIDS entries, entry = VALUE_WIDTH bits
//    OSRAM : M × N entries,             entry = SPAD_DATA_W bits
// =============================================================

`timescale 1ns / 1ps

module SYSTEM_TOP #(
    // ── Core architecture ────────────────────────────────────
    parameter NUM_CENTROIDS    = 16,          // C: centroids per subspace
    parameter VECTOR_LENGTH    = 2,           // VL: elements per centroid/vector
    parameter VALUE_WIDTH      = 8,           // bits per element
    parameter M                = 20,          // rows per subspace (input depth)
    parameter K                = 16,          // number of subspaces
    parameter N                = 16,          // output columns

    // ── Memory address widths ────────────────────────────────
    // Each computed from the number of entries in that SRAM.
    parameter CSRAM_ADDR_W     = $clog2(K * NUM_CENTROIDS),           // 8  (256 entries)
    parameter ISRAM_ADDR_W     = $clog2(K * M),                        // 9  (320 entries)
    parameter LSRAM_ADDR_W     = $clog2(K * N * NUM_CENTROIDS),        // 12 (4096 entries)
    parameter OSRAM_ADDR_W     = $clog2(M * N),                        // 9  (320 entries)

    // Unified address width for IMM / IMM_CTRL — must fit LSRAM
    parameter MEM_ADDR_WIDTH   = LSRAM_ADDR_W,                         // 12

    // ── Memory data widths ───────────────────────────────────
    parameter CSRAM_DATA_W     = VALUE_WIDTH * VECTOR_LENGTH,           // 16
    parameter ISRAM_DATA_W     = VALUE_WIDTH * VECTOR_LENGTH,           // 16
    parameter LSRAM_DATA_W     = VALUE_WIDTH,                           // 8
    parameter SPAD_DATA_W      = 32,                                    // accumulator

    // ── FIFO ─────────────────────────────────────────────────
    parameter FIFO_DEPTH       = 256,
    parameter CENTROID_IDX_W   = $clog2(NUM_CENTROIDS),                // 4

    // ── Clock divider ─────────────────────────────────────────
    parameter DIV_RATIO_W      = 8,

    // ── Derived counter widths ────────────────────────────────
    parameter K_CNT_W          = $clog2(K + 1),
    parameter N_CNT_W          = $clog2(N + 1)
)(
    // ── Clocking & Reset ─────────────────────────────────────
    input  wire                        clk_fast,
    input  wire                        rst_n,
    input  wire [DIV_RATIO_W-1:0]      div_ratio,           // ClkDiv ratio

    // ── System Handshake (clk_fast domain) ───────────────────
    input  wire                        top2sys_valid,        // 1-cycle start pulse
    output wire                        sys2top_ready,        // high when fully idle
    output wire                        sys_done,             // 1-cycle done pulse (fast domain)

    // ── Runtime loop bounds ──────────────────────────────────
    input  wire [K_CNT_W-1:0]          k_total,             // runtime subspaces (≤ K)
    input  wire [N_CNT_W-1:0]          n_total,             // runtime columns   (≤ N)
    input  wire [MEM_ADDR_WIDTH-1:0]   spad_out_addr,       // OSRAM start for streaming

    // ── CSRAM Port A: host writes centroid data (clk_fast) ───
    input  wire                        csram_we_a,
    input  wire [CSRAM_ADDR_W-1:0]     csram_waddr_a,
    input  wire [CSRAM_DATA_W-1:0]     csram_wdata_a,

    // ── ISRAM Port A: host writes input vectors (clk_fast) ───
    input  wire                        isram_we_a,
    input  wire [ISRAM_ADDR_W-1:0]     isram_waddr_a,
    input  wire [ISRAM_DATA_W-1:0]     isram_wdata_a,

    // ── LSRAM Port A: host writes PSum LUT table (clk_fast) ──
    input  wire                        lsram_we_a,
    input  wire [LSRAM_ADDR_W-1:0]     lsram_waddr_a,
    input  wire [LSRAM_DATA_W-1:0]     lsram_wdata_a,

    // ── OSRAM Port B: host reads output matrix (clk_fast) ────
    input  wire                        osram_re_b,
    input  wire [OSRAM_ADDR_W-1:0]     osram_raddr_b,
    output wire [SPAD_DATA_W-1:0]      osram_rdata_b
);

    // =========================================================
    //  Generated slow clock
    // =========================================================
    wire clk_slow;

    ClkDiv #(.RATIO_WD(DIV_RATIO_W)) u_clk_div (
        .i_ref_clk  (clk_fast),
        .i_rst      (rst_n),
        .i_clk_en   (1'b1),
        .i_div_ratio(div_ratio),
        .o_div_clk  (clk_slow)
    );

    // =========================================================
    //  System-level busy register (clk_fast)
    //  Set on start, cleared when imm_done crosses back to fast.
    // =========================================================
    wire ccm_start_pulse;
    wire ccm_done_pulse;     // from ccm_controller
    wire imm_done_slow;      // from IMM_CTRL (clk_slow)
    wire imm_done_fast;      // CDC of imm_done_slow → clk_fast

    reg sys_busy;

    always @(posedge clk_fast or negedge rst_n) begin
        if (!rst_n)                          sys_busy <= 1'b0;
        else if (top2sys_valid && !sys_busy) sys_busy <= 1'b1;
        else if (imm_done_fast)              sys_busy <= 1'b0;
    end

    assign sys2top_ready  = !sys_busy;
    assign sys_done       = imm_done_fast;
    assign ccm_start_pulse = top2sys_valid && !sys_busy;  // 1-cycle; gated by sys_busy

    // =========================================================
    //  CDC: start pulse (clk_fast → clk_slow) → IMM_CTRL kick
    // =========================================================
    wire imm_start_slow;

    cdc_pulse_sync #(.N_SYNC(3)) u_cdc_start (
        .src_clk    (clk_fast),
        .src_resetn (rst_n),
        .src_pulse_i(ccm_start_pulse),
        .dst_clk    (clk_slow),
        .dst_resetn (rst_n),
        .dst_pulse_o(imm_start_slow)
    );

    // =========================================================
    //  CDC: imm_done (clk_slow → clk_fast) → sys_done
    // =========================================================
    cdc_pulse_sync #(.N_SYNC(3)) u_cdc_done (
        .src_clk    (clk_slow),
        .src_resetn (rst_n),
        .src_pulse_i(imm_done_slow),
        .dst_clk    (clk_fast),
        .dst_resetn (rst_n),
        .dst_pulse_o(imm_done_fast)
    );

    // =========================================================
    //  CSRAM — Centroid data
    //    Port A (clk_fast) : host writes centroid vectors
    //    Port B (clk_fast) : CCM centroid_buffer reads
    // =========================================================
    wire                    csram_re_b;
    wire [CSRAM_ADDR_W-1:0] csram_raddr_b;
    wire [CSRAM_DATA_W-1:0] csram_rdata_b;

    tdp_sram #(
        .DEPTH (K * NUM_CENTROIDS),
        .DATA_W(CSRAM_DATA_W),
        .ADDR_W(CSRAM_ADDR_W)
    ) u_csram (
        .clk_a  (clk_fast),    .we_a  (csram_we_a),    .waddr_a(csram_waddr_a), .wdata_a(csram_wdata_a),
        .clk_b  (clk_fast),    .re_b  (csram_re_b),    .raddr_b(csram_raddr_b), .rdata_b(csram_rdata_b)
    );

    // =========================================================
    //  ISRAM — Input vectors
    //    Port A (clk_fast) : host writes input vectors
    //    Port B (clk_fast) : CCM input_buffer reads
    // =========================================================
    wire                    isram_re_b;
    wire [ISRAM_ADDR_W-1:0] isram_raddr_b;
    wire [ISRAM_DATA_W-1:0] isram_rdata_b;

    tdp_sram #(
        .DEPTH (K * M),
        .DATA_W(ISRAM_DATA_W),
        .ADDR_W(ISRAM_ADDR_W)
    ) u_isram (
        .clk_a  (clk_fast),    .we_a  (isram_we_a),    .waddr_a(isram_waddr_a), .wdata_a(isram_wdata_a),
        .clk_b  (clk_fast),    .re_b  (isram_re_b),    .raddr_b(isram_raddr_b), .rdata_b(isram_rdata_b)
    );

    // =========================================================
    //  LSRAM — PSum LUT table
    //    Port A (clk_fast) : host writes LUT entries
    //    Port B (clk_slow) : PSumLUT reads (TDP BRAM CDC boundary)
    // =========================================================
    wire                     lsram_re_b;
    wire [MEM_ADDR_WIDTH-1:0] lsram_raddr_b;  // driven by PSumLUT (MEM_ADDR_WIDTH wide)
    wire [LSRAM_DATA_W-1:0]   lsram_rdata_b;

    tdp_sram #(
        .DEPTH (K * N * NUM_CENTROIDS),
        .DATA_W(LSRAM_DATA_W),
        .ADDR_W(LSRAM_ADDR_W)
    ) u_lsram (
        .clk_a  (clk_fast),    .we_a  (lsram_we_a),    .waddr_a(lsram_waddr_a),              .wdata_a(lsram_wdata_a),
        .clk_b  (clk_slow),    .re_b  (lsram_re_b),    .raddr_b(lsram_raddr_b[LSRAM_ADDR_W-1:0]), .rdata_b(lsram_rdata_b)
    );

    // =========================================================
    //  OSRAM — Output matrix
    //    Port A (clk_slow) : Scratchpad writes result rows
    //    Port B (clk_fast) : host reads (TDP BRAM CDC boundary)
    //
    //  Scratchpad outputs MEM_ADDR_WIDTH-wide address; OSRAM uses
    //  OSRAM_ADDR_W bits (upper bits of spad2out_addr are always 0).
    // =========================================================
    wire                    osram_we_a;
    wire [MEM_ADDR_WIDTH-1:0] osram_waddr_full;   // from IMM/Scratchpad
    wire [SPAD_DATA_W-1:0]  osram_wdata_a;

    tdp_sram #(
        .DEPTH (M * N),
        .DATA_W(SPAD_DATA_W),
        .ADDR_W(OSRAM_ADDR_W)
    ) u_osram (
        .clk_a  (clk_slow),    .we_a  (osram_we_a),    .waddr_a(osram_waddr_full[OSRAM_ADDR_W-1:0]), .wdata_a(osram_wdata_a),
        .clk_b  (clk_fast),    .re_b  (osram_re_b),    .raddr_b(osram_raddr_b),                       .rdata_b(osram_rdata_b)
    );

    // =========================================================
    //  ccm_controller (clk_fast)
    //  Drives CCM's Centroid Buffer and Input Buffer exclusively.
    // =========================================================
    wire [CSRAM_ADDR_W-1:0] ccm_ctrl2cb_start_addr;
    wire                    ccm_ctrl2cb_addr_valid;
    wire                    ccm_cb2ctrl_addr_ready;

    wire [ISRAM_ADDR_W-1:0] ccm_ctrl2ib_start_addr;
    wire                    ccm_ctrl2ib_valid;
    wire                    ccm_ib2ctrl_ready;

    wire                    ccm_ccu_done;

    ccm_controller #(
        .N               (N),
        .NUM_SUBSPACES   (K),
        .NUM_INPUTS      (M),
        .NUM_CENTROIDS   (NUM_CENTROIDS),
        .ISRAM_ADDR_WIDTH(ISRAM_ADDR_W),
        .CSRAM_ADDR_WIDTH(CSRAM_ADDR_W)
    ) u_ccm_ctrl (
        .clk                (clk_fast),
        .rst_n              (rst_n),
        .ccm_start_pulse    (ccm_start_pulse),
        .ccm_done_pulse     (ccm_done_pulse),
        // Centroid Buffer
        .ctrl2cb_start_addr (ccm_ctrl2cb_start_addr),
        .ctrl2cb_valid      (ccm_ctrl2cb_addr_valid),
        .cb2ctrl_ready      (ccm_cb2ctrl_addr_ready),
        // Input Buffer
        .ctrl2ib_start_addr (ccm_ctrl2ib_start_addr),
        .ctrl2ib_valid      (ccm_ctrl2ib_valid),
        .ib2ctrl_ready      (ccm_ib2ctrl_ready),
        // CCU status
        .ccu_done           (ccm_ccu_done)
    );

    // =========================================================
    //  CCM block (clk_fast)
    //  centroid_buffer + input_buffer + CCU, all on clk_fast.
    // =========================================================
    wire                      fifo2ccu_ready;    // FIFO back-pressure → CCU
    wire [CENTROID_IDX_W-1:0] ccu2fifo_idx;     // index output → FIFO write
    wire                      ccu2fifo_valid;    // FIFO write valid

    CCM #(
        .VECTOR_LENGTH      (VECTOR_LENGTH),
        .VALUE_WIDTH        (VALUE_WIDTH),
        .NUM_INPUTS         (M),
        .NUM_CENTROIDS      (NUM_CENTROIDS),
        .CENTROID_ADDR_WIDTH(CENTROID_IDX_W),
        .CSRAM_ADDR_WIDTH   (CSRAM_ADDR_W),
        .INPUT_ADDR_WIDTH   ($clog2(M)),
        .ISRAM_ADDR_WIDTH   (ISRAM_ADDR_W)
    ) u_ccm (
        .clk                (clk_fast),
        .rst_n              (rst_n),
        // Centroid Buffer ↔ ccm_controller
        .ctrl2cb_start_addr (ccm_ctrl2cb_start_addr),
        .ctrl2cb_addr_valid (ccm_ctrl2cb_addr_valid),
        .cb2ctrl_addr_ready (ccm_cb2ctrl_addr_ready),
        // Centroid Buffer ↔ CSRAM
        .cb2csb_re          (csram_re_b),
        .cb2csb_addr        (csram_raddr_b),
        .csb2cb_data        (csram_rdata_b),
        // Input Buffer ↔ ccm_controller
        .ctrl2ib_start_addr (ccm_ctrl2ib_start_addr),
        .ctrl2ib_valid      (ccm_ctrl2ib_valid),
        .ib2ctrl_ready      (ccm_ib2ctrl_ready),
        // Input Buffer ↔ ISRAM
        .ib2isb_re          (isram_re_b),
        .ib2isb_addr        (isram_raddr_b),
        .isb2ib_data        (isram_rdata_b),
        // CCU ↔ FIFO
        .fifo2ccu_ready     (fifo2ccu_ready),
        .ccu2fifo_idx       (ccu2fifo_idx),
        .ccu2fifo_valid     (ccu2fifo_valid),
        // CCU done → ccm_controller
        .ccu_done           (ccm_ccu_done)
    );

    // =========================================================
    //  Async FIFO — CCM (fast) → PSumLUT (slow)
    //  Carries centroid indices produced by CCU to PSumLUT consumer.
    //  Provides backpressure (W_ready = fifo2ccu_ready) to stall CCU
    //  when FIFO is full.
    // =========================================================
    wire                      fifo2psum_valid;
    wire [CENTROID_IDX_W-1:0] fifo2psum_index;
    wire                      psum2fifo_ready;

    Async_fifo #(
        .D_SIZE     (CENTROID_IDX_W),
        .FIFO_DEPTH (FIFO_DEPTH),
        .SYNC_STAGE (3)
    ) u_fifo (
        // Write side — clk_fast (CCU produces)
        .W_clk  (clk_fast),
        .W_rst_n(rst_n),
        .W_valid(ccu2fifo_valid),
        .W_ready(fifo2ccu_ready),
        .WR_DATA(ccu2fifo_idx),
        // Read side — clk_slow (PSumLUT consumes)
        .R_clk  (clk_slow),
        .R_rst_n(rst_n),
        .R_ready(psum2fifo_ready),
        .R_valid(fifo2psum_valid),
        .RD_DATA(fifo2psum_index),
        // Status (tie off — back-pressure handled through W_ready/R_valid)
        .FULL   (),
        .EMPTY  ()
    );

    // =========================================================
    //  IMM_CTRL (clk_slow)
    //  Sequences PSumLUT and Scratchpad for K×N (subspace, column)
    //  pairs. Started concurrently with ccm_controller via CDC pulse.
    // =========================================================
    wire [MEM_ADDR_WIDTH-1:0] ctrl2psum_start_addr;
    wire                      ctrl2psum_addr_valid;
    wire                      psum2ctrl_addr_ready;
    wire [MEM_ADDR_WIDTH-1:0] ctrl2spad_start_addr;
    wire                      ctrl2spad_addr_valid;
    wire                      spad2ctrl_addr_ready;
    wire                      spad2ctrl_done;
    wire                      imm2top_ready;

    IMM_CTRL #(
        .NUM_CENTROIDS  (NUM_CENTROIDS),
        .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH),
        .N              (N),
        .K              (K)
    ) u_imm_ctrl (
        .clk                  (clk_slow),
        .rst_n                (rst_n),
        .k_total              (k_total),
        .n_total              (n_total),
        .top2imm_valid        (imm_start_slow),         // CDC'd start pulse
        .imm2top_ready        (imm2top_ready),
        .imm_done             (imm_done_slow),          // CDC'd back to fast domain
        .spad_out_addr        (spad_out_addr),
        .ctrl2psum_start_addr (ctrl2psum_start_addr),
        .ctrl2psum_addr_valid (ctrl2psum_addr_valid),
        .psum2ctrl_addr_ready (psum2ctrl_addr_ready),
        .ctrl2spad_start_addr (ctrl2spad_start_addr),
        .ctrl2spad_addr_valid (ctrl2spad_addr_valid),
        .spad2ctrl_addr_ready (spad2ctrl_addr_ready),
        .spad2ctrl_done       (spad2ctrl_done)
    );

    // =========================================================
    //  IMM block (clk_slow)
    //  PSumLUT: loads LUT bank from LSRAM, pops FIFO indices,
    //           pushes partial sums to Scratchpad.
    //  Scratchpad: accumulates M×N result matrix, streams to OSRAM.
    // =========================================================
    IMM #(
        .NUM_CENTROIDS      (NUM_CENTROIDS),
        .CENTROID_ADDR_WIDTH(CENTROID_IDX_W),
        .MEM_ADDR_WIDTH     (MEM_ADDR_WIDTH),
        .VALUE_WIDTH_LUT    (LSRAM_DATA_W),
        .DATA_WIDTH_Spad    (SPAD_DATA_W),
        .M                  (M),
        .N                  (N),
        .K                  (K)
    ) u_imm (
        .clk                  (clk_slow),
        .rst_n                (rst_n),
        // IMM_CTRL → PSumLUT
        .ctrl2psum_start_addr (ctrl2psum_start_addr),
        .ctrl2psum_addr_valid (ctrl2psum_addr_valid),
        .psum2ctrl_addr_ready (psum2ctrl_addr_ready),
        // LSRAM → PSumLUT
        .mem2psum_lut_value   (lsram_rdata_b),
        .psum2mem_re          (lsram_re_b),
        .psum2mem_addr        (lsram_raddr_b),
        // Async FIFO → PSumLUT
        .fifo2psum_valid      (fifo2psum_valid),
        .fifo2psum_index      (fifo2psum_index),
        .psum2fifo_ready      (psum2fifo_ready),
        // IMM_CTRL → Scratchpad
        .ctrl2spad_start_addr (ctrl2spad_start_addr),
        .ctrl2spad_addr_valid (ctrl2spad_addr_valid),
        .spad2ctrl_addr_ready (spad2ctrl_addr_ready),
        // Scratchpad → OSRAM
        .spad2out_we          (osram_we_a),
        .spad2out_data        (osram_wdata_a),
        .spad2out_addr        (osram_waddr_full),
        // Scratchpad → IMM_CTRL (streaming done)
        .spad2ctrl_done       (spad2ctrl_done)
    );

endmodule

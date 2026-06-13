// =============================================================
//  SYSTEM_CTRL_TOP  —  Single-clock controller wrapper
//
//  For simulation / single-clock integration only.
//  For the full dual-clock design (fast + slow) use SYSTEM_TOP.
//
//  Concurrent operation:
//    top2sys_valid → starts ccm_controller AND IMM_CTRL simultaneously
//    ccm_controller: exclusively drives CCM's CB/IB/CCU
//    IMM_CTRL:       exclusively drives PSum LUT + Scratchpad
//    FIFO (external) carries CCU indices from CCM to PSumLUT
//    sys_done = imm_done (IMM is the last stage to complete)
//
//  sys2top_ready = !ccm_busy && imm2top_ready
// =============================================================

module SYSTEM_CTRL_TOP #(
    parameter NUM_CENTROIDS    = 16,
    parameter MEM_ADDR_WIDTH   = 10,
    parameter M                = 20,         // input rows per subspace (= NUM_INPUTS)
    parameter K                = 16,         // number of subspaces
    parameter N                = 16,         // output columns
    parameter ISRAM_ADDR_WIDTH = 10,
    parameter CSRAM_ADDR_WIDTH = 10,

    // Derived
    parameter K_CNT_WIDTH      = $clog2(K + 1),
    parameter N_CNT_WIDTH      = $clog2(N + 1)
)(
    // ── Global ────────────────────────────────────────────────
    input  wire clk,
    input  wire rst_n,

    // ── System handshake ─────────────────────────────────────
    input  wire                        top2sys_valid,
    output wire                        sys2top_ready,
    output wire                        sys_done,

    // ── Runtime loop bounds ──────────────────────────────────
    input  wire [K_CNT_WIDTH-1:0]      k_total,
    input  wire [N_CNT_WIDTH-1:0]      n_total,

    // ── Scratchpad output base address ────────────────────────
    input  wire [MEM_ADDR_WIDTH-1:0]   spad_out_addr,

    // ── Centroid Buffer interface (ccm_controller → CCM) ─────
    output wire                        addr_valid,
    input  wire                        addr_ready,
    output wire [CSRAM_ADDR_WIDTH-1:0] cb_start_addr,

    // ── Input Buffer interface (ccm_controller → CCM) ────────
    output wire                        ctrl2ib_valid,
    input  wire                        ctrl2ib_ready,
    output wire [ISRAM_ADDR_WIDTH-1:0] initial_idx,

    // ── CCU status (CCM → ccm_controller) ────────────────────
    input  wire                        ccu_done,

    // ── PSum LUT interface (IMM_CTRL → IMM) ──────────────────
    output wire [MEM_ADDR_WIDTH-1:0]   ctrl2psum_start_addr,
    output wire                        ctrl2psum_addr_valid,
    input  wire                        psum2ctrl_addr_ready,

    // ── Scratchpad interface (IMM_CTRL ↔ IMM) ─────────────────
    output wire [MEM_ADDR_WIDTH-1:0]   ctrl2spad_start_addr,
    output wire                        ctrl2spad_addr_valid,
    input  wire                        spad2ctrl_addr_ready,
    input  wire                        spad2ctrl_done
);

    // =========================================================
    //  CCM busy tracking (ccm_controller has no ready output)
    // =========================================================
    wire ccm_done_pulse;
    wire ccm_start_pulse;
    reg  ccm_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ccm_busy <= 1'b0;
        else if (ccm_start_pulse)
            ccm_busy <= 1'b1;
        else if (ccm_done_pulse)
            ccm_busy <= 1'b0;
    end

    wire imm2top_ready;
    wire imm_done;

    assign sys2top_ready  = !ccm_busy && imm2top_ready;
    assign sys_done       = imm_done;
    // One-cycle pulse: sys2top_ready gates itself, so ccm_start_pulse fires only once
    assign ccm_start_pulse = top2sys_valid && sys2top_ready;

    // =========================================================
    //  ccm_controller — drives CCM's CB / IB / CCU
    // =========================================================
    ccm_controller #(
        .N               (N),
        .NUM_SUBSPACES   (K),
        .NUM_INPUTS      (M),
        .NUM_CENTROIDS   (NUM_CENTROIDS),
        .ISRAM_ADDR_WIDTH(ISRAM_ADDR_WIDTH),
        .CSRAM_ADDR_WIDTH(CSRAM_ADDR_WIDTH)
    ) u_ccm_ctrl (
        .clk                (clk),
        .rst_n              (rst_n),
        .ccm_start_pulse    (ccm_start_pulse),
        .ccm_done_pulse     (ccm_done_pulse),
        // IB
        .ctrl2ib_start_addr (initial_idx),
        .ctrl2ib_valid      (ctrl2ib_valid),
        .ib2ctrl_ready      (ctrl2ib_ready),
        // CB
        .ctrl2cb_start_addr (cb_start_addr),
        .ctrl2cb_valid      (addr_valid),
        .cb2ctrl_ready      (addr_ready),
        // CCU
        .ccu_done           (ccu_done)
    );

    // =========================================================
    //  IMM_CTRL — drives PSum LUT + Scratchpad
    //  Triggered simultaneously with ccm_controller
    // =========================================================
    IMM_CTRL #(
        .NUM_CENTROIDS  (NUM_CENTROIDS),
        .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH),
        .N              (N),
        .K              (K)
    ) u_imm_ctrl (
        .clk                  (clk),
        .rst_n                (rst_n),
        .k_total              (k_total),
        .n_total              (n_total),
        .top2imm_valid        (ccm_start_pulse),   // same trigger as ccm_controller
        .imm2top_ready        (imm2top_ready),
        .imm_done             (imm_done),
        .spad_out_addr        (spad_out_addr),
        .ctrl2psum_start_addr (ctrl2psum_start_addr),
        .ctrl2psum_addr_valid (ctrl2psum_addr_valid),
        .psum2ctrl_addr_ready (psum2ctrl_addr_ready),
        .ctrl2spad_start_addr (ctrl2spad_start_addr),
        .ctrl2spad_addr_valid (ctrl2spad_addr_valid),
        .spad2ctrl_addr_ready (spad2ctrl_addr_ready),
        .spad2ctrl_done       (spad2ctrl_done)
    );

endmodule

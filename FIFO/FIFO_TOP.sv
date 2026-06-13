// ============================================================
//  Async_fifo — Top-level wrapper
// ============================================================
module Async_fifo #(
    parameter D_SIZE        = 8,
    parameter FIFO_DEPTH    = 8,
    parameter max_fifo_addr = $clog2(FIFO_DEPTH),
    parameter SYNC_STAGE    = 2
)(
    // ---------- Write clock domain ----------
    input  wire                  W_clk,
    input  wire                  W_rst_n,
    input  wire                  W_valid,      // Handshake: producer has data
    output wire                  W_ready,      // Handshake: FIFO accepts data (= !FULL)
    input  wire [D_SIZE-1:0]     WR_DATA,

    // ---------- Read clock domain ----------
    input  wire                  R_clk,
    input  wire                  R_rst_n,
    input  wire                  R_ready,      // Handshake: consumer ready to receive
    output wire                  R_valid,      // Handshake: FIFO has data (= !EMPTY)
    output wire [D_SIZE-1:0]     RD_DATA,

    // ---------- Optional debug / status ----------
    output wire                  FULL,
    output wire                  EMPTY
);

    // --------------------------------------------------------
    //  Internal wires
    // --------------------------------------------------------
    wire [max_fifo_addr:0]   r_ptr, w_ptr;          // Gray pointers
    wire [max_fifo_addr-1:0] w_addr, r_addr;         // Binary addresses
    wire [max_fifo_addr:0]   Wq2_rptr, rq2_wptr;    // Synchronized pointers
    wire                     W_clk_en, R_clk_en;    // Memory clock-enables

    // --------------------------------------------------------
    //  Memory
    // --------------------------------------------------------
    FIFO_MEM_CNTRL #(
        .DATA_WIDTH    (D_SIZE),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .max_fifo_addr (max_fifo_addr)
    ) MEM (
        .W_clk    (W_clk),
        .R_clk    (R_clk),
        .RD_DATA  (RD_DATA),
        .WR_DATA  (WR_DATA),
        .R_clk_en (R_clk_en),
        .W_clk_en (W_clk_en),
        .rst_n    (W_rst_n),
        .R_rst_n  (R_rst_n),   
        .w_addr   (w_addr),
        .r_addr   (r_addr)
    );

    // --------------------------------------------------------
    //  Write controller
    // --------------------------------------------------------
    FIFO_WR #(
        .DATA_WIDTH    (D_SIZE),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .max_fifo_addr (max_fifo_addr)
    ) W_ptr (
        .W_clk     (W_clk),
        .W_rst_n   (W_rst_n),
        .W_valid   (W_valid),
        .W_ready   (W_ready),
        .Wq2_rptr  (Wq2_rptr),
        .W_clk_en  (W_clk_en),
        .w_gptr    (w_ptr),
        .w_addr    (w_addr),
        .FULL      (FULL)
    );

    // --------------------------------------------------------
    //  Read controller
    // --------------------------------------------------------
    FIFO_RD #(
        .DATA_WIDTH    (D_SIZE),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .max_fifo_addr (max_fifo_addr)
    ) R_ptr (
        .R_clk     (R_clk),
        .R_rst_n   (R_rst_n),
        .R_ready   (R_ready),
        .R_valid   (R_valid),
        .rq2_wptr  (rq2_wptr),
        .r_gptr    (r_ptr),
        .r_addr    (r_addr),
        .R_clk_en  (R_clk_en),
        .EMPTY     (EMPTY)
    );

    // --------------------------------------------------------
    //  Synchronizers
    // --------------------------------------------------------
    SYNC_W2R #(
        .NUM_STAGES    (SYNC_STAGE),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .DATA_WIDTH    (D_SIZE),
        .max_fifo_addr (max_fifo_addr)
    ) write_sync (
        .clk      (R_clk),
        .rst_n    (R_rst_n),
        .w_ptr    (w_ptr),
        .SYNC_W2R (rq2_wptr)
    );

    SYNC_R2W #(
        .NUM_STAGES    (SYNC_STAGE),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .DATA_WIDTH    (D_SIZE),
        .max_fifo_addr (max_fifo_addr)
    ) read_sync (
        .clk      (W_clk),
        .rst_n    (W_rst_n),
        .r_ptr    (r_ptr),
        .SYNC_R2W (Wq2_rptr)
    );

endmodule : Async_fifo

// ============================================================
//  FIFO_WR — Write domain controller
// ============================================================
module FIFO_WR #(
    parameter DATA_WIDTH   = 8,
    parameter FIFO_DEPTH   = 16,
    parameter max_fifo_addr = $clog2(FIFO_DEPTH)
)(
    input  wire                      W_clk,       // Write domain clock
    input  wire                      W_rst_n,     // Write domain async reset (active-low)
    // ---------- Handshake (write side) ----------
    input  wire                      W_valid,     // Producer: data is valid / wants to write
    output wire                      W_ready,     // Consumer: FIFO can accept data (= !FULL)
    // ---------- Gray-pointer in from sync ----------
    input  wire [max_fifo_addr:0]    Wq2_rptr,    // Synced read gray-pointer
    // ---------- Internal outputs ----------
    output wire                      W_clk_en,    // Clock-enable for memory (actual write strobe)
    output reg  [max_fifo_addr:0]    w_gptr,      // Gray-coded write pointer (to sync chain)
    output reg  [max_fifo_addr-1:0]  w_addr,      // Binary write address for memory
    // ---------- Status (kept for visibility / debug) ----------
    output reg                       FULL
);

    // --------------------------------------------------------
    //  Internal binary pointer
    // --------------------------------------------------------
    reg [max_fifo_addr:0] w_ptr;

    // Next Gray value (combinational)
    wire [max_fifo_addr:0] w_gnext;
    assign w_gnext = (w_ptr + 1'b1) ^ ((w_ptr + 1'b1) >> 1);

    // --------------------------------------------------------
    //  FULL flag — Clifford Cummings Gray-code comparison
    //  Full when the two MSBs are INVERTED and the rest are EQUAL
    // --------------------------------------------------------
    assign FULL = (w_gnext == {~Wq2_rptr[max_fifo_addr:max_fifo_addr-1],
                                Wq2_rptr[max_fifo_addr-2:0]});

    // --------------------------------------------------------
    //  Handshake outputs
    // --------------------------------------------------------
    assign W_ready   = ~FULL;                // FIFO is ready when not full
    assign W_clk_en  = W_valid & W_ready;   // Actual write = both sides agree

    // --------------------------------------------------------
    //  Sequential pointer update
    // --------------------------------------------------------
    always @(posedge W_clk or negedge W_rst_n) begin
        if (~W_rst_n) begin
            w_ptr  <= {(max_fifo_addr+1){1'b0}};
            w_addr <= {max_fifo_addr{1'b0}};
            w_gptr <= {(max_fifo_addr+1){1'b0}};
        end
        else if (W_clk_en) begin
            w_ptr  <= w_ptr + 1'b1;
            w_addr <= w_addr + 1'b1;
            w_gptr <= w_gnext;   // Use pre-computed next Gray value
        end
    end

endmodule : FIFO_WR

// ============================================================
//  FIFO_RD — Read domain controller
// ============================================================
module FIFO_RD #(
    parameter DATA_WIDTH    = 8,
    parameter FIFO_DEPTH    = 16,
    parameter max_fifo_addr = $clog2(FIFO_DEPTH)
)(
    input  wire                      R_clk,      // Read domain clock
    input  wire                      R_rst_n,    // Read domain async reset (active-low)
    // ---------- Handshake (read side) ----------
    input  wire                      R_ready,    // ready to accept data
    output wire                      R_valid,    // FIFO has data (= !EMPTY)
    // ---------- Gray-pointer in from sync ----------
    input  wire [max_fifo_addr:0]    rq2_wptr,   // Synced write gray-pointer
    // ---------- Internal outputs ----------
    output reg  [max_fifo_addr:0]    r_gptr,     // Gray-coded read pointer (to sync chain)
    output reg  [max_fifo_addr-1:0]  r_addr,     // Binary read address for memory
    // ---------- Clock-enable for memory ----------
    output wire                      R_clk_en,
    // ---------- Status (kept for visibility / debug) ----------
    output reg                       EMPTY
);

    // --------------------------------------------------------
    //  Internal binary pointer
    // --------------------------------------------------------
    reg [max_fifo_addr:0] r_ptr;

    // Next Gray value — used to update r_gptr on a read
    wire [max_fifo_addr:0] r_gnext;
    assign r_gnext = (r_ptr + 1'b1) ^ ((r_ptr + 1'b1) >> 1);

    // BUG FIX 2: Current Gray value (combinational).
    //   r_gcur tracks the CURRENT read position in Gray code.
    //   After reset r_ptr=0 → r_gcur=0 = rq2_wptr=0 → EMPTY=1 ✓
    //   After a read r_ptr advances, r_gcur follows immediately → no lag.
    wire [max_fifo_addr:0] r_gcur;
    assign r_gcur = r_ptr ^ (r_ptr >> 1);

    // --------------------------------------------------------
    //  Handshake outputs
    // --------------------------------------------------------
    assign R_valid  = ~EMPTY;               // FIFO valid when not empty
    assign R_clk_en = R_ready & R_valid;    // Actual read = both sides agree

    // --------------------------------------------------------
    //  Sequential pointer update
    // --------------------------------------------------------
    always @(posedge R_clk or negedge R_rst_n) begin
        if (~R_rst_n) begin
            r_ptr  <= {(max_fifo_addr+1){1'b0}};
            r_addr <= {max_fifo_addr{1'b0}};
            r_gptr <= {(max_fifo_addr+1){1'b0}};
        end
        else if (R_clk_en) begin
            r_ptr  <= r_ptr + 1'b1;
            r_addr <= r_addr + 1'b1;
            r_gptr <= r_gnext;
        end
    end

    // --------------------------------------------------------
    //  EMPTY flag
    // --------------------------------------------------------
    
    always @(posedge R_clk or negedge R_rst_n) begin
        if (~R_rst_n)
            EMPTY <= 1'b1;             // Reset: FIFO starts empty ✓
        else
            EMPTY <= (r_gcur == rq2_wptr);  // BUG FIX 2
    end

endmodule : FIFO_RD

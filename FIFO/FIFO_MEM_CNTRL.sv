// ============================================================
//  FIFO_MEM_CNTRL — Dual-port memory
// ============================================================
module FIFO_MEM_CNTRL #(
    parameter DATA_WIDTH    = 8,
    parameter FIFO_DEPTH    = 16,
    parameter max_fifo_addr = $clog2(FIFO_DEPTH)
)(
    // Write domain
    input  wire                      W_clk,
    input  wire                      W_clk_en,            // Write enable (from FIFO_WR)
    input  wire                      rst_n,               // Write-domain reset  (W_rst_n)
    // Read domain
    input  wire                      R_clk,
    input  wire                      R_clk_en,            // Read enable  (from FIFO_RD)
    input  wire                      R_rst_n,             // BUG FIX: read-domain reset
    input  wire [max_fifo_addr-1:0]  w_addr,
    input  wire [max_fifo_addr-1:0]  r_addr,
    input  wire [DATA_WIDTH-1:0]     WR_DATA,
    output reg  [DATA_WIDTH-1:0]     RD_DATA
);

    reg [DATA_WIDTH-1:0] FIFO_MEM [0:FIFO_DEPTH-1];
    integer i;

    // ------ Write port (write-domain reset) ------
    always @(posedge W_clk or negedge rst_n) begin
        if (~rst_n) begin
            for (i = 0; i < FIFO_DEPTH; i = i + 1)
                FIFO_MEM[i] <= {DATA_WIDTH{1'b0}};
        end
        else if (W_clk_en)
            FIFO_MEM[w_addr] <= WR_DATA;
    end

    // ------ Read port (First-Word-Fall-Through) ------
    // Present the current head entry combinationally so RD_DATA is valid on the
    // SAME cycle that R_valid is high (before the pop advances r_addr). The
    // consumer (PSumLUT) reads Bank[fifo2psum_index] on the pop cycle, so it
    // needs the head index available at that moment.
    //
    // The previous registered read (RD_DATA <= FIFO_MEM[r_addr] on R_clk_en)
    // delivered each entry ONE cycle late: the first pop returned the reset
    // value 0 (a bubble) and every real index was shifted one position later,
    // with the last index's data never read — shifting the whole output matrix
    // down by one row (row 0 = junk, row 19 lost). CDC safety is preserved:
    // the Gray-coded pointer synchronisation guarantees r_addr only addresses
    // entries that are already fully written and stable.
    always @(*) begin
        RD_DATA = FIFO_MEM[r_addr];
    end

endmodule : FIFO_MEM_CNTRL
